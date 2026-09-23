# The Word DatePDF 📖

날짜를 기준으로 PDF의 해당 날짜 말씀을 자동으로 찾아 보여주는 모바일 앱입니다\.

일반 사용자는 별도의 회원가입이나 로그인을 하지 않고 앱을 사용할 수 있으며, 관리자는 **설정 → 관리자 모드 → 승인코드**를 통해 관리자 기능에 접근할 수 있도록 설계했습니다\.

현재는 Flutter \+ Firebase를 기반으로 개발하고 있으며, 향후 NAS를 자체 서버로 사용하는 구조로 확장할 수 있도록 서버 의존성을 분리하는 것을 목표로 합니다\.

---

## 📱 프로젝트 개요

이 프로젝트의 핵심 목적은 특정 날짜의 콘텐츠가 들어 있는 PDF를 사용자가 일일이 찾아보지 않아도 **오늘 날짜에 해당하는 PDF 페이지를 자동으로 찾아 바로 보여주는 것**입니다\.

예를 들어 현재 사용 중인 PDF가 다음과 같은 구조라면:

```text
2026년 1월 1일 → PDF 4페이지
2026년 1월 2일 → PDF 5페이지
2026년 1월 3일 → PDF 6페이지
...
2026년 9월 23일 → PDF 269페이지
...
2026년 12월 31일 → PDF 368페이지
```

앱에서 오늘 날짜를 확인한 후 해당 페이지를 자동으로 계산합니다\.

따라서 사용자는 PDF에서 날짜를 직접 검색하거나 페이지를 찾아 이동할 필요가 없습니다\.

---

# ✨ 주요 기능

## 1\. 홈 화면

홈 화면에서는 사용자가 앱을 실행했을 때 가장 필요한 정보를 한눈에 확인할 수 있도록 구성합니다\.

- 사용자 이름
- 오늘 날짜
- 오늘의 PDF
- 오늘 날짜에 해당하는 PDF 페이지
- 많이 방문한 페이지 TOP 3
- 최근 본 페이지
- 설정 진입

예시:

```text
┌──────────────────────────────┐
│ 👤 사용자님                 ⚙️ │
│ 2026년 9월 23일 (수)          │
│                              │
│ 오늘의 말씀                   │
│ ┌──────────────────────────┐ │
│ │ 📖 9월 23일               │ │
│ │                          │ │
│ │        [말씀 제목]      │ │
│ │                          │ │
│ │      [오늘 내용 보기]    │ │
│ └──────────────────────────┘ │
│                              │
│ 🔥 많이 방문한 페이지         │
│ 🥇 말씀 제목1 · 12회            │
│ 🥈 말씀 제목2 · 9회             │
│ 🥉 말씀 제목3 · 7회             │
│                              │
├──────────────────────────────┤
│ 일정       🏠 홈       QnA   │
└──────────────────────────────┘
```

---

## 2\. 하단 네비게이션

앱의 주요 기능은 하단 탭으로 이동합니다\.

### 📅 일정

날짜를 선택하여 해당 날짜의 PDF 페이지를 확인합니다\.

### 🏠 홈

오늘 날짜의 PDF와 인기 페이지를 확인합니다\.

### 💬 QnA

자주 묻는 질문과 사용자의 질문을 관리하는 공간입니다\.

---

# 📅 날짜 → PDF 페이지 자동 이동
앞부분의 3페이지를 제외하고 PDF 4페이지부터 365일의 일일 콘텐츠가 시작하는 형태라고 가정하면\.

현재 PDF 형식에서는 다음과 같은 규칙을 사용할 수 있습니다\.

```text
PDF 페이지 = 해당 연도의 날짜 순번 + 앞부분 제외 페이지
```

예:

```text
1월 1일
= 1번째 날
= 1 + 3
= PDF 4페이지
```

```text
2월 1일
= 32번째 날
= 32 + 3
= PDF 35페이지
```

```text
9월 23일
= 266번째 날
= 266 + 3
= PDF 269페이지
```

```text
12월 31일
= 365번째 날
= 365 + 3
= PDF 368페이지
```

이 기능은 `lib/services/date_page_mapper.dart`에서 담당합니다\.

```dart
DatePageMapper.pdfPageForDate(date);
```

### 주의사항

현재 매핑 방식은 **현재 PDF의 페이지 구조가 유지된다는 전제**에서 동작합니다\.

새 PDF를 업로드했을 때:

- 앞표지 페이지 수가 달라지는 경우
- 일일 콘텐츠 시작 페이지가 달라지는 경우
- 날짜 순서가 달라지는 경우
- 2월 29일이 별도 페이지로 추가되는 윤년용 PDF인 경우

페이지 매핑 방식을 별도로 설정해야 합니다\.

따라서 최종 관리자 화면에서는 **일일 콘텐츠 시작 페이지를 관리자가 설정할 수 있도록 만드는 것**을 권장합니다\.

---

# ⚙️ 설정

설정 화면에서는 일반적인 앱 설정과 관리자 기능을 함께 제공합니다\.

## 👤 사용자

- 사용자 이름 변경

현재는 회원가입/로그인 없이 이름을 기기에 저장하는 방식으로 설계합니다\.

즉:

```text
이름
 ↓
SharedPreferences
 ↓
"사용자님"
```

처럼 동작합니다\.

사용자 이름은 인증 목적이 아니라 앱에서 표시하기 위한 정보입니다\.

---

## 🔔 알림

향후 다음과 같은 알림 기능을 추가할 수 있습니다\.

- PDF 업데이트 알림
- QnA 답변 알림
- 일정 변경 알림

현재 프로젝트에서는 UI를 먼저 구성하고 실제 Push Notification 기능은 Firebase 연결 단계에서 추가할 수 있도록 설계합니다\.

---

# 🔐 관리자 모드

일반 사용자에게 관리자 기능을 노출하지 않으면서 별도의 일반 사용자 로그인 시스템을 만들지 않기 위해 다음 구조를 사용합니다\.

```text
설정
 ↓
관리자 모드
 ↓
승인코드 입력
 ↓
관리자 인증
 ↓
관리자 센터
```

관리자 인증이 성공해도 앱 전체의 UI가 별도의 앱처럼 바뀌지는 않습니다\.

기존의:

```text
일정 | 홈 | QnA
```

구조는 유지하고,

```text
설정
 ↓
관리자 모드
 ↓
관리자 센터
```

에서 관리 기능을 이용하는 방식입니다\.

---

# 🛠️ 관리자 센터

관리자 센터에서는 다음 기능을 제공하는 것을 목표로 합니다\.

## 📄 PDF 관리

- 현재 PDF 확인
- PDF 업로드
- PDF 교체
- PDF 버전 관리
- 마지막 업데이트 날짜 확인

관리자가 PDF를 교체하면 사용자는 앱을 다시 설치하지 않고 최신 PDF를 사용할 수 있도록 구성합니다\.

예상 구조:

```text
관리자
 ↓
새 PDF 선택
 ↓
Firebase Storage 업로드
 ↓
Firestore의 현재 PDF 정보 변경
 ↓
사용자 앱에서 최신 PDF 조회
```

---

## 📅 날짜 / 페이지 관리

현재 PDF 구조에서는 자동 계산이 가능하지만, PDF 형식이 변경될 가능성을 고려해 관리자 화면에서 매핑을 확인할 수 있도록 구성합니다\.

예:

```text
일일 콘텐츠 시작 페이지
[ 4 ]

1월 1일  → 4페이지
1월 2일  → 5페이지
1월 3일  → 6페이지
...
12월 31일 → 368페이지
```

필요한 경우 관리자가 특정 날짜의 페이지를 직접 수정할 수 있도록 확장할 수 있습니다\.

---

## 📊 방문 통계

사용자가 PDF 페이지를 열면 해당 페이지의 조회수를 기록합니다\.

예:

```text
page_stats

23페이지 → 13회
45페이지 → 9회
78페이지 → 7회
```

홈 화면에는:

```text
🥇 23페이지
🥈 45페이지
🥉 78페이지
```

형태로 TOP 3를 표시합니다\.

관리자 화면에서는 향후:

- 전체 페이지 조회수
- 날짜별 조회수
- 인기 페이지
- 최근 조회 페이지
- 사용자별 통계

등으로 확장할 수 있습니다\.

---

# 💬 QnA

QnA 화면은 사용자가 앱 사용 중 궁금한 내용을 확인하거나 질문할 수 있도록 구성합니다\.

기본 기능:

- 질문 검색
- 자주 묻는 질문
- 질문 작성
- 답변 확인

관리자 기능:

- 질문 확인
- 답변 작성
- FAQ 등록
- FAQ 수정
- FAQ 삭제

---

# 🏗️ 프로젝트 구조

현재 프로젝트는 기능별로 파일을 나누어 유지보수하기 쉽게 구성합니다\.

