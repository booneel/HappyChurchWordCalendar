const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const crypto = require('crypto');

admin.initializeApp();

const db = admin.firestore();

const adminNotificationEmail = (process.env.ADMIN_NOTIFICATION_EMAIL || '').trim();
const smtpHost = (process.env.SMTP_HOST || '').trim();
const smtpPort = Number.parseInt(process.env.SMTP_PORT || '465', 10);
const smtpSecure = (process.env.SMTP_SECURE || 'true').toLowerCase() !== 'false';
const smtpUser = (process.env.SMTP_USER || '').trim();
const smtpPassword = process.env.SMTP_PASSWORD || '';
const smtpFrom = (process.env.SMTP_FROM || smtpUser).trim();
const nasPushSecret = (process.env.NAS_PUSH_SECRET || '').trim();

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
  const subject = `[TheWordCalendar] 새 Q&A 질문: ${shortText(title, 100)}`;
  const text = [
    '새 Q&A 질문이 등록되었습니다.',
    '',
    `제목: ${title}`,
    `작성자: ${authorName}`,
    `내용: ${content}`,
    `질문 ID: ${questionId}`,
  ].join('\n');
  const html = [
    '<h2>TheWordCalendar 새 Q&A 질문</h2>',
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
      notification: { channelId: 'wordcalendar_updates' },
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

async function getRegisteredTokens({ backend } = {}) {
  const snapshot = await db.collection('notification_tokens').get();
  return snapshot.docs
    .filter((doc) => {
      const registeredBackend = doc.data().backend;
      if (backend === 'nas') return registeredBackend === 'nas';
      return registeredBackend !== 'nas';
    })
    .map((doc) => doc.data().token || doc.id)
    .filter((token) => typeof token === 'string' && token.length > 0);
}

function hasValidNasPushSecret(req) {
  const authorization = String(req.get('authorization') || '');
  if (!nasPushSecret || !/^Bearer\s+/i.test(authorization)) return false;
  const provided = authorization.replace(/^Bearer\s+/i, '');
  const expectedBuffer = Buffer.from(nasPushSecret);
  const providedBuffer = Buffer.from(provided);
  return expectedBuffer.length === providedBuffer.length &&
    crypto.timingSafeEqual(expectedBuffer, providedBuffer);
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

  const tokens = await getRegisteredTokens({ backend: 'firebase' });
  await sendToTokens({
    tokens,
    title: 'PDF가 업데이트되었습니다',
    body: '새로운 말씀 PDF를 확인해 보세요.',
    type: 'pdf_update',
  });
});

exports.notifyNasEvent = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send('POST required');
  if (!hasValidNasPushSecret(req)) return res.status(401).send('Unauthorized');

  const { type, deviceId, answer, questionId } = req.body || {};
  if (type === 'pdf_update') {
    const tokens = await getRegisteredTokens({ backend: 'nas' });
    await sendToTokens({
      tokens,
      title: 'PDF가 업데이트되었습니다',
      body: '새로운 말씀 PDF를 확인해 보세요.',
      type: 'pdf_update',
    });
    return res.status(200).json({ ok: true, recipients: tokens.length });
  }

  if (type === 'qna_answer' && typeof deviceId === 'string' &&
      deviceId.length > 0 && typeof questionId === 'string' && questionId.length > 0) {
    const snapshot = await db.collection('notification_tokens')
      .where('deviceId', '==', deviceId)
      .get();
    const tokens = snapshot.docs
      .filter((doc) => doc.data().backend === 'nas')
      .map((doc) => doc.data().token || doc.id)
      .filter((token) => typeof token === 'string' && token.length > 0);
    await sendToTokens({
      tokens,
      title: 'Q&A 답변이 등록되었습니다',
      body: shortText(answer || '질문에 대한 답변을 확인해 보세요.'),
      type: 'qna_answer',
      questionId,
    });
    return res.status(200).json({ ok: true, recipients: tokens.length });
  }

  return res.status(400).send('Unsupported notification event');
});
