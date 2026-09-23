# The Word DatePDF 📖

> **최종 기준 문서 — v7.1**
>
> 이 문서는 현재 프로젝트를 새 PC에서 다시 세팅하고, Firebase를 연결하고,
> Android에서 실행하고, GitHub에 백업/업로드하는 데 필요한 내용을 한 곳에 정리한 문서입니다.
>
> 과거 README나 OCR/제목 자동추출 관련 문서와 내용이 충돌하면 **이 문서를 우선**합니다.

---

# 1. 프로젝트 개요

The Word DatePDF는 날짜를 기준으로 365일 묵상 PDF의 해당 페이지를 자동으로 열어주는 Flutter 앱입니다.

사용자는 PDF 페이지 번호를 직접 찾지 않아도 됩니다.

예:

```text
2026년 1월 1일   → PDF 4페이지
2026년 1월 2일   → PDF 5페이지
...
2026년 9월 23일  → PDF 269페이지
...
2026년 12월 31일 → PDF 368페이지
```

앱에서는 날짜를 선택하면 자동으로 해당 페이지를 계산한 뒤 PDF를 엽니다.

---

# 2. 최종 방향

초기에는 PDF 안의 묵상 제목을 자동 OCR로 읽으려고 했지만,
손글씨/캘리그라피/혼합 폰트 때문에 인식률과 속도가 안정적이지 않았습니다.

따라서 **최종 버전에서는 제목 자동 추출을 사용하지 않습니다.**

사용자 화면에서는 다음과 같이 단순하게 표시합니다.

```text
오늘의 말씀
2026년 9월 23일 (수)

오늘의 말씀을 확인해보세요.

[오늘 말씀 보기]
```

찾아보기:

```text
오늘의 말씀
2026년 9월 23일 (수)

[보기]
```

많이 본 말씀:

```text
🥇
말씀
9월 23일
12회
```

최근 본 말씀:

```text
오늘의 말씀
2026년 9월 23일 (수)
```

즉 페이지 번호와 OCR 제목을 사용자에게 강조하지 않고
**날짜 중심의 말씀 앱**으로 운영합니다.

---

# 3. 현재 주요 기능

현재 프로젝트 기준 기능입니다.

- Flutter Android 앱
- Firebase 초기화
- Firebase Storage PDF 연결
- Firebase Firestore 연결
- Firebase Storage PDF 로컬 캐시
- `pdfrx` 실제 PDF Viewer
- 날짜 → PDF 페이지 자동 계산
- 오늘의 말씀 바로 열기
- 날짜로 말씀 찾아보기
- 한국어 날짜/달력
- 사용자 이름 로컬 저장
- 관리자 모드
- 직접 클릭 조회수 기록
- 많이 본 말씀 TOP 3
- 최근 직접 열어본 말씀 기록
- QnA UI
- PDF 내부 스크롤은 조회수에서 제외

---

# 4. 최종 하단 메뉴

```text
🔎 찾아보기 | 🏠 홈 | 💬 QnA
```

과거의 `일정` 메뉴는 `찾아보기`로 변경했습니다.

---

# 5. 최종 관리자 센터

제목/OCR 기능은 제거했으므로 관리자 화면에도 제목 관련 메뉴가 없습니다.

현재 관리자 센터 방향:

```text
관리자 센터

📄 PDF 관리
📅 날짜 / 페이지 관리
📊 방문 통계
🕘 최근 이용 기록
💬 QnA 관리
```

제거된 기능:

```text
제목 카탈로그 관리
365개 제목 자동 생성
OCR 제목 검수
AI 제목 추출
```

---

# 6. 프로젝트 경로

현재 개발 경로 기준:

```text
D:\my_portfolio\Date-Pdf
```

다른 PC에서는 경로가 달라도 됩니다.

다만 Windows에서 프로젝트가 `D:`에 있고 Flutter Pub Cache가 `C:`에 있을 경우
Kotlin incremental cache 오류가 발생했던 이력이 있으므로
뒤의 `PUB_CACHE` 설정을 반드시 참고하세요.

---

# 7. 권장 프로젝트 구조

