import 'dart:async';

import 'package:flutter/material.dart';

import '../services/date_page_mapper.dart';
import '../services/pdf_catalog_service.dart';
import '../services/qna_service.dart';
import '../services/view_history_service.dart';

class AdminStatsPage extends StatefulWidget {
  const AdminStatsPage({super.key});

  @override
  State<AdminStatsPage> createState() => _AdminStatsPageState();
}

class _AdminStatsPageState extends State<AdminStatsPage> {
  final ViewHistoryService _historyService = ViewHistoryService.instance;
  final QnaService _qnaService = QnaService.instance;
  final PdfCatalogService _catalogService = PdfCatalogService.instance;

  bool _loading = true;
  List<PageViewStat> _topPages = [];
  int _totalQnaCount = 0;
  int _answeredQnaCount = 0;
  StreamSubscription<List<PageViewStat>>? _topPagesSubscription;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _topPagesSubscription =
        _historyService.streamTopPages(limit: 10).listen((top) {
      if (!mounted) return;
      setState(() => _topPages = top);
    });
  }

  @override
  void dispose() {
    _topPagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);

    try {
      final top = await _historyService.getTopPages(limit: 10);
      final qnaList = await _qnaService.getQuestions();

      final answered = qnaList.where((q) => q.isAnswered).length;

      if (!mounted) return;

      setState(() {
        _topPages = top;
        _totalQnaCount = qnaList.length;
        _answeredQnaCount = answered;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('방문 & 이용 통계'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _loadStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // 1. QnA 요약 정보 카드
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.question_answer,
                              color: Color(0xFF4F7CAC), size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'QnA 문의 현황',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '답변 완료 $_answeredQnaCount건 / 전체 $_totalQnaCount건',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4F7CAC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. 가장 많이 본 말씀 Top 10
                  Text(
                    '🔥 가장 많이 본 말씀 Top 10',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),

                  if (_topPages.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text('아직 집계된 말씀 조회 기록이 없습니다.'),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            for (int i = 0; i < _topPages.length; i++) ...[
                              Builder(builder: (context) {
                                final stat = _topPages[i];
                                DateTime date;
                                try {
                                  date = DatePageMapper.dateForPdfPage(
                                    stat.page,
                                    year: today.year,
                                  );
                                } catch (_) {
                                  date = today;
                                }

                                final rankEmojis = ['🥇', '🥈', '🥉'];
                                final rankStr =
                                    i < 3 ? rankEmojis[i] : '${i + 1}위';
                                final title =
                                    _catalogService.formatTitleForDate(date);

                                final maxViews = _topPages.first.views > 0
                                    ? _topPages.first.views
                                    : 1;
                                final ratio =
                                    (stat.views / maxViews).clamp(0.05, 1.0);

                                return ListTile(
                                  leading: SizedBox(
                                    width: 38,
                                    child: Text(
                                      rankStr,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      color: const Color(0xFF4F7CAC),
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                  ),
                                  trailing: Text(
                                    '${stat.views}회',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              }),
                              if (i < _topPages.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
