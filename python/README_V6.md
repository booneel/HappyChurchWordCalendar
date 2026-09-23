# DatePDF v6 — AI Vision 제목 카탈로그 생성기

## 왜 이 방식인가

현재 PDF 제목은 다음처럼 디자인되어 있습니다.

```text
움직임 + 을 가질 때
하나님의 + 뜻 + 을 행하는 자
```

즉 제목 하나 안에서도:

- 손글씨
- 일반 글씨
- 색상 변화
- 글자 크기 변화
- 서로 다른 기준선

이 섞여 있습니다.

전통 OCR은 이걸 각각 다른 글자 덩어리로 보고:

```text
가질
행하는
```

같은 일부 단어만 제목으로 잘못 선택할 수 있습니다.

v6에서는 Flutter 사용자의 휴대폰에서 제목을 찾지 않습니다.

```text
관리자 PC에서 1회
PDF 365페이지
→ 제목 영역 이미지 렌더링
→ AI Vision이 화면 의미를 보고 전체 제목 해석
→ JSON
→ 관리자 검수
→ Firestore pdf_catalog/current
```

일반 사용자 앱:

```text
앱 시작
→ Firestore 카탈로그 1회 다운로드
→ 로컬/메모리 캐시
→ titles["09-13"]
→ "움직임을 가질 때"
```

따라서 사용자 화면은 빠릅니다.

---

# 1. 폴더 준비

이 도구 폴더에 실제 PDF를 복사합니다.

파일명:

```text
365일 매일묵상말씀.pdf
```

---

# 2. 최초 설치

Windows에서:

```text
01_setup.bat
```

실행합니다.

완료 후:

```text
.env
```

파일이 생성됩니다.

메모장으로 열어:

```env
OPENAI_API_KEY=실제_API_KEY
OPENAI_TITLE_MODEL=gpt-5.6-luna
OPENAI_FALLBACK_MODEL=gpt-5.6-terra
```

를 설정합니다.

`.env`와 Firebase 서비스 계정 JSON은 Git에 올리지 마세요.

---

# 3. 먼저 문제 페이지 3개만 테스트

```text
02_test_3_titles.bat
```

기본 테스트:

```text
09-13
09-23
10-27
```

입니다.

의도한 예:

```text
09-13 → 움직임을 가질 때
09-23 → 충성
10-27 → 하나님의 뜻을 행하는 자
```

결과:

```text
output/titles.json
output/crops/*.png
```

---

# 4. 365개 전체 생성

테스트가 괜찮으면:

```text
03_extract_all.bat
```

실행합니다.

기본은 이미 성공한 날짜를 다시 호출하지 않는 `resume` 방식입니다.

중간에 프로그램을 꺼도:

```text
output/titles.json
```

에 성공 결과가 계속 저장됩니다.

다시 실행하면 비어 있는 날짜부터 이어갑니다.

전부 다시 생성하고 싶다면:

```powershell
.venv\Scripts\python.exe extract_titles_ai.py `
  --pdf "365일 매일묵상말씀.pdf" `
  --year 2026 `
  --force
```

---

# 5. 낮은 확신 결과 자동 재확인

기본 모델:

```text
gpt-5.6-luna
```

결과 confidence가 기본 `0.82`보다 낮거나 제목이 비어 있으면:

```text
gpt-5.6-terra
```

로 해당 페이지만 다시 읽습니다.

직접 조정 가능:

```powershell
.venv\Scripts\python.exe extract_titles_ai.py `
  --pdf "365일 매일묵상말씀.pdf" `
  --year 2026 `
  --confidence-threshold 0.90
```

---

# 6. 관리자 검수 화면

전체 추출 후:

```text
04_build_review.bat
```

실행합니다.

브라우저에:

```text
output/review.html
```

이 열립니다.

각 날짜마다:

- 날짜
- PDF 페이지
- 실제 제목 crop 이미지
- AI가 읽은 제목
- confidence

가 같이 표시됩니다.

틀린 제목만 직접 고칩니다.

예:

```text
AI: 움직임을 가질때
수정: 움직임을 가질 때
```

완료 후 상단:

```text
수정 JSON 다운로드
```

버튼을 누릅니다.

브라우저 다운로드 폴더에:

```text
titles_reviewed.json
```

이 생성됩니다.

이 파일을 도구의:

```text
output/titles_reviewed.json
```

위치로 복사합니다.

---

# 7. Firestore 업로드

Firebase Console에서 서비스 계정을 발급해야 합니다.

Firebase 프로젝트:

```text
date-pdf
```

Firebase Console:

```text
프로젝트 설정
→ 서비스 계정
→ 새 비공개 키 생성
```

다운로드한 JSON은 예를 들어:

```text
firebase-service-account.json
```

으로 이 도구 폴더에 둡니다.

중요:

```text
절대 GitHub에 커밋하지 마세요.
```

업로드:

```powershell
.venv\Scripts\python.exe upload_firestore.py `
  --input "output\titles_reviewed.json" `
  --service-account "firebase-service-account.json" `
  --project-id "date-pdf"
```

Firestore 결과:

```text
pdf_catalog
└── current
    ├── year: 2026
    ├── startPage: 4
    ├── pageCount: 365
    ├── source: ai-vision-reviewed-v6
    └── titles
        ├── 09-13: 움직임을 가질 때
        ├── 09-23: 충성
        └── 10-27: 하나님의 뜻을 행하는 자
```

Flutter v4/v5의 `PdfCatalogService`는 이 구조를 그대로 읽을 수 있습니다.

---

# 8. Firestore 데이터베이스

이전 오류:

```text
The database (default) does not exist for project date-pdf
```

가 있었다면 Firebase Console에서 먼저:

```text
Build
→ Firestore Database
→ Create database
```

로 `(default)` Firestore를 생성해야 합니다.

---

# 9. Flutter에서 ML Kit 제거 가능

이 AI 카탈로그 방식을 사용하면 일반 사용자 앱에서는:

```text
google_mlkit_text_recognition
```

이 필요하지 않습니다.

단, 기존 `pdf_catalog_builder_service.dart` 등 관리자 OCR 코드를 Flutter 앱 안에 계속 남겨둘 경우에는 패키지가 필요합니다.

권장 최종 구조:

```text
PC 관리자 도구
→ AI Vision 제목 생성

Flutter
→ Firestore 제목 읽기만
```

즉 Flutter에서 OCR 코드 자체를 삭제하는 것이 가장 깔끔합니다.

---

# 10. 조회수 정책

v5에서 정한 정책을 그대로 유지합니다.

조회수 증가:

```text
사용자가 직접 말씀 카드를 눌러 PDF에 들어감
```

조회수 증가 안 함:

```text
PDF 내부 스크롤
onPageChanged
다음/이전 페이지 이동
스크롤하다 페이지가 화면에 보임
```

Firestore:

```text
page_stats/{page}
  page: 269
  views: 12
  countType: direct_open_only
```

---

# 11. 모델 변경

현재 OpenAI의 최신 모델 계열은 이미지 입력을 지원합니다.

기본 비용 절감:

```text
gpt-5.6-luna
```

더 어려운 제목을 처음부터 강한 모델로:

```powershell
.venv\Scripts\python.exe extract_titles_ai.py `
  --pdf "365일 매일묵상말씀.pdf" `
  --year 2026 `
  --model gpt-5.6-terra `
  --force
```

---

# 12. 특정 날짜만 다시 생성

예:

```powershell
.venv\Scripts\python.exe extract_titles_ai.py `
  --pdf "365일 매일묵상말씀.pdf" `
  --year 2026 `
  --only 09-13,10-27 `
  --force
```

전체 365개를 다시 돌릴 필요가 없습니다.

---

# 최종 권장 운영

PDF를 새 버전으로 교체했을 때만:

```text
1. PDF를 PC 도구 폴더에 복사
2. AI Vision으로 365개 제목 생성
3. review.html에서 낮은 확신/오류만 수정
4. Firestore 업로드
5. 사용자 앱은 새 카탈로그를 자동으로 읽음
```

이렇게 운영하면 사용자 휴대폰에서 제목 OCR을 할 이유가 없어집니다.
