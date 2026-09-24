import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../services/pdf_cache_service.dart';

class PdfPage extends StatefulWidget {
  final String title;
  final int page;

  const PdfPage({super.key, required this.title, required this.page});

  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  static const int fallbackTotalPages = 368;

  final PdfCacheService cache = PdfCacheService();
  late int page;
  late Future<File> pdfFuture;

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, fallbackTotalPages);
    pdfFuture = cache.getCachedPdf();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          widget.title,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
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
            onPageChanged: (newPage) {
              if (mounted && page != newPage) {
                setState(() => page = newPage);
              }
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
  final ValueChanged<int> onPageChanged;

  const _SinglePagePdfViewer({
    required this.file,
    required this.initialPage,
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
    } catch (_) {
      // The FutureBuilder already reports a document open error.
    }
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
            scrollDirection: Axis.horizontal,
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
          boundaryMargin: const EdgeInsets.all(48),
          clipBehavior: Clip.none,
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