```text
Date-Pdf/
│
├── android/
│   ├── app/
│   │   └── build.gradle.kts
│   ├── build.gradle.kts
│   └── gradle.properties
│
├── lib/
│   ├── main.dart
│   ├── firebase_options.dart
│   │
│   ├── screens/
│   │   ├── app_shell.dart
│   │   ├── home_page.dart
│   │   ├── schedule_page.dart
│   │   ├── pdf_page.dart
│   │   ├── qna_page.dart
│   │   ├── settings_page.dart
│   │   ├── admin_code_page.dart
│   │   └── admin_page.dart
│   │
│   └── services/
│       ├── admin_service.dart
│       ├── date_page_mapper.dart
│       ├── local_profile_service.dart
│       ├── pdf_cache_service.dart
│       ├── pdf_repository.dart
│       └── view_history_service.dart
│
├── pubspec.yaml
├── README.md
└── ...
```

---

# 8. 더 이상 필요 없는 OCR/제목 파일

최종 방향에서는 아래 파일은 필요하지 않습니다.

```text
lib/screens/admin_title_catalog_page.dart

lib/services/pdf_title_service.dart
lib/services/pdf_catalog_service.dart
lib/services/pdf_catalog_builder_service.dart
```

프로젝트에 남아 있다면 먼저 import 여부를 확인합니다.

PowerShell:

```powershell
cd D:\my_portfolio\Date-Pdf

Get-ChildItem .\lib -Recurse -Filter *.dart |
Select-String "pdf_title_service|pdf_catalog_service|pdf_catalog_builder_service|admin_title_catalog_page"
```

아무 결과가 없으면 삭제 가능합니다.

---

# 9. ML Kit 제거

최종 버전에서는 제목 OCR을 사용하지 않습니다.

따라서 설치되어 있다면 제거합니다.

```powershell
flutter pub remove google_mlkit_text_recognition
```

`android/app/build.gradle.kts`에 아래 줄이 남아 있다면 삭제합니다.

```kotlin
implementation("com.google.mlkit:text-recognition-korean:16.0.1")
```

---

# 10. PDF 파일

현재 Firebase Storage 기준 파일:

```text
365일 매일묵상말씀.pdf
```

Storage URI 예:

```text
gs://date-pdf.firebasestorage.app/365일 매일묵상말씀.pdf
```

코드에서는 일반적으로:

```dart
FirebaseStorage.instance.ref('365일 매일묵상말씀.pdf');
```

형태로 접근합니다.

향후 더 관리하기 쉬운 구조는:

```text
pdf/current.pdf
```

처럼 고정 경로를 사용하는 것입니다.

---

# 11. PDF 페이지 구조

현재 PDF:

```text
총 368페이지
```

구조:

```text
1~3페이지      앞부분
4페이지         1월 1일
5페이지         1월 2일
...
269페이지       9월 23일
...
368페이지       12월 31일
```

핵심 상수:

```dart
static const int dailyStartPdfPage = 4;
static const int dailyPageCount = 365;
```

---

# 12. 날짜 → PDF 페이지 계산

담당 파일:

```text
lib/services/date_page_mapper.dart
```

개념:

```text
PDF 페이지 = 해당 연도의 날짜 순번 + 3
```

예:

```text
1월 1일
= 1번째 날
= 1 + 3
= PDF 4페이지
```

```text
9월 23일
= 266번째 날
= 266 + 3
= PDF 269페이지
```

사용:

```dart
final page = DatePageMapper.pdfPageForDate(date);
```

역변환:

```dart
final date = DatePageMapper.dateForPdfPage(
  page,
  year: 2026,
);
```

---

# 13. 윤년 주의

현재 PDF는 365일 기준입니다.

따라서 윤년 PDF에서 2월 29일이 별도 페이지로 포함되면
현재 계산 방식과 맞지 않을 수 있습니다.

현재 로직은 365일용 PDF 기준으로 유지합니다.

윤년용 PDF를 실제로 운영하게 될 경우 별도 매핑 정책을 추가해야 합니다.

---

# 14. PDF Viewer 속도 구조

초기 방식:

```text
PDF 버튼 클릭
→ Firebase URL 요청
→ 네트워크에서 PDF 열기
→ 페이지 이동
```

이 방식은 느렸습니다.

현재 권장 방식:

```text
앱 시작
→ Firebase Storage PDF를 기기에 캐시
→ 이후 로컬 PDF 사용
→ PdfViewer.file()
```

