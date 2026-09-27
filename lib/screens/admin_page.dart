import 'package:flutter/material.dart';

import '../services/admin_service.dart';
import '../services/local_profile_service.dart';
import '../services/qna_service.dart';
import 'admin_page_settings_page.dart';
import 'admin_pdf_page.dart';
import 'admin_qna_page.dart';
import 'admin_stats_page.dart';
import 'admin_title_catalog_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final AdminService _adminService = AdminService.instance;
  final LocalProfileService _profileService = LocalProfileService();
  final QnaService _qnaService = QnaService.instance;

  @override
  void initState() {
    super.initState();
    _checkUnreadQnaNotification();
  }

  Future<void> _checkUnreadQnaNotification() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final unreadCount = await _qnaService.getUnreadQuestionCount();
      if (unreadCount > 0 && mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '신규 QnA 질문 ($unreadCount건)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Text(
              '사용자가 새로 등록한 QnA 질문이 $unreadCount건 있습니다.\n'
              '지금 바로 질문 내용을 확인하고 답변을 작성해보세요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('나중에'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminQnaPage()),
                  );
                },
                child: const Text('QnA 답변 작성'),
              ),
            ],
          ),
        );
      }
    });
  }

  Future<void> _confirmAdminExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Center(child: Text('관리자 종료')),
        content: const Text('관리자 모드를 종료하시겠습니까?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('종료'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _adminService.signOut();
      await _profileService.setAdminMode(false);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 센터'),
        actions: [
          IconButton(
            tooltip: '관리자 종료',
            onPressed: _confirmAdminExit,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const Text(
            '관리자 기능 선택',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'PDF 교체, 날짜 매핑, 말씀 제목 및 QnA 질문/답변을 관리합니다.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          _AdminCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF 관리',
            subtitle: '현재 PDF 확인 · 새 PDF 업로드 및 교체',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPdfPage()),
              );
            },
          ),
          _AdminCard(
            icon: Icons.calendar_month_outlined,
            title: '날짜 / 페이지 관리',
            subtitle: '날짜와 PDF 시작 페이지 매핑 설정',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminPageSettingsPage(),
                ),
              );
            },
          ),
          _AdminCard(
            icon: Icons.list_alt_outlined,
            title: '말씀 제목 카탈로그 관리',
            subtitle: '365일 말씀 제목 수동 입력 및 PDF 자동 추출',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminTitleCatalogPage(),
                ),
              );
            },
          ),
          StreamBuilder<int>(
            stream: _qnaService.streamUnreadCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;

              return _AdminCard(
                icon: Icons.question_answer_outlined,
                title: 'QnA 질문 및 답변 관리',
                subtitle: unreadCount > 0
                    ? '🔴 미확인 질문 $unreadCount건 도착!'
                    : '사용자 질문 확인 및 공식 답변 작성',
                badgeCount: unreadCount,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminQnaPage()),
                  );
                },
              );
            },
          ),
          _AdminCard(
            icon: Icons.bar_chart_outlined,
            title: '방문 & 이용 통계',
            subtitle: '말씀 직접 클릭 조회수 · 많이 본 말씀 순위',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminStatsPage()),
              );
            },
          ),
          const SizedBox(height: 14),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PDF 교체, 날짜 매핑 및 QnA 질문 답변 등록 시 '
                      '사용자 화면에 실시간으로 반영됩니다.',
                      style: TextStyle(fontSize: 13),
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
}

class _AdminCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int badgeCount;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF4F7CAC)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (badgeCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: badgeCount > 0 ? Colors.red.shade800 : null,
            fontWeight: badgeCount > 0 ? FontWeight.w600 : null,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
