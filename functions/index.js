const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

function shortText(value, length = 80) {
  const text = String(value || '').trim();
  return text.length <= length ? text : `${text.slice(0, length)}…`;
}

async function sendToTokens({ tokens, title, body, type, questionId }) {
  if (tokens.length === 0) return;

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: {
      type,
      title,
      body,
      ...(questionId ? { questionId } : {}),
    },
    android: {
      priority: 'high',
      notification: { channelId: 'datepdf_updates' },
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
  });

  const invalidTokens = [];
  response.responses.forEach((result, index) => {
    const code = result.error && result.error.code;
    if (code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token') {
      invalidTokens.push(tokens[index]);
    }
  });

  if (invalidTokens.length > 0) {
    const batch = db.batch();
    invalidTokens.forEach((token) => {
      batch.delete(db.collection('notification_tokens').doc(token.replaceAll('/', '_')));
    });
    await batch.commit();
  }
}

async function getRegisteredTokens() {
  const snapshot = await db.collection('notification_tokens').get();
  return snapshot.docs
    .map((doc) => doc.data().token || doc.id)
    .filter((token) => typeof token === 'string' && token.length > 0);
}

exports.notifyOnQnaAnswer = functions.firestore
  .document('qna/{questionId}')
  .onUpdate(async (change, context) => {
  const before = change.before.data() || {};
  const after = change.after.data() || {};
  if (before.isAnswered === true || after.isAnswered !== true) return;

  const token = after.notificationToken;
  if (typeof token !== 'string' || token.length === 0) return;

  await sendToTokens({
    tokens: [token],
    title: 'Q&A 답변이 등록되었습니다',
    body: shortText(after.answer || '질문에 대한 답변을 확인해 보세요.'),
    type: 'qna_answer',
    questionId: context.params.questionId,
  });
});

exports.notifyOnPdfUpdate = functions.firestore
  .document('pdf_documents/current')
  .onWrite(async (change) => {
  const before = change.before.exists
    ? change.before.data() || {}
    : {};
  const after = change.after.exists
    ? change.after.data() || {}
    : {};
  if (!change.after.exists) return;

  const beforeVersion = `${before.updatedAt || ''}|${before.pdfUrl || ''}|${before.fileSize || ''}`;
  const afterVersion = `${after.updatedAt || ''}|${after.pdfUrl || ''}|${after.fileSize || ''}`;
  if (beforeVersion === afterVersion) return;

  const tokens = await getRegisteredTokens();
  await sendToTokens({
    tokens,
    title: 'PDF가 업데이트되었습니다',
    body: '새로운 말씀 PDF를 확인해 보세요.',
    type: 'pdf_update',
  });
});
