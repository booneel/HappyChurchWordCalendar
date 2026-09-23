import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_shell.dart';
import 'pdf_page.dart';
import '../services/date_page_mapper.dart';
import '../services/pdf_cache_service.dart';
import '../services/view_history_service.dart';

class _HomeData {
  final List<PageViewStat> topPages;
  final List<RecentDirectOpen> recent;

  const _HomeData({
    required this.topPages,
    required this.recent,
  });
}

class HomePage extends StatefulWidget {
  final String displayName;
  final bool adminMode;
  final VoidCallback onSettings;

  const HomePage({
    super.key,
    required this.displayName,
    required this.adminMode,
    required this.onSettings,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ViewHistoryService history = ViewHistoryService();

  late Future<_HomeData> dataFuture;

  @override
  void initState() {
    super.initState();
    dataFuture = _loadData();

    // PDF는 홈을 보는 동안 백그라운드에서 미리 준비합니다.
    PdfCacheService().preload();
  }

  Future<_HomeData> _loadData() async {
    final results = await Future.wait([
      history.getTopPages(limit: 3),
      history.getRecent(limit: 6),
    ]);

    return _HomeData(
      topPages: results[0] as List<PageViewStat>,
      recent: results[1] as List<RecentDirectOpen>,
    );
  }

  Future<void> _refresh() async {
    final next = _loadData();
    setState(() => dataFuture = next);
    await next;
  }

  Future<void> _openPdf({
    required int page,
    required DateTime date,
  }) async {
    // 직접 눌러서 들어간 경우에만 조회수 +1.
    unawaited(
      history.recordDirectOpen(
        page: page,
        date: date,
      ),
    );

    final dateText =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(date);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPage(
          title: '$dateText · 오늘의 말씀',
          page: page,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayPage = DatePageMapper.pdfPageForDate(today);
    final todayDateText =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(today);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_HomeData>(
          future: dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;

            DateTime dateForPage(int page) {
              return DatePageMapper.dateForPdfPage(
                page,
                year: today.year,
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Header(
                  displayName: widget.displayName,
                  onSettings: widget.onSettings,
                ),
                const SizedBox(height: 22),

                if (widget.adminMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text('관리자 모드가 활성화되어 있습니다.'),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                Text(
                  '오늘의 말씀',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),

                const SizedBox(height: 10),

                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openPdf(
                      page: todayPage,
                      date: today,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.menu_book_outlined,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.chevron_right),
                            ],
                          ),

                          const SizedBox(height: 18),

                          Text(
                            todayDateText,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            '오늘의 말씀을 확인해보세요.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _openPdf(
                                page: todayPage,
                                date: today,
                              ),
                              icon: const Icon(Icons.menu_book_outlined),
                              label: const Text('오늘 말씀 보기'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  '🔥 많이 본 말씀',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),

                const SizedBox(height: 10),

                if (snapshot.connectionState == ConnectionState.waiting &&
                    data == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (data?.topPages.isEmpty ?? true)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        '아직 직접 열어본 말씀 조회 기록이 없습니다.',
                      ),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < data!.topPages.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _TopWordCard(
                            rank: ['🥇', '🥈', '🥉'][i],
                            date: dateForPage(
                              data.topPages[i].page,
                            ),
                            views: data.topPages[i].views,
                            onTap: () => _openPdf(
                              page: data.topPages[i].page,
                              date: dateForPage(
                                data.topPages[i].page,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                const SizedBox(height: 24),

                Text(
                  '🕘 최근 본 말씀',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),

                const SizedBox(height: 10),

                if (data?.recent.isEmpty ?? true)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        '아직 직접 열어본 말씀이 없습니다.',
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final item in data!.recent)
                          _RecentWordRow(
                            date: item.date,
                            onTap: () => _openPdf(
                              page: item.page,
                              date: item.date,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopWordCard extends StatelessWidget {
  final String rank;
  final DateTime date;
  final int views;
  final VoidCallback onTap;

  const _TopWordCard({
    required this.rank,
    required this.date,
    required this.views,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat('M월 d일', 'ko_KR').format(date);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                rank,
                style: const TextStyle(fontSize: 23),
              ),
              const SizedBox(height: 6),
              const Text(
                '말씀',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                dateText,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$views회',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentWordRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _RecentWordRow({
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(date);

    return ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: const Text(
        '오늘의 말씀',
        style: TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(dateText),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
