"""Small self-hosted DatePDF API for a NAS or a home server.

The Flutter app talks to this service when DATEPDF_BACKEND=nas. It keeps the
same JSON field names as the Firebase implementation. Metadata remains in
small JSON files, while counters and QnA use SQLite so concurrent requests do
not overwrite one another.
"""

from __future__ import annotations

import json
import os
import secrets
import shutil
import sqlite3
import tempfile
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


ROOT = Path(os.getenv("DATEPDF_NAS_ROOT", "./nas-data")).resolve()
DATA = ROOT / "data"
BACKUPS = ROOT / "backups"
TOKEN = os.getenv("DATEPDF_NAS_TOKEN", "").strip()
PDF = DATA / "current.pdf"
CATALOG = DATA / "catalog.json"
SETTINGS = DATA / "settings.json"
QNA = DATA / "qna.json"
STATS = DATA / "stats.json"
DATABASE = DATA / "datepdf.sqlite3"
PDF_META = DATA / "pdf_metadata.json"
WRITE_LOCK = threading.RLock()

app = FastAPI(title="DatePDF NAS API", version="1.0.0")


class CatalogPayload(BaseModel):
    year: int = 2026
    startPage: int = 4
    pageCount: int = 365
    titleAlgorithmVersion: int = 3
    titles: dict[str, str] = Field(default_factory=dict)
    confidences: dict[str, float] = Field(default_factory=dict)
    lowConfidenceKeys: list[str] = Field(default_factory=list)
    updatedAt: str | None = None


class SettingsPayload(BaseModel):
    dailyStartPdfPage: int = 4
    dailyPageCount: int = 365
    pdfFileName: str = "365일 매일묵상말씀.pdf"
    updatedAt: str | None = None


class ViewPayload(BaseModel):
    page: int = Field(ge=1)
    count: int = Field(default=1, ge=1, le=10000)
    eventId: str | None = None
    openedAt: str | None = None


class QuestionPayload(BaseModel):
    id: str | None = None
    title: str = ""
    content: str = ""
    authorName: str = "사용자"
    createdAt: str | None = None
    answer: str | None = None
    answeredAt: str | None = None
    isAnswered: bool = False
    isReadByAdmin: bool = False


def ensure_store() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    BACKUPS.mkdir(parents=True, exist_ok=True)
    if not CATALOG.exists():
        atomic_json(CATALOG, CatalogPayload().model_dump())
    if not SETTINGS.exists():
        atomic_json(SETTINGS, SettingsPayload().model_dump())
    if not QNA.exists():
        atomic_json(QNA, [])
    if not STATS.exists():
        atomic_json(STATS, {})
    initialize_database()


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


@contextmanager
def database():
    connection = sqlite3.connect(DATABASE, timeout=30.0)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA busy_timeout = 30000")
    try:
        yield connection
    finally:
        connection.close()


