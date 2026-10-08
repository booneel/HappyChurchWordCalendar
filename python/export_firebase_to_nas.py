"""Export Firebase data before the first NAS API start.

Example: python export_firebase_to_nas.py --service-account service-account.json \
  --bucket thewordcalendar-f768c.firebasestorage.app --output ./firebase-export

Keep the service account and export directory private. Stop app writes while
exporting, then copy the output files into /volume1/wordcalendar-data/data/.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore, storage


def normalize(value):
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item) for item in value]
    return value


def write_json(path, value):
    path.write_text(json.dumps(normalize(value), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--service-account", required=True, type=Path)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--pdf-name", default="365일 매일묵상말씀.pdf")
    args = parser.parse_args()
    data = args.output / "data"
    if args.output.exists() and any(args.output.iterdir()):
        parser.error("Output directory must be empty to avoid overwriting a previous export")
    data.mkdir(parents=True, exist_ok=True)

    firebase_admin.initialize_app(credentials.Certificate(str(args.service_account)),
                                  {"storageBucket": args.bucket})
    db = firestore.client()
    bucket = storage.bucket()
    blob = bucket.blob(args.pdf_name)
    if not blob.exists():
        raise SystemExit(f"Storage PDF missing: {args.pdf_name}")
    blob.download_to_filename(str(data / "current.pdf"))
    write_json(data / "pdf_metadata.json", {"fileName": args.pdf_name})

    catalog = db.collection("pdf_catalog").document("current").get()
    settings = db.collection("pdf_settings").document("config").get()
    current_pdf = db.collection("pdf_documents").document("current").get()
    write_json(data / "catalog.json", catalog.to_dict() if catalog.exists else {})
    config = settings.to_dict() if settings.exists else {}
    pdf_doc = current_pdf.to_dict() if current_pdf.exists else {}
    config["pdfPageCount"] = pdf_doc.get("pdfPageCount", config.get("pdfPageCount", 368))
    write_json(data / "settings.json", config)

    questions = []
    for doc in db.collection("qna").stream():
        questions.append({"id": doc.id, **(doc.to_dict() or {})})
    write_json(data / "qna.json", questions)
    stats = {}
    for doc in db.collection("page_stats").stream():
        item = doc.to_dict() or {}
        page = item.get("page", doc.id)
        if str(page).isdigit():
            stats[str(page)] = int(item.get("views", 0))
    write_json(data / "stats.json", stats)
    print(f"Exported PDF, catalog, settings, {len(questions)} QnA and {len(stats)} page counts to {data}")


if __name__ == "__main__":
    main()