담당 파일:

```text
lib/services/pdf_cache_service.dart
```

사용자는 두 번째 실행부터 훨씬 빠르게 PDF를 열 수 있습니다.

---

# 15. PDF 선로딩

앱 홈 화면을 보는 동안 PDF를 미리 준비합니다.

예:

```dart
PdfCacheService().preload();
```

따라서 사용자가 `오늘 말씀 보기`를 누른 시점에는
이미 PDF가 로컬에 준비되어 있을 가능성이 높습니다.

---

# 16. Firebase PDF 변경 확인

로컬 PDF가 있어도 Firebase의 PDF가 바뀌면 새 파일을 내려받아야 합니다.

Firebase Storage의 `generation` 메타데이터를 비교하는 방식으로 운영합니다.

```text
Firebase generation
vs
로컬 저장 generation
```

같음:

```text
기존 로컬 PDF 사용
```

다름:

```text
새 PDF 다운로드
```

네트워크 확인을 너무 자주 하지 않도록 일정 시간 동안 메타데이터 체크를 생략할 수 있습니다.

예:

```dart
Duration(hours: 6)
```

---

# 17. 조회수 집계 정책

매우 중요합니다.

조회수는 **사용자가 말씀을 직접 눌러 PDF에 진입한 경우만** 올라갑니다.

## 조회수 +1

예:

```text
홈 → 오늘 말씀 보기
찾아보기 → 보기
많이 본 말씀 카드 직접 클릭
최근 본 말씀 직접 클릭
```

## 조회수 증가 안 함

```text
PDF 안에서 손가락으로 스크롤
스크롤해서 다른 페이지가 보임
PdfViewer의 onPageChanged
PDF 내부 이전 버튼
PDF 내부 다음 버튼
```

즉:

```text
"스크롤 중 우연히 지나간 페이지"
```

는 조회수에 포함하지 않습니다.

---

# 18. 조회수 Firestore 구조

예:

```text
page_stats
└── 269
    ├── page: 269
    ├── views: 12
    ├── countType: "direct_open_only"
    └── lastDirectOpenedAt: Timestamp
```

담당 서비스:

```text
lib/services/view_history_service.dart
```

직접 진입할 때:

```dart
history.recordDirectOpen(
  page: page,
  date: date,
);
```

를 호출합니다.

---

# 19. 최근 본 말씀

최근 본 말씀도 `직접 진입`만 기록합니다.

PDF에서 스크롤하다 지나간 페이지는 최근 기록에 들어가지 않습니다.

현재 최근 기록은 기기 로컬 `SharedPreferences`를 사용할 수 있습니다.

예:

```text
오늘의 말씀
2026년 9월 23일 (수)
```

---

# 20. 많이 본 말씀

Firestore `page_stats`에서 직접 클릭 수가 높은 페이지를 가져옵니다.

표시:

```text
🥇
말씀
9월 23일
12회
```

즉:

```text
순위
고정 표시 "말씀"
날짜
직접 클릭 조회수
```

구조입니다.

---

# 21. 사용자 이름

일반 사용자는 별도의 회원가입 없이 사용할 수 있습니다.

사용자 이름은 표시용입니다.

```text
사용자 이름
↓
SharedPreferences
↓
"사용자님"
```

인증용 데이터가 아닙니다.

---

# 22. 관리자 모드

흐름:

```text
설정
↓
관리자 모드
↓
승인코드 입력
↓
관리자 센터
```

현재 승인코드 방식은 개발용 프로토타입입니다.

실제 서비스에서 관리자 비밀번호/승인코드를 앱 코드에 하드코딩하면 안 됩니다.

최종 서비스에서는:

```text
Flutter
↓
서버 / Cloud Function
↓
승인코드 검증
↓
Firebase Auth / Custom Claims
↓
관리자 권한
```

방식을 권장합니다.

---

# 23. 한국어 날짜 설정

과거 다음 오류가 있었습니다.

```text
LocaleDataException:
Locale data has not been initialized
```

`main.dart`에서 반드시:

```dart
import 'package:intl/date_symbol_data_local.dart';
```

그리고 Firebase 초기화 전에:

```dart
await initializeDateFormatting('ko_KR', null);
```