```text
date_pdf/
│
├── android/
├── ios/
│
├── lib/
│   │
│   ├── main.dart
│   │
│   ├── models/
│   │
│   ├── services/
│   │   ├── admin_service.dart
│   │   ├── date_page_mapper.dart
│   │   ├── local_profile_service.dart
│   │   └── pdf_repository.dart
│   │
│   └── screens/
│       ├── app_shell.dart
│       ├── home_page.dart
│       ├── schedule_page.dart
│       ├── qna_page.dart
│       ├── pdf_page.dart
│       ├── settings_page.dart
│       ├── admin_code_page.dart
│       └── admin_page.dart
│
├── pubspec.yaml
├── README.md
└── firebase_options.dart
```

---

# 🔥 Firebase 구성

현재 개발 단계에서는 Firebase를 백엔드로 사용합니다\.

## Firebase 서비스

### Firebase Firestore

앱의 구조화된 데이터를 저장합니다\.

예상 구조:

```text
pdf_documents/
└── current
    ├── pdfUrl
    ├── version
    └── updatedAt

pdf_pages/
├── 2026-01-01
├── 2026-01-02
├── 2026-01-03
└── ...

page_stats/
├── 1
├── 2
├── 3
└── ...

qna/
├── question-001
├── question-002
└── ...
```

---

## Firebase Storage

PDF 파일 자체는 Firebase Storage에 저장합니다\.

예:

```text
pdf/
└── current/
    └── document.pdf
```

관리자가 PDF를 교체하면 새로운 PDF를 Storage에 업로드하고 Firestore의 현재 PDF 정보를 변경합니다\.

---

# 🔒 Firebase 보안

실제 배포 전에는 반드시 Firebase Security Rules를 설정해야 합니다\.

특히 다음 기능은 일반 사용자에게 쓰기 권한을 주면 안 됩니다\.

```text
PDF 업로드
PDF 삭제
PDF 교체
관리자 설정
QnA 답변
관리자 데이터 수정
```

일반 사용자는 필요한 데이터만 읽을 수 있도록 하고 관리자 작업은 서버 측에서 검증하는 것을 목표로 합니다\.

---

# 🔑 관리자 승인코드 보안

현재 프로젝트의 관리자 승인코드는 **개발용 프로토타입**입니다\.

실제 서비스에서는 승인코드를 Flutter 코드에 하드코딩하면 안 됩니다\.

잘못된 예:

```dart
const adminCode = "123456";
```

Flutter 앱은 사용자의 기기에 설치되기 때문에 앱을 분석하면 코드가 노출될 가능성이 있습니다\.

## 권장 구조

```text
Flutter
   │
   │ 승인코드
   ▼
Firebase Cloud Function
   │
   │ 서버에서 승인코드 검증
   ▼
관리자 인증
   │
   ▼
관리자 기능 사용
```

향후 Firebase Authentication과 Custom Claims 또는 서버 측 세션/토큰을 이용하여 관리자 권한을 관리하는 방식으로 개선합니다\.

---

# 📦 현재 사용 패키지

주요 패키지:

```yaml
dependencies:
  flutter:
    sdk: flutter

  firebase_core:
  cloud_firestore:
  firebase_storage:
  firebase_auth:
  file_picker:
  shared_preferences:
  intl:
```

실제 PDF 렌더링 기능을 구현할 때는 PDF Viewer 패키지를 추가합니다\.

예:

- `pdfrx`
- `pdfx`
- `syncfusion_flutter_pdfviewer`

프로젝트의 라이선스 및 기능 요구사항을 확인한 후 하나를 선택합니다\.

---

# 🚀 개발 환경 설정

## 1\. Flutter 확인

```bash
flutter doctor
```

필요한 개발 환경이 정상적으로 설치되어 있는지 확인합니다\.

---

## 2\. 프로젝트 다운로드

```bash
git clone <YOUR_REPOSITORY_URL>
cd date_pdf
```

---

## 3\. 패키지 설치

```bash
flutter pub get
```

---

## 4\. Firebase 연결

Firebase CLI와 FlutterFire CLI를 설치한 후:

```bash
firebase login
```

```bash
dart pub global activate flutterfire_cli
```

그리고:

```bash
flutterfire configure
```

를 실행합니다\.

그러면 플랫폼별 Firebase 설정을 기반으로:

```text
lib/firebase_options.dart
```

파일이 생성됩니다\.

---

## 5\. 실행

Android:

```bash
flutter run
```

