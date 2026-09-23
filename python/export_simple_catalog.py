from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="추출 결과를 Flutter/Firestore용 단순 MM-DD -> 제목 JSON으로 변환"
    )
    parser.add_argument("--input", default="output/titles_reviewed.json")
    parser.add_argument("--output", default="output/catalog_simple.json")
    args = parser.parse_args()

    src = Path(args.input).resolve()
    dst = Path(args.output).resolve()

    data = json.loads(src.read_text(encoding="utf-8"))
    out = {}

    for key, item in data.get("titles", {}).items():
        title = (
            str(item.get("title", "")).strip()
            if isinstance(item, dict)
            else str(item).strip()
        )
        if title:
            out[key] = title

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(
        json.dumps(out, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"생성: {dst} ({len(out)}개)")


if __name__ == "__main__":
    main()