를 실행합니다.

---

# 24. 한국어 달력

`CalendarDatePicker`를 한국어로 표시하려면
`MaterialApp`에 locale 설정이 필요합니다.

```dart
locale: const Locale('ko', 'KR'),

supportedLocales: const [
  Locale('ko', 'KR'),
],

localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

필요 import:

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
```

---

# 25. 현재 주요 Flutter 패키지

최종 방향 기준 예:

```yaml
dependencies:
  flutter:
    sdk: flutter

  flutter_localizations:
    sdk: flutter

  firebase_core:
  firebase_auth:
  firebase_storage:
  cloud_firestore:

  shared_preferences:
  intl:
  pdfrx:
  path_provider:
  file_picker:
```

프로젝트 실제 `pubspec.yaml`이 최종 기준입니다.

---

# 26. 새 PC 세팅 — Flutter

Flutter 설치 후:

```powershell
flutter --version
flutter doctor -v
```

Android 관련 항목에 치명적인 오류가 없는지 확인합니다.

---

# 27. JDK 17

현재 프로젝트는 JDK 17 사용을 권장합니다.

설치:

```powershell
winget install EclipseAdoptium.Temurin.17.JDK
```

설치 후 PowerShell을 새로 열고:

```powershell
java -version
```

정상 예:

```text
openjdk version "17..."
```

---

# 28. JAVA_HOME

주의:

`JAVA_HOME`에는 `java.exe`까지 넣지 않습니다.

잘못된 예:

```text
C:\Program Files\Eclipse Adoptium\jdk-17...\bin\java.exe
```

정상:

```text
C:\Program Files\Eclipse Adoptium\jdk-17...
```

예:

```powershell
$env:JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
```

Flutter에도 지정:

```powershell
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
```

확인:

```powershell
flutter doctor -v
```

---

# 29. Android SDK / NDK

과거 오류:

```text
Package ndk not found.
Package 28.2.13676358 not found.
```

프로젝트에서 사용했던 NDK:

```text
28.2.13676358
```

Android Studio:

```text
Tools
→ SDK Manager
→ SDK Tools
→ Show Package Details
→ NDK (Side by side)
→ 28.2.13676358
```

같이 설치 권장:

```text
Android SDK Command-line Tools
Android SDK Build-Tools
CMake
NDK (Side by side)
```

확인:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Android\sdk\ndk"
```

---

# 30. 중요 — D: 프로젝트 / C: Pub Cache 오류

실제로 발생했던 오류:

```text
Could not close incremental caches
```

```text
this and base files have different roots
```

원인:

```text
프로젝트
D:\my_portfolio\Date-Pdf

