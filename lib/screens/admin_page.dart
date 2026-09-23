import 'package:flutter/material.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const Text(
            '관리자 센터',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'PDF와 앱 콘텐츠를 관리합니다.',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 20),

          _AdminCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF 관리',
            subtitle: '현재 PDF 확인 · PDF 교체',
            onTap: () => _comingSoon(
              context,
              'PDF 관리',
            ),
          ),

          _AdminCard(
            icon: Icons.calendar_month_outlined,
            title: '날짜 / 페이지 관리',
            subtitle: '날짜와 PDF 페이지 연결 확인 · 수정',
            onTap: () => _comingSoon(
              context,
              '날짜 / 페이지 관리',
            ),
          ),

          _AdminCard(
            icon: Icons.bar_chart_outlined,
            title: '방문 통계',
            subtitle: '직접 클릭 조회수 · 많이 본 말씀',
            onTap: () => _comingSoon(
              context,
              '방문 통계',
            ),
          ),

          _AdminCard(
            icon: Icons.history_outlined,
            title: '최근 이용 기록',
            subtitle: '최근 직접 열어본 말씀 기록 확인',
            onTap: () => _comingSoon(
              context,
              '최근 이용 기록',
            ),
          ),

          _AdminCard(
            icon: Icons.question_answer_outlined,
            title: 'QnA 관리',
            subtitle: 'FAQ 작성 · 질문 답변',
            onTap: () => _comingSoon(
              context,
              'QnA 관리',
            ),
          ),

          const SizedBox(height: 14),

          Card(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '현재 버전에서는 말씀 제목을 자동 추출하지 않습니다. '
                      '사용자 화면에는 "오늘의 말씀", "말씀"과 날짜만 표시합니다. '
                      '조회수는 사용자가 말씀을 직접 눌러 PDF에 들어간 경우에만 집계합니다.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _comingSoon(
    BuildContext context,
    String title,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title 기능은 추후 활성화됩니다.',
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 8,
        ),
        leading: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(
          Icons.chevron_right,
        ),
        onTap: onTap,
      ),
    );
  }
}
