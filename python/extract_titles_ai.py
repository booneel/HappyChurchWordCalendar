from __future__ import annotations

import argparse
import base64
import concurrent.futures
import datetime as dt
import io
import json
import os
import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import fitz  # PyMuPDF
from dotenv import load_dotenv
from openai import OpenAI
from PIL import Image


START_PAGE = 4
DAY_COUNT = 365

# 제목 위치가 포함되도록 상단 절반 정도를 사용합니다.
# 이미지 예시 기준 날짜 + 제목 + 본문 첫 줄까지 포함하여 Vision 모델이
# "날짜 아래 / 본문 위"라는 구조를 판단할 수 있게 합니다.
CROP_LEFT = 0.02
CROP_TOP = 0.06
CROP_RIGHT = 0.98
CROP_BOTTOM = 0.53

PROMPT = """이 이미지는 한국어 '하루 묵상 카드'의 상단 영역입니다.

해야 할 일:
- 날짜(월/일 숫자) 아래에 있고, 성경 본문 위에 있는 '묵상 제목 전체'를 정확히 읽으세요.
- 제목은 손글씨, 붓글씨, 일반 글씨, 서로 다른 색/크기/폰트로 여러 조각으로 나뉘어 있을 수 있습니다.
- 시각적으로 하나의 제목 구절을 이루는 조각은 반드시 모두 합쳐서 완전한 제목으로 반환하세요.
- OCR처럼 한 단어만 고르지 마세요.

예시:
- '움직임' + '을 가질 때' → '움직임을 가질 때'
- '하나님의' + '뜻' + '을 행하는 자' → '하나님의 뜻을 행하는 자'
- '충성' → '충성'

제외:
- 월/일 날짜 숫자
- 성경 본문
- 성경 구절 표기(예: 요 20:23, 마 25:21)
- HAPPY CHURCH
- 페이지 장식 문구

반드시 아래 JSON 하나만 출력하세요:
{"title":"정확한 전체 제목","confidence":0.00}

confidence:
- 0.95~1.00: 제목 전체가 명확함
- 0.80~0.94: 거의 확실함
- 0.50~0.79: 일부 글자가 애매함
- 0.00~0.49: 제목 전체를 자신 있게 읽기 어려움
"""


@dataclass
class PageJob:
    key: str
    date: dt.date
    page_number: int


def month_day_key(date: dt.date) -> str:
    return f"{date.month:02d}-{date.day:02d}"


def jobs_for_year(year: int) -> list[PageJob]:
    start = dt.date(year, 1, 1)
    end = dt.date(year, 12, 31)
    count = (end - start).days + 1
    if count != 365:
        raise SystemExit(
            f"{year}년은 윤년입니다. 현재 도구는 365일 PDF 기준입니다. "
            "윤년 PDF는 매핑을 별도로 정해야 합니다."
        )

    jobs: list[PageJob] = []
    for index in range(DAY_COUNT):
        date = start + dt.timedelta(days=index)
        jobs.append(
            PageJob(
                key=month_day_key(date),
                date=date,
                page_number=START_PAGE + index,
            )
        )
    return jobs


def parse_only(value: str | None) -> set[str] | None:
    if not value:
        return None
    result: set[str] = set()
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        if not re.fullmatch(r"\d{2}-\d{2}", item):
            raise SystemExit(
                f"--only 값 형식 오류: {item}. 예: --only 09-13,09-23,10-27"
            )
        result.add(item)
    return result


def render_crop(
    pdf_path: Path,
    page_number: int,
    crop_path: Path,
    zoom: float = 3.0,
) -> bytes:
    """PDF 한 페이지의 제목 주변 영역을 PNG로 렌더링합니다."""
    document = fitz.open(pdf_path)
    try:
        if page_number < 1 or page_number > document.page_count:
            raise ValueError(
                f"PDF 페이지 범위 오류: {page_number} / {document.page_count}"
            )

        page = document.load_page(page_number - 1)
        rect = page.rect
        crop = fitz.Rect(
            rect.x0 + rect.width * CROP_LEFT,
            rect.y0 + rect.height * CROP_TOP,
            rect.x0 + rect.width * CROP_RIGHT,
            rect.y0 + rect.height * CROP_BOTTOM,
        )
        matrix = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(
            matrix=matrix,
            clip=crop,
            alpha=False,
        )
        png_bytes = pix.tobytes("png")
    finally:
        document.close()

    # 지나치게 큰 이미지는 API 전송량을 줄이기 위해 폭 1500 정도로 축소.
    image = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    if image.width > 1500:
        ratio = 1500 / image.width
        image = image.resize(
            (1500, max(1, int(image.height * ratio))),
            Image.Resampling.LANCZOS,
        )

    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    final_bytes = buffer.getvalue()

    crop_path.parent.mkdir(parents=True, exist_ok=True)
    crop_path.write_bytes(final_bytes)
    return final_bytes


