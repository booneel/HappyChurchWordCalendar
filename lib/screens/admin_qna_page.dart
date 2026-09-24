import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

    // 읽음 처리
    _qnaService.markAsReadByAdmin(item.id);

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '작성자: ${item.authorName}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat.format(item.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
              TextField(
                controller: answerController,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: '답변 내용을 입력하세요...',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final text = answerController.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('답변 내용을 입력해 주세요.')),
                );
                return;
              }

              await _qnaService.answerQuestion(
                questionId: item.id,
                answer: text,
              );

              if (!mounted) return;
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('답변이 등록되었습니다.')),
              );
            },
            child: const Text('답변 저장'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('QnA 질문 및 답변 관리'),
      ),
      body: StreamBuilder<List<QnaItem>>(
        stream: _qnaService.streamQuestions(),
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

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 상태 상자
              Card(
                color: unreadCount > 0 ? Colors.red.shade50 : Colors.blue.shade50,
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
              Row(
                children: [
                  ChoiceChip(
                    label: Text('미확인/미답변 ($unreadCount)'),
                    selected: _filterMode == 'unread',
                    onSelected: (_) => setState(() => _filterMode = 'unread'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('미답변만 ($unansweredCount)'),
                    selected: _filterMode == 'unanswered',
                    onSelected: (_) => setState(() => _filterMode = 'unanswered'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('전체 (${items.length})'),
                    selected: _filterMode == 'all',
                    onSelected: (_) => setState(() => _filterMode = 'all'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (filtered.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: Text('해당 조건의 QnA 질문이 없습니다.'),
                    ),
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
                      title: Row(
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
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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
                          Row(
                            children: [
                              Text(
                                '작성자: ${item.authorName} · ${dateFormat.format(item.createdAt)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                item.isAnswered ? '답변 완료' : '답변 대기',
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
                          Text(
                            '💡 추가 실시간 Push 알림 안내 (FCM)',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '앱이 켜져 있지 않을 때도 실시간 기기 푸시 알림을 받으시려면 '
                        'Firebase Cloud Messaging (FCM) 및 Firebase Cloud Functions를 연결하면 '
                        '사용자가 질문을 등록하자마자 관리자 기기로 푸시 알림이 전송됩니다.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