Flutter Pub Cache
C:\Users\...\AppData\Local\Pub\Cache
```

처럼 서로 다른 드라이브였습니다.

---

# 31. PUB_CACHE를 D:로 이동

폴더 생성:

```powershell
New-Item -ItemType Directory -Force "D:\PubCache"
```

현재 PowerShell:

```powershell
$env:PUB_CACHE="D:\PubCache"
```

영구 설정:

```powershell
[Environment]::SetEnvironmentVariable(
    "PUB_CACHE",
    "D:\PubCache",
    "User"
)
```

PowerShell을 새로 연 뒤 확인:

```powershell
echo $env:PUB_CACHE
```

정상:

```text
D:\PubCache
```

---

# 32. Pub Cache 변경 후 캐시 삭제

```powershell
cd D:\my_portfolio\Date-Pdf
```

Gradle daemon 종료:

```powershell
cd android
.\gradlew --stop
cd ..
```

캐시 삭제:

```powershell
flutter clean

Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
```

다시:

```powershell
flutter pub get
```

확인:

```powershell
Select-String -Path ".dart_tool\package_config.json" -Pattern "D:/PubCache"
```

---

# 33. Kotlin cache 대응

필요 시:

```text
android/gradle.properties
```

에:

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

를 사용할 수 있습니다.

단, C:/D: 드라이브 충돌이 원인이라면 먼저 `PUB_CACHE`를 해결해야 합니다.

---

# 34. Firebase 연결

FlutterFire CLI:

```powershell
dart pub global activate flutterfire_cli
```

Firebase CLI 로그인:

```powershell
firebase login
```

프로젝트 루트:

```powershell
cd D:\my_portfolio\Date-Pdf
```

설정:

```powershell
flutterfire configure
```

Firebase 프로젝트:

```text
date-pdf
```

Android를 반드시 포함합니다.

---

# 35. firebase_options.dart

`flutterfire configure`가 완료되면:

```text
lib/firebase_options.dart
```

가 생성/갱신됩니다.

Windows에서 Flutter 앱을 실행할 경우 Windows 설정도 선택해야 합니다.

Android만 사용할 경우 Android 디바이스에서 실행하면 됩니다.

---

# 36. Firestore 데이터베이스 생성

실제로 발생했던 오류:

```text
The database (default) does not exist for project date-pdf
```

해결:

Firebase Console:

```text
date-pdf
→ Build
→ Firestore Database
→ Create database
```

반드시 `(default)` Firestore database를 생성합니다.

현재 코드:

```dart
FirebaseFirestore.instance
```

는 `(default)` DB를 사용합니다.

---

# 37. Firestore Rules

개발 중에는 테스트 규칙을 사용할 수 있지만
실제 배포 전에 반드시 보안 규칙을 정리해야 합니다.

특히 보호 대상:

```text
관리자 데이터
PDF 관리 데이터
QnA 관리자 답변
민감한 쓰기 작업
```

일반 사용자에게 전체 Firestore 쓰기 권한을 주지 않는 것을 권장합니다.

---

# 38. Firebase Storage

현재 Storage에는 PDF가 있어야 합니다.

예:

```text
365일 매일묵상말씀.pdf
```

앱에서 파일을 읽지 못할 경우:

- Storage 파일명 확인
- Firebase 프로젝트 확인
- Storage Rules 확인
- `firebase_options.dart` 프로젝트 확인

순서로 확인합니다.

---

# 39. 평소 실행 방법

PowerShell:

```powershell
cd D:\my_portfolio\Date-Pdf
```

Pub Cache 확인:

```powershell
echo $env:PUB_CACHE
```

필요하면:

```powershell
$env:PUB_CACHE="D:\PubCache"
```

패키지:

```powershell
flutter pub get
```

디바이스:

```powershell
flutter devices
```

실행:

```powershell
flutter run
```

---

# 40. 완전 재빌드

빌드가 이상할 때:

```powershell
cd D:\my_portfolio\Date-Pdf

cd android
.\gradlew --stop
cd ..

flutter clean

Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue

flutter pub get
flutter run
```

---

# 41. 과거 오류 — Dart const

오류:

```text
Not a constant expression
```

원인:

런타임 값:

```dart
todayPdfPage
```

를:

```dart
children: const [...]
```

안에 넣음.

해결:

해당 부모의 `const` 제거.

---

# 42. 과거 오류 — Windows Firebase 미설정

```text
DefaultFirebaseOptions have not been configured for windows
```

해결:

```powershell
flutterfire configure
```

에서 Windows 추가.

또는 Android 에뮬레이터를 선택해서 실행.

---

# 43. 과거 오류 — JAVA_HOME 없음

```text
JAVA_HOME is not set
```

해결:

JDK 17 설치 + `JAVA_HOME` 설정.

---

# 44. 과거 오류 — java.exe\bin\java

오류:

```text
...\bin\java.exe\bin\java
```

원인:

JDK 경로 설정에 `bin\java.exe`까지 넣음.

해결:

JDK 최상위 폴더까지만 지정.

---

# 45. 과거 오류 — NDK

```text
Package ndk not found
```

```text
Package 28.2.13676358 not found
```

해결:

Android Studio SDK Manager에서 NDK `28.2.13676358` 설치.

---

# 46. 과거 오류 — Kotlin different roots

```text
this and base files have different roots
```

해결:

프로젝트와 Pub Cache를 같은 드라이브로 맞춤.

현재 권장:

```text
D:\my_portfolio\Date-Pdf
D:\PubCache
```

---

# 47. 과거 오류 — Invalid depfile

```text
Invalid depfile
.dart_tool\flutter_build\...\kernel_snapshot_program.d
```

해결:

```powershell
flutter clean
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
flutter pub get
```

---

# 48. 과거 오류 — LocaleDataException

```text
LocaleDataException
```

해결:

```dart
await initializeDateFormatting('ko_KR', null);
```

---

# 49. 최종적으로 사용하지 않는 기능

현재 최종 방향에서는 아래 기능을 사용하지 않습니다.

```text
PDF 제목 OCR
Google ML Kit 제목 인식
AI Vision 제목 인식
제목 카탈로그
제목 Firestore 저장
사용자 화면 제목 자동 추출
```

이 기능 때문에 추가했던 패키지/서비스는 정리하는 것이 좋습니다.

---

# 50. GitHub에 올리기 전 반드시 확인할 것

GitHub에 코드를 올리기 전에 비밀정보가 포함되지 않았는지 확인합니다.

절대 커밋하면 안 되는 것:

```text
.env
Firebase Admin 서비스 계정 JSON
firebase-service-account.json
*.jks
*.keystore
android/key.properties
개인 API Key
비밀번호
토큰
```

특히:

```text
Firebase 서비스 계정 JSON
OpenAI API Key
```

는 절대 GitHub에 올리면 안 됩니다.

---

# 51. 권장 .gitignore

프로젝트 루트의:

```text
.gitignore
```

에 최소한 다음을 포함하세요.

```gitignore
# Flutter / Dart
.dart_tool/
.packages
.pub/
build/

