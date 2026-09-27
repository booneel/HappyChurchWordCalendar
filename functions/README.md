# DatePDF 알림 Functions

앱이 종료된 상태에서도 Q&A 답변과 PDF 교체 알림을 보내려면 Firebase Functions를 한 번 배포해야 합니다.

```bash
firebase login
firebase use date-pdf
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