iOS:

```bash
flutter run
```

iOS 개발 및 배포에는 macOS와 Xcode가 필요합니다\.

---

# 🧪 테스트 계획

## 날짜 매핑 테스트

최소한 다음 날짜를 테스트합니다\.

```text
2026-01-01 → PDF 4
2026-02-01 → PDF 35
2026-04-03 → PDF 96
2026-09-23 → PDF 269
2026-12-31 → PDF 368
```

## 앱 기능 테스트

- [ ] 첫 실행
- [ ] 사용자 이름 설정
- [ ] 이름 변경
- [ ] 오늘 날짜 표시
- [ ] 오늘 PDF 페이지 계산
- [ ] 날짜 선택
- [ ] 해당 PDF 페이지 이동
- [ ] 이전/다음 페이지 이동
- [ ] PDF 열기
- [ ] 최근 본 페이지
- [ ] 인기 페이지 TOP 3
- [ ] QnA 검색
- [ ] QnA 작성
- [ ] 관리자 승인코드
- [ ] 관리자 모드 진입
- [ ] 관리자 모드 종료
- [ ] PDF 업로드
- [ ] PDF 교체
- [ ] 날짜/페이지 확인
- [ ] 방문 통계
- [ ] Firebase Security Rules

---

# 👥 배포 계획

이 앱은 초기에는 약 10명 정도의 제한된 사용자에게 배포하는 것을 목표로 합니다\.

## Android

Google Play Console의 \*\*비공개 테스트&#40;Closed Testing&#41;\*\*를 이용하는 방식을 권장합니다\.

빌드:

```bash
flutter build appbundle --release
```

생성된 Android App Bundle을 Google Play Console에 업로드하고 테스트 사용자만 초대합니다\.

---

## iPhone

iOS는 **TestFlight**를 이용하는 방식이 적합합니다\.

일반적인 흐름:

```text
Flutter
 ↓
Xcode
 ↓
Archive
 ↓
App Store Connect
 ↓
TestFlight
 ↓
테스트 사용자 초대
```

iOS 배포에는 Apple Developer 계정과 macOS/Xcode 환경이 필요합니다\.

---

# 🗺️ 개발 로드맵

## Phase 1 — UI 프로토타입

- [x] 홈 화면
- [x] 일정 화면
- [x] QnA 화면
- [x] 설정 화면
- [x] 관리자 모드 UI
- [x] 관리자 센터 UI
- [x] 날짜 → 페이지 계산 로직

---

## Phase 2 — Firebase 연결

- [ ] Firebase 프로젝트 생성
- [ ] Firestore 연결
- [ ] Firebase Storage 연결
- [ ] 실제 PDF 업로드
- [ ] PDF URL 관리
- [ ] 사용자 앱에서 PDF 조회

---

## Phase 3 — 실제 PDF Viewer

- [ ] PDF Viewer 패키지 선택
- [ ] Firebase Storage PDF 연결
- [ ] 페이지 이동
- [ ] 날짜별 자동 페이지 이동
- [ ] 이전/다음 날짜 이동
- [ ] 최근 본 페이지 저장

---

## Phase 4 — 관리자 기능

- [ ] 관리자 승인코드 서버 검증
- [ ] 관리자 인증 상태 관리
- [ ] PDF 업로드
- [ ] PDF 교체
- [ ] PDF 버전 관리
- [ ] 날짜/페이지 매핑 관리

---

## Phase 5 — 통계 / QnA

- [ ] 페이지 조회수 저장
- [ ] 인기 페이지 TOP 3
- [ ] 관리자 통계
- [ ] QnA 작성
- [ ] QnA 답변
- [ ] FAQ

---

## Phase 6 — 보안

- [ ] Firestore Security Rules
- [ ] Storage Security Rules
- [ ] 관리자 서버 인증
- [ ] 승인코드 서버 검증
- [ ] API/데이터 접근 권한 분리
- [ ] 관리자 세션 관리

---

## Phase 7 — 제한 배포

- [ ] Android 내부/비공개 테스트
- [ ] iOS TestFlight
- [ ] 약 10명 사용자 테스트
- [ ] 버그 수정
- [ ] 사용성 개선

---

# 🖥️ 향후 NAS 서버 전환

현재는 Firebase를 사용하지만 향후 NAS를 서버로 사용할 수 있도록 구조를 분리하는 것을 목표로 합니다\.

최종적으로 다음과 같은 구조로 전환할 수 있습니다\.