# IDE
.idea/
.vscode/
*.iml

# Android local
android/local.properties
android/key.properties
*.jks
*.keystore

# iOS generated/local
ios/Pods/
ios/.symlinks/
ios/Flutter/ephemeral/

# Secrets
.env
.env.*
!.env.example
*service-account*.json
firebase-service-account*.json

# Python tools / caches if any
.venv/
__pycache__/
*.pyc

# OS
.DS_Store
Thumbs.db
```

주의:

`google-services.json`과 `firebase_options.dart`는 Firebase 클라이언트 설정 파일이며
서비스 계정 비밀키와는 성격이 다릅니다.

그래도 공개 저장소로 운영할 경우 프로젝트 정책에 맞춰 관리하세요.

---

# 52. Git 설치 확인

PowerShell:

```powershell
git --version
```

없다면 Git for Windows를 먼저 설치합니다.

---

# 53. 현재 프로젝트가 Git 저장소인지 확인

```powershell
cd D:\my_portfolio\Date-Pdf

git status
```

정상 Git 저장소라면 상태가 표시됩니다.

아직 Git 저장소가 아니면:

```text
fatal: not a git repository
```

가 나옵니다.

---

# 54. 이미 GitHub repo가 연결되어 있는지 확인

```powershell
git remote -v
```

예:

```text
origin  https://github.com/USERNAME/Date-Pdf.git (fetch)
origin  https://github.com/USERNAME/Date-Pdf.git (push)
```

이렇게 나오면 이미 GitHub repo가 연결된 것입니다.

---

# 55. 기존 GitHub repo에 현재 프로젝트 저장

이미 `origin`이 있는 경우 가장 기본적인 순서:

```powershell
cd D:\my_portfolio\Date-Pdf

