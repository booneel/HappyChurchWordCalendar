# TheWordCalendar 알림 Functions

앱이 종료된 상태에서도 Q&A 답변과 PDF 교체 알림을 보내려면 Firebase Functions를 한 번 배포해야 합니다.

```bash
firebase login
firebase use thewordcalendar-f768c
firebase deploy --only functions
```

앱은 `notification_tokens` 컬렉션에 FCM 토큰을 등록하고, Q&A 문서에는 질문을 만든 기기의 토큰을 저장합니다. Firestore 보안 규칙을 사용 중이면 앱이 해당 토큰 문서를 등록할 수 있도록 규칙을 함께 허용해야 합니다.

## 관리자 Q&A 이메일

`functions/.env.example`을 복사해 `functions/.env`를 만들고 값을 입력하면 새 Q&A 등록 시 관리자 이메일로 전송됩니다. 값이 비어 있으면 이메일 기능은 자동으로 비활성화됩니다.

```bash
copy functions/.env.example functions/.env
firebase deploy --only functions
```

Gmail을 사용할 경우 `SMTP_USER`에는 발송 Gmail 주소를, `SMTP_PASSWORD`에는 일반 비밀번호가 아닌 Gmail 앱 비밀번호를 입력합니다.

## NAS 앱의 백그라운드 푸시 중계

NAS는 Firebase 대신 데이터 API로 동작하지만, 휴대폰이 앱을 닫은 뒤에도 알림을 받도록 이 프로젝트의 FCM을 중계기로 사용할 수 있습니다. NAS 컨테이너에는 Firebase 서비스 계정 키를 저장하지 않습니다. NAS가 아래 HTTPS Function을 호출하고, Function이 Firebase Admin SDK로 NAS 앱의 등록 기기에 FCM을 보냅니다.

1. `deploy/synology/generate_tokens.bat`을 실행해 출력된 `WORDCALENDAR_NAS_PUSH_SECRET` 값을 복사합니다.
2. `functions/.env.example`을 `functions/.env`로 복사하고 `NAS_PUSH_SECRET`에 그 값을 넣습니다. 같은 비밀값을 NAS `/volume1/docker/wordcalendar/.env`의 `WORDCALENDAR_NAS_PUSH_SECRET`에 넣습니다. `.env` 파일은 Git에 커밋하지 않습니다.
3. `firebase deploy --only functions`로 Functions를 배포합니다. 출력되는 `notifyNasEvent` HTTPS URL을 NAS `.env`의 `WORDCALENDAR_NAS_PUSH_URL`에 넣습니다. 갱신된 NAS Python 파일을 복사한 뒤 NAS 프로젝트 경로에서 `sudo docker compose up -d --build`를 실행합니다.
4. NAS 앱을 FCM을 포함해 다시 빌드·설치하고 휴대폰 알림 권한을 허용합니다. 앱을 한 번 실행해 FCM 토큰이 Firestore `notification_tokens` 컬렉션에 `backend: nas`로 등록됐는지 확인합니다. 앱의 읽기/쓰기 규칙은 현재 클라이언트 토큰 등록을 허용해야 합니다.

NAS PDF 교체 시 등록된 NAS 기기에 알리고, 관리자 답변 시 질문 작성 기기에 알립니다. 앱이 열려 있을 때는 Flutter가 FCM 메시지를 받아 시스템 알림으로 표시하고, 백그라운드/종료 상태에서는 FCM/Android 또는 APNs가 알림을 표시합니다. 중계가 비활성화되거나 Functions 호출에 실패하면 NAS 데이터 저장은 성공으로 유지되고, 앱이 열린 동안 30초 주기 확인이 대체 경로로 동작합니다. Functions 로그에서 `notifyNasEvent` 호출 상태를 확인합니다.
