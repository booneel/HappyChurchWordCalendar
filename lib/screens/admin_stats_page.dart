import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bookmark_service.dart';
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
  final BookmarkService _bookmarkService = BookmarkService.instance;
  final QnaService _qnaService = QnaService.instance;
  final PdfCatalogService _catalogService = PdfCatalogService.instance;

  bool _loading = true;
  String _statMode = 'bookmarks'; // 'bookmarks' or 'views'

  List<PageViewStat> _topBookmarks = [];
  List<PageViewStat> _topViews = [];

  int _totalQnaCount = 0;
  int _answeredQnaCount = 0;

  StreamSubscription<List<PageViewStat>>? _viewsSubscription;
  StreamSubscription<List<PageViewStat>>? _bookmarksSubscription;

  @override
  void initState() {
    super.initState();
    _loadStats();

    _viewsSubscription =
        _historyService.streamTopPages(limit: 10).listen((top) {
      if (!mounted) return;
      setState(() => _topViews = top);
    });

    _bookmarksSubscription =
        _bookmarkService.streamTopBookmarkedPages(limit: 10).listen((top) {
      if (!mounted) return;
      setState(() => _topBookmarks = top);
    });
  }

  @override
  void dispose() {
    _viewsSubscription?.cancel();
    _bookmarksSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);

    try {
      final views = await _historyService.getTopPages(limit: 10);
      final bookmarks = await _bookmarkService.getTopBookmarkedPages(limit: 10);
      final qnaList = await _qnaService.getQuestions();

      final answered = qnaList.where((q) => q.isAnswered).length;

      if (!mounted) return;

      setState(() {
        _topViews = views;
        _topBookmarks = bookmarks;
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
    final activeList = _statMode == 'bookmarks' ? _topBookmarks : _topViews;

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
                          const Icon(
                            Icons.question_answer,
                            color: Color(0xFF4F7CAC),
                            size: 28,
                          ),
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

                  // 2. 통계 선택 모드 (즐겨찾기순 vs 직접 조회수순)
                  Row(
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                        label: const Text('즐겨찾기순 Top 10'),
                        selected: _statMode == 'bookmarks',
                        onSelected: (_) => setState(() => _statMode = 'bookmarks'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: const Icon(Icons.touch_app, size: 16),
                        label: const Text('직접 조회수순 Top 10'),
                        selected: _statMode == 'views',
                        onSelected: (_) => setState(() => _statMode = 'views'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Text(
                    _statMode == 'bookmarks'
                        ? '⭐ 말씀 즐겨찾기 수 Top 10'
                        : '👁️ 말씀 직접 조회수 Top 10',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),

                  if (activeList.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            _statMode == 'bookmarks'
                                ? '아직 집계된 말씀 즐겨찾기 기록이 없습니다.'
                                : '아직 집계된 말씀 직접 조회 기록이 없습니다.',
                          ),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            for (int i = 0; i < activeList.length; i++) ...[
                              Builder(builder: (context) {
                                final stat = activeList[i];
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

                                final maxCount = activeList.first.views > 0
                                    ? activeList.first.views
                                    : 1;
                                final ratio =
                                    (stat.views / maxCount).clamp(0.05, 1.0);

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
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      color: _statMode == 'bookmarks'
                                          ? Colors.amber.shade700
                                          : const Color(0xFF4F7CAC),
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                  ),
                                  trailing: SizedBox(
                                    width: 68,
                                    child: Text(
                                      _statMode == 'bookmarks'
                                          ? '${stat.views}회 ⭐'
                                          : '${stat.views}회 👁️',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: _statMode == 'bookmarks'
                                            ? Colors.amber.shade900
                                            : null,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              if (i < activeList.length - 1)
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
