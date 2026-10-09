import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'app_shell.dart';
import 'bookmark_list_page.dart';
import 'pdf_page.dart';
import '../services/bookmark_service.dart';
import '../services/date_page_mapper.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_catalog_service.dart';
import '../services/view_history_service.dart';

class _HomeData {
  final List<PageViewStat> topPages;
  final List<BookmarkItem> bookmarks;

  const _HomeData({required this.topPages, required this.bookmarks});
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
  final ViewHistoryService history = ViewHistoryService.instance;
  final BookmarkService bookmarkService = BookmarkService.instance;
  final PdfCatalogService catalogService = PdfCatalogService.instance;

  late Future<_HomeData> dataFuture;
  bool _titlesLoaded = false;
  late Future<File> _pdfFuture;

  @override
  void initState() {
    super.initState();
    dataFuture = _loadData();
    _pdfFuture = PdfCacheService().getCachedPdf();

    unawaited(_preloadAssets());
  }

  Future<void> _preloadAssets() async {
    try {
      await PdfCacheService().preload();
    } catch (error, stackTrace) {
      debugPrint('PDF preload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      await catalogService.loadTitles();
      if (mounted) setState(() => _titlesLoaded = true);
    } catch (error, stackTrace) {
      debugPrint('PDF title loading failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<_HomeData> _loadData() async {
    final results = await Future.wait([
      bookmarkService.getTopBookmarkedPages(limit: 3),
      bookmarkService.getBookmarks(),
    ]);

    return _HomeData(
      topPages: results[0] as List<PageViewStat>,
      bookmarks: (results[1] as List<BookmarkItem>).take(3).toList(),
    );
  }

  Future<void> _refresh() async {
    final next = _loadData();
    if (!mounted) return;
    setState(() {
      dataFuture = next;
      _pdfFuture = PdfCacheService().getCachedPdf(forceRefresh: true);
    });
    await next;
  }

  bool _isOpening = false;

  Future<void> _openPdf({required int page, required DateTime date}) async {
    if (_isOpening) return;
    _isOpening = true;

    try {
      if (!DatePageMapper.isDailyPage(page)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('해당 날짜에 연결된 PDF 페이지가 없습니다.')),
          );
        }
        return;
      }

      // 직접 눌러서 들어간 경우에만 조회수 +1.
      await history.recordDirectOpen(page: page, date: date);

      final title = catalogService.formatTitleForDate(date);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPage(title: title, page: page, year: date.year),
        ),
      );

      if (!mounted) return;
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayPage = DatePageMapper.pdfPageForDateOrNull(today);
    final todayTitle = todayPage == null
        ? '오늘 날짜에 PDF 페이지가 없습니다'
        : _titlesLoaded
            ? catalogService.formatTitleForDate(today)
            : '${today.year}년 ${today.month}월 ${today.day}일';
    final todayDateText = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(today);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_HomeData>(
          future: dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;

            DateTime? dateForPage(int page) {
              try {
                return DatePageMapper.dateForPdfPage(page, year: today.year);
              } catch (_) {
                return null;
              }
            }

            final topPages = data == null
                ? <PageViewStat>[]
                : data.topPages
                    .where((item) => dateForPage(item.page) != null)
                    .toList();
            final bookmarkItems = data == null ? <BookmarkItem>[] : data.bookmarks;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Header(
                  displayName: widget.displayName,
                  onSettings: widget.onSettings,
                ),
                const SizedBox(height: 22),
                if (widget.adminMode) ...[
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
                        Icon(Icons.admin_panel_settings_outlined, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('관리자 모드가 활성화되어 있습니다.', softWrap: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  '오늘의 말씀',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: todayPage == null
                        ? null
                        : () => _openPdf(page: todayPage, date: today),
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
                                child: const Icon(Icons.menu_book_outlined),
                              ),
                              const Spacer(),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            todayTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            todayDateText,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _TodayPdfPreview(
                            pdfFuture: _pdfFuture,
                            page: todayPage,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: todayPage == null
                                  ? null
                                  : () =>
                                      _openPdf(page: todayPage, date: today),
                              icon: const Icon(Icons.menu_book_outlined),
                              label: Text(
                                todayPage == null ? '오늘 말씀 PDF 없음' : '오늘 말씀 보기',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '🔥 많이 본 말씀 Top 3 (즐겨찾기순)',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
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
                else if (topPages.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('아직 즐겨찾기 등록된 말씀이 없습니다.'),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < topPages.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _TopWordCard(
                            rank: ['🥇', '🥈', '🥉'][i],
                            date: dateForPage(topPages[i].page)!,
                            views: topPages[i].views,
                            onTap: () => _openPdf(
                              page: topPages[i].page,
                              date: dateForPage(topPages[i].page)!,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '⭐ 즐겨찾기 한 말씀',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BookmarkListPage(),
                          ),
                        );
                        _refresh();
                      },
                      child: const Text('전체보기'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (bookmarkItems.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('아직 즐겨찾기 한 말씀이 없습니다. PDF에서 ⭐ 버튼을 눌러보세요!'),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final item in bookmarkItems)
                          _BookmarkWordRow(
                            item: item,
                            onTap: () =>
                                _openPdf(page: item.page, date: item.date),
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

class _TodayPdfPreview extends StatelessWidget {
  final Future<File> pdfFuture;
  final int? page;

  const _TodayPdfPreview({required this.pdfFuture, required this.page});

  @override
  Widget build(BuildContext context) {
    if (page == null) {
      return _previewFrame(
        const Center(
          child: Text('오늘 날짜에 연결된 PDF 페이지가 없습니다.', textAlign: TextAlign.center),
        ),
      );
    }

    return FutureBuilder<File>(
      future: pdfFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _previewFrame(
            const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _previewFrame(
            const Center(
              child: Text(
                '오늘 말씀 미리보기를 준비하지 못했습니다.\n눌러서 PDF를 열어보세요.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 300,
            child: IgnorePointer(
              child: pdfrx.PdfViewer.file(
                snapshot.data!.path,
                initialPageNumber: page!,
                params: const pdfrx.PdfViewerParams(
                  pageAnchor: pdfrx.PdfPageAnchor.top,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _previewFrame(Widget child) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
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
    final title = PdfCatalogService.instance.formatTitleForDate(date);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(rank, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '⭐ $views회 즐겨찾기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkWordRow extends StatelessWidget {
  final BookmarkItem item;
  final VoidCallback onTap;

  const _BookmarkWordRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = PdfCatalogService.instance.formatTitleForDate(item.date);
    final dateText = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(item.date);

    return ListTile(
      leading: const Icon(Icons.star, color: Colors.amber),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(dateText),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
