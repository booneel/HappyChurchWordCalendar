import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../services/bookmark_service.dart';
import '../services/date_page_mapper.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_catalog_service.dart';

class PdfPage extends StatefulWidget {
  final String title;
  final int page;
  final int? year;

  const PdfPage({
    super.key,
    required this.title,
    required this.page,
    this.year,
  });

  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  static const int fallbackTotalPages = 10000;

  final PdfCacheService cache = PdfCacheService();
  final BookmarkService bookmarkService = BookmarkService.instance;
  final PdfCatalogService catalog = PdfCatalogService.instance;

  late int page;
  late Future<File> pdfFuture;
  late String title;
  Axis _scrollDirection = Axis.horizontal;

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, fallbackTotalPages);
    title = widget.title;
    pdfFuture = cache.getCachedPdf();
    _refreshTitleForPage(page);
  }

  String? _titleForPage(int pdfPage) {
    if (!DatePageMapper.isDailyPage(pdfPage)) return null;

    try {
      final date = DatePageMapper.dateForPdfPage(
        pdfPage,
        year: widget.year ?? DateTime.now().year,
      );
      return catalog.formatTitleForDate(date);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshTitleForPage(int pdfPage) async {
    final immediateTitle = _titleForPage(pdfPage);
    if (mounted && page == pdfPage && immediateTitle != null) {
      setState(() => title = immediateTitle);
    }

    try {
      await catalog.loadTitles();
      final loadedTitle = _titleForPage(pdfPage);
      if (mounted && page == pdfPage && loadedTitle != null) {
        setState(() => title = loadedTitle);
      }
    } catch (_) {}
  }

  Widget _buildBookmarkButton() {
    final isBookmarked = bookmarkService.isBookmarkedSync(page);

    return IconButton(
      tooltip: isBookmarked ? '즐겨찾기 해제' : '즐겨찾기 추가',
      onPressed: () async {
        DateTime pageDate;
        try {
          pageDate = DatePageMapper.dateForPdfPage(
            page,
            year: widget.year ?? DateTime.now().year,
          );
        } catch (_) {
          pageDate = DateTime.now();
        }

        final isAdded = await bookmarkService.toggleBookmark(
          page: page,
          date: pageDate,
        );

        if (!mounted) return;
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAdded ? '⭐ 즐겨찾기에 추가되었습니다.' : '즐겨찾기에서 해제되었습니다.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      icon: Icon(
        isBookmarked ? Icons.star : Icons.star_border,
        color: isBookmarked ? Colors.amber : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          title,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          _buildBookmarkButton(),
          IconButton(
            tooltip: _scrollDirection == Axis.horizontal
                ? '현재 방향: 좌우 스크롤 (누르면 위아래로 변경)'
                : '현재 방향: 위아래 스크롤 (누르면 좌우로 변경)',
            onPressed: () {
              final newDirection = _scrollDirection == Axis.horizontal
                  ? Axis.vertical
                  : Axis.horizontal;
              setState(() {
                _scrollDirection = newDirection;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    newDirection == Axis.horizontal
                        ? '↔ 좌우 스크롤 모드로 변경되었습니다.'
                        : '↕ 위아래 스크롤 모드로 변경되었습니다.',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            icon: Icon(
              _scrollDirection == Axis.horizontal
                  ? Icons.swap_horiz
                  : Icons.swap_vert,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$page',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<File>(
        future: pdfFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Text(
                'PDF를 불러오지 못했습니다.\n${snapshot.error ?? ''}',
                textAlign: TextAlign.center,
              ),
            );
          }

          return _SinglePagePdfViewer(
            file: snapshot.data!,
            initialPage: page,
            scrollDirection: _scrollDirection,
            onPageChanged: (newPage) {
              if (!mounted || page == newPage) return;

              final nextTitle = _titleForPage(newPage);
              setState(() {
                page = newPage;
                if (nextTitle != null) title = nextTitle;
              });
              _refreshTitleForPage(newPage);
            },
          );
        },
      ),
    );
  }
}

class _SinglePagePdfViewer extends StatefulWidget {
  final File file;
  final int initialPage;
  final Axis scrollDirection;
  final ValueChanged<int> onPageChanged;

  const _SinglePagePdfViewer({
    required this.file,
    required this.initialPage,
    required this.scrollDirection,
    required this.onPageChanged,
  });

  @override
  State<_SinglePagePdfViewer> createState() => _SinglePagePdfViewerState();
}

class _SinglePagePdfViewerState extends State<_SinglePagePdfViewer> {
  late final Future<pdfrx.PdfDocument> _documentFuture;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _documentFuture = pdfrx.PdfDocument.openFile(widget.file.path);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    unawaited(_disposeDocument());
    super.dispose();
  }

  Future<void> _disposeDocument() async {
    try {
      final document = await _documentFuture;
      await document.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<pdfrx.PdfDocument>(
      future: _documentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Text(
              'PDF 페이지를 표시하지 못했습니다.\n${snapshot.error ?? ''}',
              textAlign: TextAlign.center,
            ),
          );
        }

        final document = snapshot.data!;
        if (document.pages.isEmpty) {
          return const Center(child: Text('PDF에 페이지가 없습니다.'));
        }

        final initialIndex = (widget.initialPage - 1).clamp(
          0,
          document.pages.length - 1,
        );
        _pageController ??= PageController(initialPage: initialIndex);

        return Container(
          color: const Color(0xff202124),
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(), // 다음/이전 말씀 페이지 스와이프 이동 허용
            scrollDirection: widget.scrollDirection,
            itemCount: document.pages.length,
            onPageChanged: (index) => widget.onPageChanged(index + 1),
            itemBuilder: (context, index) {
              return _SinglePdfPageImage(page: document.pages[index]);
            },
          ),
        );
      },
    );
  }
}

class _SinglePdfPageImage extends StatefulWidget {
  final pdfrx.PdfPage page;

  const _SinglePdfPageImage({required this.page});

  @override
  State<_SinglePdfPageImage> createState() => _SinglePdfPageImageState();
}

class _SinglePdfPageImageState extends State<_SinglePdfPageImage> {
  late final Future<ui.Image> _imageFuture;
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _imageFuture = _renderPage();
  }

  Future<ui.Image> _renderPage() async {
    final width = (widget.page.width * 2.5).round();
    final height = (widget.page.height * 2.5).round();
    final rendered = await widget.page.render(
      x: 0,
      y: 0,
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xffffffff,
    );
    if (rendered == null) {
      throw StateError('PDF page render returned no image.');
    }
    final image = await rendered.createImage();
    rendered.dispose();
    if (!mounted) {
      image.dispose();
      throw StateError('PDF page viewer was disposed while rendering.');
    }
    _image = image;
    return image;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Text(
              '페이지를 표시하지 못했습니다.\n${snapshot.error ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          );
        }

        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          boundaryMargin: EdgeInsets.zero, // 위치 치우침 방지 (중앙 정렬 고정)
          clipBehavior: Clip.hardEdge,
          child: Center(
            child: RawImage(
              image: snapshot.data,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        );
      },
    );
  }
}