def image_data_url(png_bytes: bytes) -> str:
    encoded = base64.b64encode(png_bytes).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def parse_model_json(text: str) -> dict[str, Any]:
    text = text.strip()

    # 코드펜스 제거
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.S)
        if not match:
            raise ValueError(f"JSON을 찾지 못했습니다: {text[:300]}")
        data = json.loads(match.group(0))

    title = str(data.get("title", "")).strip()
    try:
        confidence = float(data.get("confidence", 0.0))
    except (TypeError, ValueError):
        confidence = 0.0

    confidence = max(0.0, min(1.0, confidence))

    # 모델이 제외해야 할 문자열을 반환하는 간단한 방어.
    if re.fullmatch(r"\d{1,2}\s*/\s*\d{1,2}", title):
        title = ""
        confidence = 0.0
    if title.upper() == "HAPPY CHURCH":
        title = ""
        confidence = 0.0

    return {
        "title": title,
        "confidence": confidence,
    }


def ask_vision(
    client: OpenAI,
    model: str,
    png_bytes: bytes,
    *,
    page_number: int,
    date: dt.date,
    max_retries: int = 3,
) -> dict[str, Any]:
    prompt = (
        PROMPT
        + f"\n참고 메타데이터: 이 카드는 {date.year}년 {date.month}월 {date.day}일,"
        + f" PDF {page_number}페이지입니다."
    )

    last_error: Exception | None = None

    for attempt in range(max_retries):
        try:
            response = client.responses.create(
                model=model,
                input=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "input_text",
                                "text": prompt,
                            },
                            {
                                "type": "input_image",
                                "image_url": image_data_url(png_bytes),
                                "detail": "high",
                            },
                        ],
                    }
                ],
            )
            parsed = parse_model_json(response.output_text)
            parsed["model"] = model
            return parsed
        except Exception as exc:  # API/네트워크/파싱 재시도
            last_error = exc
            if attempt + 1 < max_retries:
                time.sleep(2 ** attempt)

    raise RuntimeError(
        f"{model} 요청 실패: {last_error}"
    )


def load_existing(output_path: Path, year: int) -> dict[str, Any]:
    if not output_path.exists():
        return {
            "year": year,
            "start_page": START_PAGE,
            "page_count": DAY_COUNT,
            "generated_at": None,
            "titles": {},
        }

    data = json.loads(output_path.read_text(encoding="utf-8"))
    if int(data.get("year", year)) != year:
        raise SystemExit(
            f"기존 {output_path}의 year가 요청 연도 {year}와 다릅니다."
        )
    data.setdefault("titles", {})
    return data


def save_output(
    output_path: Path,
    data: dict[str, Any],
    lock: threading.Lock | None = None,
) -> None:
    if lock:
        with lock:
            _save_output_unlocked(output_path, data)
    else:
        _save_output_unlocked(output_path, data)


def _save_output_unlocked(
    output_path: Path,
    data: dict[str, Any],
) -> None:
    data["generated_at"] = dt.datetime.now().isoformat(timespec="seconds")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = output_path.with_suffix(".tmp")
    tmp.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    tmp.replace(output_path)


