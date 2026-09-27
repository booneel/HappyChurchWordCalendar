const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();

const db = admin.firestore();

const adminNotificationEmail = (process.env.ADMIN_NOTIFICATION_EMAIL || '').trim();
const smtpHost = (process.env.SMTP_HOST || '').trim();
const smtpPort = Number.parseInt(process.env.SMTP_PORT || '465', 10);
const smtpSecure = (process.env.SMTP_SECURE || 'true').toLowerCase() !== 'false';
const smtpUser = (process.env.SMTP_USER || '').trim();
const smtpPassword = process.env.SMTP_PASSWORD || '';
const smtpFrom = (process.env.SMTP_FROM || smtpUser).trim();

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function createEmailTransporter() {
  if (!adminNotificationEmail || !smtpHost || !smtpUser || !smtpPassword) {
    return null;
  }

  return nodemailer.createTransport({
    host: smtpHost,
    port: smtpPort,
    secure: smtpSecure,
    auth: {
      user: smtpUser,
      pass: smtpPassword,
    },
  });
}

async function sendAdminQnaEmail({ questionId, data }) {
  const transporter = createEmailTransporter();
  if (!transporter) {
    console.log(
      'QnA email notification is disabled because email settings are empty.',
    );
    return;
  }

  const title = data.title || '제목 없는 질문';
  const content = data.content || '';
  const authorName = data.authorName || '익명';
  const subject = `[DatePDF] 새 Q&A 질문: ${shortText(title, 100)}`;
  const text = [
    '새 Q&A 질문이 등록되었습니다.',
    '',
    `제목: ${title}`,
    `작성자: ${authorName}`,
    `내용: ${content}`,
    `질문 ID: ${questionId}`,
  ].join('\n');
  const html = [
    '<h2>DatePDF 새 Q&A 질문</h2>',
    `<p><strong>제목:</strong> ${escapeHtml(title)}</p>`,
    `<p><strong>작성자:</strong> ${escapeHtml(authorName)}</p>`,
    `<p><strong>내용:</strong><br>${escapeHtml(content).replaceAll('\n', '<br>')}</p>`,
    `<p><strong>질문 ID:</strong> ${escapeHtml(questionId)}</p>`,
  ].join('');

  await transporter.sendMail({
    from: smtpFrom,
    to: adminNotificationEmail,
    subject,
    text,
    html,
  });
}

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

exports.notifyAdminOnQnaCreated = functions.firestore
  .document('qna/{questionId}')
  .onCreate(async (snapshot, context) => {
    await sendAdminQnaEmail({
      questionId: context.params.questionId,
      data: snapshot.data() || {},
    });
  });

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