def initialize_database() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    with database() as connection:
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = NORMAL")
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS page_stats (
                page INTEGER PRIMARY KEY,
                views INTEGER NOT NULL DEFAULT 0,
                last_opened_at TEXT
            );
            CREATE TABLE IF NOT EXISTS view_events (
                event_id TEXT PRIMARY KEY,
                page INTEGER NOT NULL,
                count INTEGER NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS qna (
                id TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """
        )

        stats_count = connection.execute(
            "SELECT COUNT(*) AS count FROM page_stats"
        ).fetchone()["count"]
        if stats_count == 0:
            legacy_stats = read_json(STATS, {})
            if isinstance(legacy_stats, dict):
                connection.executemany(
                    "INSERT OR IGNORE INTO page_stats(page, views) VALUES (?, ?)",
                    [
                        (int(page), int(views))
                        for page, views in legacy_stats.items()
                        if str(page).isdigit()
                    ],
                )

        qna_count = connection.execute(
            "SELECT COUNT(*) AS count FROM qna"
        ).fetchone()["count"]
        if qna_count == 0:
            legacy_qna = read_json(QNA, [])
            if isinstance(legacy_qna, list):
                rows = []
                for item in legacy_qna:
                    if not isinstance(item, dict) or not item.get("id"):
                        continue
                    rows.append(
                        (
                            str(item["id"]),
                            json.dumps(item, ensure_ascii=False),
                            str(item.get("createdAt") or ""),
                        )
                    )
                connection.executemany(
                    "INSERT OR IGNORE INTO qna(id, payload, created_at) VALUES (?, ?, ?)",
                    rows,
                )
        connection.commit()


def atomic_json(path: Path, value: Any, backup: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    BACKUPS.mkdir(parents=True, exist_ok=True)
    with WRITE_LOCK:
        if backup and path.exists():
            backup_path = BACKUPS / f"{path.stem}-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
            shutil.copy2(path, backup_path)
        fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(value, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_name, path)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)


def require_auth(authorization: str | None = Header(default=None)) -> None:
    if not TOKEN:
        return
    expected = f"Bearer {TOKEN}"
    if not authorization or not secrets.compare_digest(authorization, expected):
        raise HTTPException(status_code=401, detail="Bearer token required")


def backup_pdf() -> None:
    if PDF.exists():
        backup = BACKUPS / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}-current.pdf"
        shutil.copy2(PDF, backup)


@app.on_event("startup")
def startup() -> None:
    ensure_store()


@app.get("/api/pdf/current", dependencies=[Depends(require_auth)])
def download_pdf() -> FileResponse:
    if not PDF.exists():
        raise HTTPException(status_code=404, detail="current.pdf not found")
    metadata = read_json(PDF_META, {})
    return FileResponse(
        PDF,
        media_type="application/pdf",
        filename=metadata.get("fileName") or PDF.name,
    )


@app.get("/api/pdf/current/metadata", dependencies=[Depends(require_auth)])
def pdf_metadata() -> dict[str, Any]:
    if not PDF.exists():
        raise HTTPException(status_code=404, detail="current.pdf not found")
    stat = PDF.stat()
    metadata = read_json(PDF_META, {})
    return {
        "fileName": metadata.get("fileName") or PDF.name,
        "fileSize": stat.st_size,
        "updatedAt": metadata.get("updatedAt")
        or datetime.fromtimestamp(stat.st_mtime, timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
    }


@app.post("/api/pdf/current", dependencies=[Depends(require_auth)])
async def upload_pdf(file: UploadFile = File(...)) -> dict[str, Any]:
    DATA.mkdir(parents=True, exist_ok=True)
    temporary = DATA / f".upload-{secrets.token_hex(8)}.pdf"
    try:
        with temporary.open("wb") as target:
            while chunk := await file.read(1024 * 1024):
                target.write(chunk)
            target.flush()
            os.fsync(target.fileno())
        if temporary.stat().st_size == 0:
            raise HTTPException(status_code=400, detail="PDF is empty")
        with WRITE_LOCK:
            backup_pdf()
            os.replace(temporary, PDF)
            atomic_json(
                PDF_META,
                {
                    "fileName": Path(file.filename or "current.pdf").name,
                    "updatedAt": utc_now(),
                },
            )
        return pdf_metadata()
    finally:
        temporary.unlink(missing_ok=True)


@app.get("/api/catalog/current", dependencies=[Depends(require_auth)])
def get_catalog() -> dict[str, Any]:
    return read_json(CATALOG, CatalogPayload().model_dump())


@app.put("/api/catalog/current", dependencies=[Depends(require_auth)])
def put_catalog(payload: CatalogPayload) -> dict[str, Any]:
    data = payload.model_dump()
    data["updatedAt"] = payload.updatedAt or utc_now()
    atomic_json(CATALOG, data, backup=True)
    return data


@app.post("/api/stats/direct-open", dependencies=[Depends(require_auth)])
def record_view(payload: ViewPayload) -> dict[str, Any]:
    opened_at = payload.openedAt or utc_now()
    event_id = payload.eventId or secrets.token_urlsafe(18)
    with database() as connection:
        with connection:
            inserted = connection.execute(
                """
                INSERT OR IGNORE INTO view_events(event_id, page, count, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (event_id, payload.page, payload.count, opened_at),
            ).rowcount
            if inserted:
                connection.execute(
                    """
                    INSERT INTO page_stats(page, views, last_opened_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(page) DO UPDATE SET
                        views = page_stats.views + excluded.views,
                        last_opened_at = excluded.last_opened_at
                    """,
                    (payload.page, payload.count, opened_at),
                )
        row = connection.execute(
            "SELECT views FROM page_stats WHERE page = ?",
            (payload.page,),
        ).fetchone()
        return {"page": payload.page, "views": int(row["views"])}


@app.get("/api/stats/top", dependencies=[Depends(require_auth)])
def top_views(limit: int = 10) -> dict[str, Any]:
    limit = max(1, min(limit, 100))
    with database() as connection:
        rows = connection.execute(
            """
            SELECT page, views
            FROM page_stats
            WHERE views > 0
            ORDER BY views DESC, page ASC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
    items = [{"page": int(row["page"]), "views": int(row["views"])} for row in rows]
    return {"items": items[:limit]}


@app.get("/api/settings/pdf", dependencies=[Depends(require_auth)])
def get_settings() -> dict[str, Any]:
    return read_json(SETTINGS, SettingsPayload().model_dump())


@app.put("/api/settings/pdf", dependencies=[Depends(require_auth)])
def put_settings(payload: SettingsPayload) -> dict[str, Any]:
    data = payload.model_dump()
    data["updatedAt"] = payload.updatedAt or utc_now()
    atomic_json(SETTINGS, data, backup=True)
    return data


@app.get("/api/qna", dependencies=[Depends(require_auth)])
def get_qna() -> dict[str, Any]:
    with database() as connection:
        rows = connection.execute(
            "SELECT payload FROM qna ORDER BY created_at DESC LIMIT 50"
        ).fetchall()
    items = []
    for row in rows:
        try:
            item = json.loads(row["payload"])
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict):
            items.append(item)
    return {"items": items}


@app.post("/api/qna", dependencies=[Depends(require_auth)])
def create_qna(payload: QuestionPayload) -> dict[str, Any]:
    item = payload.model_dump()
    item["id"] = item["id"] or secrets.token_urlsafe(12)
    item["createdAt"] = item["createdAt"] or utc_now()
    with database() as connection:
        with connection:
            connection.execute(
                """
                INSERT INTO qna(id, payload, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload = excluded.payload,
                    created_at = excluded.created_at
                """,
                (
                    item["id"],
                    json.dumps(item, ensure_ascii=False),
                    str(item["createdAt"]),
                ),
            )
    return item


@app.put("/api/qna/{question_id}", dependencies=[Depends(require_auth)])
def update_qna(question_id: str, updates: dict[str, Any]) -> dict[str, Any]:
    with database() as connection:
        with connection:
            row = connection.execute(
                "SELECT payload FROM qna WHERE id = ?",
                (question_id,),
            ).fetchone()
            if row is not None:
                item = json.loads(row["payload"])
                item.update(updates)
                connection.execute(
                    """
                    UPDATE qna
                    SET payload = ?, created_at = ?
                    WHERE id = ?
                    """,
                    (
                        json.dumps(item, ensure_ascii=False),
                        str(item.get("createdAt") or ""),
                        question_id,
                    ),
                )
                return item
    raise HTTPException(status_code=404, detail="question not found")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "nas_api:app",
        host=os.getenv("DATEPDF_NAS_HOST", "0.0.0.0"),
        port=int(os.getenv("DATEPDF_NAS_PORT", "8787")),
        reload=False,
    )
