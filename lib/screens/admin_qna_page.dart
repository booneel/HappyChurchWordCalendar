import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/backend_config.dart';
import '../services/nas_api_client.dart';
import '../services/qna_service.dart';

class AdminQnaPage extends StatefulWidget {
  const AdminQnaPage({super.key});

  @override
  State<AdminQnaPage> createState() => _AdminQnaPageState();
}

class _AdminQnaPageState extends State<AdminQnaPage> {
  final QnaService _qnaService = QnaService();
  String _filterMode = 'unread'; // 'unread', 'unanswered', 'all'

  void _openAnswerDialog(QnaItem item) {
    final answerController = TextEditingController(text: item.answer ?? '');
    final dateFormat = DateFormat('yyyy년 M월 d일 HH:mm', 'ko_KR');
    final readOnly = BackendConfig.useNas &&
        (!NasApiClient.instance.hasAdminToken ||
            !NasApiClient.instance.isServerReachable);

    if (!readOnly) _qnaService.markAsReadByAdmin(item.id);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.56,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      '작성자: ${item.authorName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      dateFormat.format(item.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                const Text(
                  '📝 질문 내용',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.content.isEmpty ? item.title : item.content,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '💬 관리자 답변 작성',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF4F7CAC),
                  ),
                ),
                const SizedBox(height: 6),
                if (readOnly)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                        '오프라인에서는 저장된 Q&A를 읽기만 할 수 있습니다. NAS에 다시 연결되면 답변할 수 있습니다.'),
                  ),
                TextField(
                  controller: answerController,
                  readOnly: readOnly,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 500,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '답변 내용을 입력하세요...',
                    alignLabelWithHint: true,
                    contentPadding: EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!readOnly)
            TextButton.icon(
              onPressed: () => _confirmAndDeleteQuestion(item, dialogContext),
              icon: const Icon(Icons.delete_outline),
              label: const Text('질문 삭제'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          if (!readOnly)
            FilledButton(
              onPressed: () async {
                final text = answerController.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('답변 내용을 입력해 주세요.')),
                  );
                  return;
                }

                try {
                  await _qnaService.answerQuestion(
                    questionId: item.id,
                    answer: text,
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'NAS에 연결되지 않아 답변을 저장하지 못했습니다. 다시 연결한 뒤 시도해 주세요.')),
                  );
                  return;
                }

                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('답변이 등록되었습니다.')));
              },
              child: const Text('답변 저장'),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeleteQuestion(
    QnaItem item,
    BuildContext dialogContext,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('질문 삭제'),
        content: Text('「${item.title}」 질문을 삭제할까요? 삭제하면 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _qnaService.deleteQuestion(item.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('질문을 삭제하지 못했습니다. 연결과 관리자 권한을 확인해 주세요.')),
      );
      return;
    }

    if (!mounted || !dialogContext.mounted) return;
    Navigator.pop(dialogContext);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('질문을 삭제했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');

    return Scaffold(
      appBar: AppBar(title: const Text('QnA 질문 및 답변 관리')),
      body: StreamBuilder<List<QnaItem>>(
        stream: _qnaService.streamAdminQuestions(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];

          final unreadCount = items.where((q) => !q.isReadByAdmin).length;
          final unansweredCount = items.where((q) => !q.isAnswered).length;

          final filtered = items.where((q) {
            if (_filterMode == 'unread') {
              return !q.isReadByAdmin || !q.isAnswered;
            }
            if (_filterMode == 'unanswered') {
              return !q.isAnswered;
            }
            return true;
          }).toList();

          return Scrollbar(
            thumbVisibility: true,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              children: [
                // 상태 상자
                Card(
                  color: unreadCount > 0
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          unreadCount > 0
                              ? Icons.mark_chat_unread
                              : Icons.check_circle,
                          color: unreadCount > 0 ? Colors.red : Colors.blue,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unreadCount > 0
                                    ? '🔴 신규/미답변 질문이 $unreadCount건 있습니다!'
                                    : '✅ 처리할 질문이 모두 완료되었습니다.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: unreadCount > 0
                                      ? Colors.red.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '전체 질문 ${items.length}건 중 미답변 $unansweredCount건',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 필터 선택
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: Text('미확인/미답변 ($unreadCount)'),
                                    selected: _filterMode == 'unread',
                                    onSelected: (_) =>
                                        setState(() => _filterMode = 'unread'),
                                  ),
                                  const SizedBox(width: 10),
                                  ChoiceChip(
                                    label: Text('미답변만 ($unansweredCount)'),
                                    selected: _filterMode == 'unanswered',
                                    onSelected: (_) => setState(
                                      () => _filterMode = 'unanswered',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ChoiceChip(
                                    label: Text('전체 (${items.length})'),
                                    selected: _filterMode == 'all',
                                    onSelected: (_) =>
                                        setState(() => _filterMode = 'all'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                if (filtered.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('해당 조건의 QnA 질문이 없습니다.')),
                    ),
                  )
                else
                  for (final item in filtered) ...[
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Icon(
                          item.isAnswered
                              ? Icons.check_circle_outline
                              : Icons.help_outline,
                          color: item.isAnswered ? Colors.green : Colors.red,
                          size: 28,
                        ),
                        title: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!item.isReadByAdmin) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              item.content.isEmpty ? item.title : item.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 6),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '작성자: ${item.authorName} · ${dateFormat.format(item.createdAt)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    item.isAnswered ? '답변 완료' : '답변 대기',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: item.isAnswered
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.edit_note_outlined),
                        onTap: () => _openAnswerDialog(item),
                      ),
                    ),
                  ],

                const SizedBox(height: 20),

                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.circle_notifications_outlined),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '💡 추가 실시간 Push 알림 안내 (FCM)',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '앱이 꺼져 있어도 새 질문을 받으려면 Firebase Cloud Messaging(FCM)과 '
                          'Cloud Functions가 연결되어 있어야 합니다. 연결되면 질문 등록 즉시 관리자 기기로 알림을 보냅니다.',
                          style: TextStyle(fontSize: 12.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
