"""Run with: python -m pytest python/test_nas_api.py -q"""

import importlib
from io import BytesIO

from fastapi.testclient import TestClient
from pypdf import PdfWriter


def test_nas_api_end_to_end(tmp_path, monkeypatch):
    monkeypatch.setenv("DATEPDF_NAS_ROOT", str(tmp_path))
    monkeypatch.setenv("DATEPDF_NAS_TOKEN", "r" * 48)
    monkeypatch.setenv("DATEPDF_NAS_ADMIN_TOKEN", "a" * 48)
    import nas_api

    api = importlib.reload(nas_api)
    user = {"Authorization": "Bearer " + "r" * 48}
    admin = {"Authorization": "Bearer " + "a" * 48}
    with TestClient(api.app) as client:
        assert client.get("/api/catalog/current").status_code == 401
        assert client.get("/api/admin/check", headers=user).status_code == 403
        assert client.get("/api/admin/check", headers=admin).json() == {"ok": True}
        assert client.put("/api/settings/pdf", headers=user, json={}).status_code == 403

        settings = client.put(
            "/api/settings/pdf", headers=admin,
            json={"dailyStartPdfPage": 4, "dailyPageCount": 365,
                  "pdfPageCount": 368, "pdfFileName": "말씀.pdf"},
        )
        assert settings.status_code == 200
        assert client.get("/api/settings/pdf", headers=user).json()["pdfPageCount"] == 368

        assert client.post("/api/pdf/current", headers=admin,
                           files={"file": ("bad.pdf", b"not a pdf", "application/pdf")}).status_code == 400
        writer = PdfWriter()
        writer.add_blank_page(width=72, height=72)
        pdf = BytesIO()
        writer.write(pdf)
        uploaded = client.post("/api/pdf/current", headers=admin,
                               files={"file": ("test.pdf", pdf.getvalue(), "application/pdf")})
        assert uploaded.status_code == 200
        assert client.get("/api/pdf/current", headers=user).content.startswith(b"%PDF-")
        assert client.get("/api/pdf/current/metadata", headers=user).json()["fileName"] == "test.pdf"

        question = client.post("/api/qna", headers=user, json={
            "id": "q1", "title": "질문", "content": "내용", "authorDeviceId": "device",
            "isAnswered": True, "answer": "forged",
        })
        assert question.status_code == 200
        assert question.json()["isAnswered"] is False
        assert question.json()["notificationToken"] is None
        assert client.put("/api/qna/q1", headers=user, json={"answer": "답"}).status_code == 403
        answer = client.put("/api/qna/q1", headers=admin, json={
            "answer": "답변", "isAnswered": True, "answeredAt": "2026-10-05T00:00:00Z"
        })
        assert answer.status_code == 200
        assert client.post("/api/qna", headers=user, json={
            "id": "q1", "title": "질문", "content": "내용"
        }).json()["answer"] == "답변"
        assert client.put("/api/qna/q1", headers=admin,
                          json={"authorDeviceId": "hijack"}).status_code == 400

        event = {"page": 4, "count": 1, "eventId": "one"}
        assert client.post("/api/stats/direct-open", headers=user, json=event).json()["views"] == 1
        assert client.post("/api/stats/direct-open", headers=user, json=event).json()["views"] == 1
        assert client.get("/api/stats/top", headers=user).json()["items"][0]["views"] == 1
