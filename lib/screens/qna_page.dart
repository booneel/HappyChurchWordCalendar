import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/local_profile_service.dart';
import '../services/qna_service.dart';

class QnaPage extends StatefulWidget {
  const QnaPage({super.key});

  @override
  State<QnaPage> createState() => _QnaPageState();
}

class _QnaPageState extends State<QnaPage> {
  final QnaService _qnaService = QnaService();
  final LocalProfileService _profileService = LocalProfileService();

  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'faq', 'answered'

  Future<void> _openAskDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final name = await _profileService.getName() ?? '사용자';

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('QnA 질문하기'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: '질문 제목',
                  hintText: '궁금하신 내용을 한 줄로 요약해 주세요',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '질문 내용',
                  hintText: '자세한 내용을 입력해 주세요',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              final content = contentController.text.trim();

              if (title.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('질문 제목을 입력해 주세요.')),
                );
                return;
              }

              if (content.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('질문 내용을 입력해 주세요.')),
                );
                return;
              }

              Navigator.pop(context, true);
            },
            child: const Text('질문 등록'),
          ),
        ],
      ),
    );

    if (result == true) {
      final title = titleController.text.trim();
      final content = contentController.text.trim();

      await _qnaService.createQuestion(
        title: title,
        content: content,
        authorName: name,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('질문이 성공적으로 등록되었습니다.')));

      setState(() {});
    }
  }

  void _showQuestionDetail(QnaItem item) {
    final dateFormat = DateFormat('yyyy년 M월 d일 HH:mm', 'ko_KR');

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
              Text(
                item.content.isEmpty ? item.title : item.content,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              const Text(
                '💬 관리자 답변',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF4F7CAC),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: item.isAnswered
                      ? Colors.blue.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.isAnswered
                      ? item.answer!
                      : '아직 답변이 등록되지 않았습니다.\n잠시만 기다려 주세요.',
                  style: TextStyle(
                    fontSize: 14,
                    color: item.isAnswered ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd', 'ko_KR');

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<QnaItem>>(
              stream: _qnaService.streamQuestions(),
              builder: (context, snapshot) {
                final allItems = snapshot.data ?? [];

                // 필터링 적용
                final filtered = allItems.where((q) {
                  final matchesQuery = _searchQuery.isEmpty ||
                      q.title.contains(_searchQuery) ||
                      q.content.contains(_searchQuery);

                  if (!matchesQuery) return false;

                  if (_filterMode == 'answered') {
                    return q.isAnswered;
                  }
                  return true;
                }).toList();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    const Text(
                      'QnA',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '궁금한 점을 자유롭게 질문해 보세요.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (val) {
                        setState(() => _searchQuery = val.trim());
                      },
                      decoration: InputDecoration(
                        hintText: '궁금한 내용을 검색하세요',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('전체'),
                          selected: _filterMode == 'all',
                          onSelected: (_) =>
                              setState(() => _filterMode = 'all'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('답변 완료'),
                          selected: _filterMode == 'answered',
                          onSelected: (_) =>
                              setState(() => _filterMode = 'answered'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (filtered.isEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              Icon(
                                Icons.question_answer_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? '검색 결과와 일치하는 질문이 없습니다.'
                                    : '아직 등록된 QnA 질문이 없습니다.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '아래 "질문하기" 버튼을 눌러 궁금한 점을 질문해 보세요!',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      for (final item in filtered)
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: Icon(
                              item.isAnswered
                                  ? Icons.check_circle_outline
                                  : Icons.help_outline,
                              color: item.isAnswered
                                  ? Colors.green
                                  : const Color(0xFF4F7CAC),
                            ),
                            title: Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  dateFormat.format(item.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.isAnswered
                                        ? Colors.green.shade50
                                        : Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.isAnswered ? '답변 완료' : '답변 대기',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: item.isAnswered
                                          ? Colors.green.shade800
                                          : Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showQuestionDetail(item),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openAskDialog,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('질문하기'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