def main() -> None:
    load_dotenv()

    parser = argparse.ArgumentParser(
        description="TheWordCalendar 365일 묵상 제목 AI Vision 일괄 추출기"
    )
    parser.add_argument(
        "--pdf",
        default="365일 매일묵상말씀.pdf",
        help="PDF 파일 경로",
    )
    parser.add_argument(
        "--year",
        type=int,
        default=2026,
        help="카탈로그 기준 연도",
    )
    parser.add_argument(
        "--output",
        default="output/titles.json",
        help="결과 JSON",
    )
    parser.add_argument(
        "--model",
        default=os.getenv("OPENAI_TITLE_MODEL", "gpt-5.6-luna"),
        help="1차 Vision 모델",
    )
    parser.add_argument(
        "--fallback-model",
        default=os.getenv("OPENAI_FALLBACK_MODEL", "gpt-5.6-terra"),
        help="낮은 확신 결과 재확인 모델",
    )
    parser.add_argument(
        "--confidence-threshold",
        type=float,
        default=0.82,
        help="이 값 미만이면 fallback 모델로 재확인",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=3,
        help="동시 API 요청 수. 처음에는 2~3 권장",
    )
    parser.add_argument(
        "--only",
        help="특정 날짜만 테스트. 예: 09-13,09-23,10-27",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="기존 결과가 있어도 다시 추출",
    )
    args = parser.parse_args()

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise SystemExit(
            "OPENAI_API_KEY가 없습니다. .env.example을 .env로 복사한 뒤 키를 입력하세요."
        )

    pdf_path = Path(args.pdf).expanduser().resolve()
    if not pdf_path.exists():
        raise SystemExit(f"PDF를 찾을 수 없습니다: {pdf_path}")

    output_path = Path(args.output).expanduser().resolve()
    crop_dir = output_path.parent / "crops"

    client = OpenAI(api_key=api_key)
    data = load_existing(output_path, args.year)
    only = parse_only(args.only)

    jobs = jobs_for_year(args.year)
    if only is not None:
        jobs = [job for job in jobs if job.key in only]

    if not args.force:
        jobs = [
            job
            for job in jobs
            if not (
                job.key in data["titles"]
                and str(data["titles"][job.key].get("title", "")).strip()
            )
        ]

    if not jobs:
        print("추출할 항목이 없습니다. --force를 사용하면 다시 추출합니다.")
        return

    print(f"PDF: {pdf_path}")
    print(f"대상: {len(jobs)}개")
    print(f"1차 모델: {args.model}")
    print(f"재확인 모델: {args.fallback_model}")
    print(f"결과: {output_path}")
    print()

    # PDF 렌더링은 먼저 순차 실행해 crop을 안정적으로 확보.
    prepared: list[tuple[PageJob, bytes, Path]] = []
    for idx, job in enumerate(jobs, 1):
        crop_path = crop_dir / f"{job.key}_p{job.page_number}.png"
        png = render_crop(
            pdf_path,
            job.page_number,
            crop_path,
        )
        prepared.append((job, png, crop_path))
        print(
            f"[렌더링 {idx}/{len(jobs)}] "
            f"{job.key} / PDF {job.page_number}"
        )

    lock = threading.Lock()
    completed = 0

    def process(item: tuple[PageJob, bytes, Path]) -> tuple[PageJob, dict[str, Any]]:
        job, png, crop_path = item

        result = ask_vision(
            client,
            args.model,
            png,
            page_number=job.page_number,
            date=job.date,
        )

        # 제목이 비었거나 confidence가 낮으면 더 강한 모델로 다시 확인.
        if (
            not result["title"]
            or result["confidence"] < args.confidence_threshold
        ):
            fallback = ask_vision(
                client,
                args.fallback_model,
                png,
                page_number=job.page_number,
                date=job.date,
            )

            # fallback이 비지 않았다면 fallback 우선.
            if fallback["title"]:
                result = fallback
                result["fallback_used"] = True

        result.update(
            {
                "page": job.page_number,
                "date": job.date.isoformat(),
                "crop": str(crop_path.relative_to(output_path.parent)),
            }
        )
        return job, result

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max(1, args.workers)
    ) as executor:
        futures = {
            executor.submit(process, item): item[0]
            for item in prepared
        }

        for future in concurrent.futures.as_completed(futures):
            job = futures[future]
            try:
                _, result = future.result()
            except Exception as exc:
                result = {
                    "title": "",
                    "confidence": 0.0,
                    "model": "",
                    "page": job.page_number,
                    "date": job.date.isoformat(),
                    "error": str(exc),
                }

            with lock:
                data["titles"][job.key] = result
                completed += 1
                _save_output_unlocked(output_path, data)

            title = result.get("title") or "(실패)"
            confidence = float(result.get("confidence", 0.0))
            print(
                f"[AI {completed}/{len(jobs)}] "
                f"{job.key} → {title} "
                f"(confidence {confidence:.2f}, {result.get('model','')})"
            )

    print()
    print("완료.")
    print(f"결과 JSON: {output_path}")
    print(
        "다음: python build_review.py "
        f'--input "{output_path}"'
    )


if __name__ == "__main__":
    main()
