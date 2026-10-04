"""Create temporary sample data for the local emulator smoke run only."""

from io import BytesIO

import httpx
from pypdf import PdfWriter

base = "http://127.0.0.1:8787"
admin = {"Authorization": "Bearer local-admin-token-bbbbbbbbbbbbbbbbbbbbbb"}
user = {"Authorization": "Bearer local-user-token-aaaaaaaaaaaaaaaaaaaaaa"}
writer = PdfWriter()
for _ in range(368):
    writer.add_blank_page(width=300, height=500)
buffer = BytesIO()
writer.write(buffer)
response = httpx.post(f"{base}/api/pdf/current", headers=admin,
                      files={"file": ("smoke.pdf", buffer.getvalue(), "application/pdf")})
response.raise_for_status()
print("PDF:", response.json())
response = httpx.put(f"{base}/api/catalog/current", headers=admin, json={
    "year": 2026, "startPage": 4, "pageCount": 365,
    "titles": {"10-05": "화면 연결 확인"},
})
response.raise_for_status()
response = httpx.post(f"{base}/api/qna", headers=user, json={
    "id": "smoke-question", "title": "Q&A 확인", "content": "화면 표시 확인",
    "authorName": "테스트",
})
response.raise_for_status()
print("Q&A:", response.json()["id"])