git status
git add .
git commit -m "Finalize DatePDF v7.1"
git push
```

처음 main 브랜치를 push하는 경우:

```powershell
git push -u origin main
```

---

# 56. 처음 GitHub repo를 만드는 경우

GitHub 웹사이트에서 새 repository를 생성합니다.

권장:

```text
Repository name:
Date-Pdf
```

이미 로컬에 README가 있으므로
처음 repo를 만들 때 가능하면:

```text
Add a README
Add .gitignore
Add license
```

를 체크하지 않고 **빈 repo**로 만드는 것이 충돌을 줄이기 쉽습니다.

---

# 57. 로컬 프로젝트를 새 GitHub repo에 연결

프로젝트 루트:

```powershell
cd D:\my_portfolio\Date-Pdf
```

Git 초기화:

```powershell
git init
```

브랜치:

```powershell
git branch -M main
```

모든 파일 추가:

```powershell
git add .
```

확인:

```powershell
git status
```

첫 커밋:

```powershell
git commit -m "Initial DatePDF project"
```

GitHub repo 연결:

```powershell
git remote add origin https://github.com/USERNAME/Date-Pdf.git
```

Push:

```powershell
git push -u origin main
```

`USERNAME`과 repo 이름은 실제 GitHub 주소로 바꿉니다.

---

# 58. origin이 이미 있는데 주소가 틀린 경우

확인:

```powershell
git remote -v
```

변경:

```powershell
git remote set-url origin https://github.com/USERNAME/Date-Pdf.git
```

다시:

```powershell
git push -u origin main
```

---

# 59. GitHub repo에 이미 README가 있는 경우

GitHub에서 repo를 만들 때 README를 먼저 생성했다면
로컬과 원격 히스토리가 다를 수 있습니다.

먼저:

```powershell
git pull --rebase origin main
```

문제가 없다면:

```powershell
git push -u origin main
```

충돌이 생기면 충돌 파일을 직접 정리한 뒤:

```powershell
git add .
git rebase --continue
git push
```

처음부터 빈 repo를 만드는 것이 가장 편합니다.

---

# 60. GitHub 로그인

GitHub는 일반 계정 비밀번호를 Git push 비밀번호처럼 사용하는 방식이 아닙니다.

Git for Windows의 Git Credential Manager가 설치되어 있다면
`git push` 시 브라우저 로그인 창이 뜰 수 있습니다.

브라우저에서 GitHub 로그인을 완료하면 됩니다.

---

# 61. 현재 프로젝트를 GitHub에 올릴 때 권장 순서

실제로는 아래 순서만 기억하면 됩니다.

```powershell
cd D:\my_portfolio\Date-Pdf
```

비밀 파일 확인:

```powershell
git status
```

.gitignore 확인 후:

```powershell
git add .
```

다시 확인:

```powershell
git status
```

커밋:

```powershell
git commit -m "DatePDF final setup"
```

원격 확인:

```powershell
git remote -v
```

Push:

```powershell
git push
```

---

# 62. 이후 개발할 때 Git 사용

작업 시작:

```powershell
git pull
```

코드 수정.

변경 확인:

```powershell
git status
```

저장:

```powershell
git add .
git commit -m "Improve PDF view statistics"
git push
```

---

# 63. 커밋 메시지 예시

```text
Fix PDF local caching
Update Korean calendar UI
Add direct-open page statistics
Remove OCR title extraction
Clean up admin menu
Finalize DatePDF v7.1
```

---

# 64. 현재 프로젝트 전체를 안전하게 백업하는 방법

GitHub:

```text
소스 코드
설정 파일
README
```

백업.

Firebase:

```text
Firestore 데이터
Storage PDF
```

는 별도 클라우드 데이터입니다.

즉 GitHub에 push했다고 해서 Firebase Storage의 PDF와 Firestore 데이터가
GitHub에 같이 백업되는 것은 아닙니다.

필요하면 Firebase 데이터도 별도로 백업해야 합니다.

---

# 65. APK / build 결과는 Git에 올리지 않기

다음은 Git에 올리지 않는 것을 권장합니다.

```text
build/
.dart_tool/
```

APK/AAB 배포 파일이 필요하다면 GitHub Releases나 별도 배포 스토리지를 사용하는 것이 좋습니다.

---

# 66. 배포용 Android 빌드

테스트가 끝난 뒤:

```powershell
flutter build appbundle --release
```

또는 APK:

```powershell
flutter build apk --release
```

릴리스 서명키는 GitHub에 커밋하지 않습니다.

---

# 67. 현재 최종 UI 용어

```text
오늘의 PDF
→ 오늘의 말씀
```

```text
일정
→ 찾아보기
```

```text
많이 방문한 페이지
→ 많이 본 말씀
```

```text
최근 본 페이지
→ 최근 본 말씀
```

개별 제목:

```text
OCR 제목
→ 사용하지 않음
```

---

# 68. 최종 데이터 흐름

앱 시작:

```text
Flutter
│
├─ Firebase 초기화
├─ 한국어 locale 초기화
├─ 사용자 이름 로드
├─ PDF 로컬 preload
└─ 홈 표시
```

오늘 말씀:

```text
오늘 날짜
↓
DatePageMapper
↓
PDF 페이지 계산
↓
오늘 말씀 보기 클릭
↓
직접 클릭 조회수 +1
↓
로컬 캐시 PDF 열기
↓
해당 페이지 표시
```

찾아보기:

```text
날짜 선택
↓
PDF 페이지 계산
↓
보기 클릭
↓
직접 클릭 조회수 +1
↓
PDF 열기
```

스크롤:

```text
PDF 내부 스크롤
↓
다른 페이지 표시
↓
조회수 변화 없음
```

---

# 69. 향후 개발 우선순위

권장 순서:

```text
1. PDF 관리 실제 구현
2. 날짜/페이지 관리자 수정 UI
3. 방문 통계 관리자 화면
4. QnA Firestore 연결
5. 관리자 인증 서버화
6. Firebase Security Rules 정리
7. PDF 버전 관리
8. Push Notification
9. Android 비공개 테스트
10. iOS TestFlight
```

---

# 70. 최종 체크리스트

새 PC에서:

```text
[ ] Flutter 설치
[ ] flutter doctor -v 정상
[ ] JDK 17 설치
[ ] JAVA_HOME 정상
[ ] Android SDK 설치
[ ] NDK 28.2.13676358 확인
[ ] D: 프로젝트면 PUB_CACHE를 D:로 설정
[ ] flutterfire configure
[ ] Firebase Storage PDF 확인
[ ] Firestore (default) DB 생성
[ ] flutter pub get
[ ] Android 디바이스 확인
[ ] flutter run
```

코드:

```text
[ ] OCR 관련 파일 제거
[ ] ML Kit 패키지 제거
[ ] admin_title_catalog_page.dart 제거
[ ] 관리자 화면에서 제목 메뉴 제거
[ ] 직접 클릭만 조회수 기록
[ ] PDF 스크롤은 조회수 미기록
[ ] 찾아보기 한국어 날짜 표시
```

GitHub:

```text
[ ] .gitignore 확인
[ ] API Key 없음
[ ] 서비스 계정 JSON 없음
[ ] keystore 없음
[ ] git status 확인
[ ] git add .
[ ] git commit
[ ] git remote -v
[ ] git push
```

---

# 71. 현재 최종 상태

```text
DatePDF v7.1