```text
현재

Flutter
   │
   ▼
Firebase
 ├── Firestore
 ├── Storage
 └── Authentication
```

향후:

```text
Flutter
   │
   │ HTTPS
   ▼
NAS
 ├── FastAPI
 ├── Database
 ├── PDF Storage
 └── Admin API
```

이때 Flutter UI가 Firebase에 직접 의존하지 않도록 Repository/API 계층을 두는 것이 중요합니다\.

예:

```dart
pdfRepository.getCurrentPdf();
```

처럼 화면에서는 데이터의 출처를 알 필요가 없도록 만들고,

현재:

```text
Repository
    ↓
Firebase
```

에서 향후:

```text
Repository
    ↓
NAS API
```

로 교체할 수 있도록 설계합니다\.

---

# 🏠 NAS 전환 예상 구조

NAS에서는 Docker를 이용해 다음과 같은 구조를 구성할 수 있습니다\.

```text
NAS
│
├── Reverse Proxy
│
├── FastAPI
│   ├── PDF API
│   ├── Admin API
│   ├── QnA API
│   └── Statistics API
│
├── Database
│
└── PDF Storage
```

외부 인터넷에서 NAS를 사용할 경우에는 단순한 포트포워딩보다 HTTPS, 방화벽, 인증, Reverse Proxy 등의 보안 구성을 함께 고려해야 합니다\.

---

# 🔐 보안 원칙

이 프로젝트에서는 다음 원칙을 적용합니다\.

### 일반 사용자

- 별도 회원가입 없음
- 일반 데이터 읽기
- PDF 보기
- QnA 사용

### 관리자

- 승인코드 인증
- PDF 업로드/교체
- 날짜/페이지 관리
- 통계 확인
- QnA 관리

### 서버

- 관리자 권한 검증
- PDF 쓰기 권한 제한
- 데이터베이스 쓰기 권한 제한
- Firebase Security Rules 적용

특히 **관리자 승인코드와 Firebase 관리자 권한을 Flutter 앱에 직접 저장하지 않는 것**을 원칙으로 합니다\.

---

# 📌 현재 프로젝트의 한계

현재 버전은 아직 완성된 서비스가 아니라 **개발용 UI/기능 프로토타입**입니다\.

아직 실제 연결이 필요한 부분:

- 실제 PDF Viewer
- Firebase Storage
- Firestore
- 실제 방문 통계
- 실제 QnA
- 서버 측 관리자 인증
- Firebase Security Rules
- 실제 Push Notification

따라서 현재 코드에 포함된 관리자 승인코드나 샘플 통계 데이터는 실제 서비스용 보안/데이터가 아닙니다\.

---

# 📄 PDF 형식 관련 참고

현재 개발 기준 PDF는 365일 일일 콘텐츠가 들어 있는 문서이며, 총 368페이지입니다\.

현재 확인된 주요 매핑:

|날짜     |PDF 페이지|
|-------|------:|
|1월 1일  |4      |
|2월 1일  |35     |
|4월 3일  |96     |
|9월 23일 |269    |
|12월 31일|368    |

따라서 현재 버전에서는 OCR을 이용하여 매일 날짜를 검색하는 것보다 **날짜 순번을 계산하여 페이지를 결정하는 방식이 더 단순하고 안정적**입니다\.

단, PDF의 형식이 변경될 경우 날짜/페이지 매핑 로직을 다시 검증해야 합니다\.

---

# 👨‍💻 개발 목적

이 프로젝트는 다음 기술을 실제로 적용하고 학습하는 것을 목표로 합니다\.

- Flutter
- Dart
- Firebase
- Firestore
- Firebase Storage
- 모바일 앱 UI/UX
- PDF 처리
- REST API 구조
- 서버 인증
- 관리자 권한 관리
- 데이터 통계
- Docker
- NAS 서버
- 모바일 앱 배포
- Android / iOS 테스트 배포

---

# 📜 License

프로젝트의 실제 배포 및 PDF 콘텐츠에 대한 저작권/사용 권한을 확인한 후 라이선스를 결정합니다\.

PDF 원본 콘텐츠는 프로젝트 소스 코드와 별도로 관리하는 것을 권장합니다\.

---

# 📞 Project Status

현재 상태:

```text
🟡 Prototype / Development
```

목표:

```text
Flutter App
    ↓
Firebase
    ↓
10명 내외 제한 테스트
    ↓
사용성/안정성 검증
    ↓
필요 시 NAS 서버 전환
```
