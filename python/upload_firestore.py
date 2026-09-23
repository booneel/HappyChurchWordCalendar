from __future__ import annotations

import argparse
import json
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


def main() -> None:
    parser = argparse.ArgumentParser(
        description="DatePDF 제목 JSON을 Firestore pdf_catalog/current에 업로드"
    )
    parser.add_argument(
        "--input",
        default="output/titles_reviewed.json",
        help="검수 완료 JSON",
    )
    parser.add_argument(
        "--service-account",
        required=True,
        help="Firebase 서비스 계정 JSON 경로",
    )
    parser.add_argument(
        "--project-id",
        default="date-pdf",
    )
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    service_account = Path(args.service_account).resolve()

    if not input_path.exists():
        raise SystemExit(f"입력 JSON 없음: {input_path}")
    if not service_account.exists():
        raise SystemExit(f"서비스 계정 JSON 없음: {service_account}")

    raw = json.loads(input_path.read_text(encoding="utf-8"))
    year = int(raw["year"])

    source_titles = raw.get("titles", {})
    titles: dict[str, str] = {}
    missing: list[str] = []

    for key, item in source_titles.items():
        if isinstance(item, dict):
            title = str(item.get("title", "")).strip()
        else:
            title = str(item).strip()

        if title:
            titles[key] = title
        else:
            missing.append(key)

    if missing:
        print(f"경고: 제목이 빈 날짜 {len(missing)}개")
        print(", ".join(missing[:30]))
        answer = input("그래도 업로드할까요? (y/N): ").strip().lower()
        if answer != "y":
            raise SystemExit("취소했습니다.")

    cred = credentials.Certificate(str(service_account))

    if not firebase_admin._apps:
        firebase_admin.initialize_app(
            cred,
            {"projectId": args.project_id},
        )

    db = firestore.client()

    document = {
        "year": year,
        "startPage": int(raw.get("start_page", 4)),
        "pageCount": int(raw.get("page_count", 365)),
        "titles": titles,
        "source": "ai-vision-reviewed-v6",
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }

    db.collection("pdf_catalog").document("current").set(
        document,
        merge=True,
    )

    print()
    print("Firestore 업로드 완료")
    print(f"project: {args.project_id}")
    print("document: pdf_catalog/current")
    print(f"titles: {len(titles)}개")


if __name__ == "__main__":
    main()