Flutter Android
↓
Firebase Storage PDF
↓
기기 로컬 PDF 캐시
↓
날짜별 페이지 자동 이동

Firestore
↓
직접 클릭 조회수

SharedPreferences
↓
사용자 이름
↓
최근 직접 열어본 말씀

UI
↓
오늘의 말씀
찾아보기
많이 본 말씀
최근 본 말씀
QnA
관리자 센터
```

제목 자동 추출은 사용하지 않습니다.

---

# 72. 변경 이력

## 2026-09-23 ~ 2026-09-24 개발 정리

- Flutter UI 구성
- 날짜 → PDF 페이지 자동 계산
- Firebase 연결
- Firebase Storage PDF 업로드 및 읽기
- `pdfrx` 실제 PDF Viewer 적용
- PDF 로컬 캐시 추가
- 한국어 날짜 초기화
- 한국어 CalendarDatePicker 적용
- JDK 17 환경 구성
- NDK 28.2.13676358 문제 해결
- C:/D: Kotlin cache 충돌 해결
- Pub Cache D: 이동
- Firestore `(default)` 데이터베이스 필요 확인
- 제목 OCR 방식 테스트
- 손글씨/혼합 폰트 제목 인식 한계 확인
- 제목 자동 추출 최종 제거 결정
- 사용자 UI를 `오늘의 말씀` 중심으로 단순화
- `일정` → `찾아보기`
- `많이 방문한 페이지` → `많이 본 말씀`
- `최근 본 페이지` → `최근 본 말씀`
- 직접 클릭 조회수 정책 적용
- PDF 내부 스크롤 조회수 제외
- 관리자 제목/OCR 메뉴 제거
- 최종 GitHub 백업/업로드 절차 문서화

---

# 73. 핵심 원칙

이 프로젝트의 최종 원칙은 다음과 같습니다.

```text
복잡한 OCR보다 안정적인 날짜 매핑
네트워크 PDF보다 로컬 캐시
페이지 노출보다 직접 클릭 통계
기술적인 페이지 번호보다 사용자 친화적인 날짜/말씀 UI
비밀키는 GitHub에 저장하지 않기
```

이 문서를 현재 프로젝트의 최종 기준 README로 사용합니다.
