from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


HTML_TEMPLATE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TheWordCalendar 제목 검수</title>
<style>
body {{ font-family: Arial, "Malgun Gothic", sans-serif; margin: 0; background:#f4f6f9; color:#20242a; }}
header {{ position:sticky; top:0; background:white; border-bottom:1px solid #ddd; padding:16px 22px; z-index:10; display:flex; gap:18px; align-items:center; }}
button {{ border:0; border-radius:10px; background:#376d9f; color:white; padding:11px 16px; font-weight:700; cursor:pointer; }}
main {{ max-width:1200px; margin:20px auto; padding:0 16px 60px; }}
.card {{ background:white; border-radius:16px; margin-bottom:14px; padding:14px; display:grid; grid-template-columns:100px minmax(260px, 1fr) minmax(260px, 1fr); gap:16px; align-items:center; }}
.meta {{ font-weight:700; }}
.meta small {{ display:block; color:#777; margin-top:5px; font-weight:400; }}
img {{ max-width:100%; max-height:190px; object-fit:contain; border:1px solid #eee; border-radius:10px; background:#fff; }}
input {{ width:100%; box-sizing:border-box; font-size:18px; padding:12px; border:1px solid #bbb; border-radius:10px; }}
.low {{ border:2px solid #d98400; }}
.fail {{ border:2px solid #c33; }}
@media(max-width:800px) {{
  .card {{ grid-template-columns:1fr; }}
}}
</style>
</head>
<body>
<header>
  <strong>TheWordCalendar 제목 검수</strong>
  <span>총 {count}개</span>
  <span>낮은 확신 {low_count}개</span>
  <button onclick="downloadJson()">수정 JSON 다운로드</button>
</header>
<main>
{cards}
</main>
<script>
const original = {json_blob};

function downloadJson() {{
  const result = JSON.parse(JSON.stringify(original));
  document.querySelectorAll('input[data-key]').forEach(input => {{
    const key = input.dataset.key;
    result.titles[key].title = input.value.trim();
    result.titles[key].reviewed = true;
  }});
  result.reviewed_at = new Date().toISOString();
  const blob = new Blob([JSON.stringify(result, null, 2)], {{type:'application/json'}});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'titles_reviewed.json';
  a.click();
  URL.revokeObjectURL(url);
}}
</script>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        default="output/titles.json",
    )
    parser.add_argument(
        "--output",
        default="output/review.html",
    )
    parser.add_argument(
        "--low-threshold",
        type=float,
        default=0.88,
    )
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()

    data = json.loads(input_path.read_text(encoding="utf-8"))
    titles = data.get("titles", {})

    cards = []
    low_count = 0

    for key in sorted(titles):
        item = titles[key]
        title = str(item.get("title", ""))
        confidence = float(item.get("confidence", 0.0) or 0.0)
        page = item.get("page", "")
        crop = item.get("crop", "")

        if confidence < args.low_threshold:
            low_count += 1

        css = ""
        if not title:
            css = " fail"
        elif confidence < args.low_threshold:
            css = " low"

        crop_path = input_path.parent / crop if crop else None
        if crop_path and crop_path.exists():
            try:
                relative = crop_path.relative_to(output_path.parent)
                img_src = relative.as_posix()
            except ValueError:
                img_src = crop_path.as_uri()
        else:
            img_src = ""

        cards.append(
            f"""
            <section class="card{css}">
              <div class="meta">
                {html.escape(key)}
                <small>PDF {html.escape(str(page))}<br>
                confidence {confidence:.2f}</small>
              </div>
              <div>
                {'<img src="' + html.escape(img_src) + '">' if img_src else '이미지 없음'}
              </div>
              <div>
                <input data-key="{html.escape(key)}"
                       value="{html.escape(title, quote=True)}"
                       placeholder="제목 직접 입력">
              </div>
            </section>
            """
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        HTML_TEMPLATE.format(
            count=len(titles),
            low_count=low_count,
            cards="\n".join(cards),
            json_blob=json.dumps(data, ensure_ascii=False),
        ),
        encoding="utf-8",
    )

    print(f"검수 HTML 생성: {output_path}")
    print("브라우저로 열어서 제목을 수정한 뒤 '수정 JSON 다운로드'를 누르세요.")


if __name__ == "__main__":
    main()
