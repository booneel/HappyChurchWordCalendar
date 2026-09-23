import 'package:flutter/material.dart';

class QnaPage extends StatelessWidget {
  QnaPage({super.key});

  final questions = const [
    ('PDF는 언제 업데이트되나요?', '2026.09.20 · 조회 34'),
    ('특정 페이지를 바로 볼 수 있나요?', '2026.09.19 · 조회 28'),
    ('일정이 변경됐어요. 어떻게 하나요?', '2026.09.18 · 조회 21'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('QnA', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: '궁금한 내용을 검색하세요',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: () {}, icon: const Icon(Icons.tune_outlined)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ChoiceChip(label: const Text('전체'), selected: true, onSelected: (_) {}),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('자주 묻는 질문'), selected: false, onSelected: (_) {}),
            ],
          ),
          const SizedBox(height: 12),
          ...questions.map(
            (q) => Card(
              child: ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(q.$1),
                subtitle: Text(q.$2),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit_outlined),
            label: const Text('질문하기'),
          ),
        ],
      ),
    );
  }
}
