import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_cache_service.dart';

class PdfPage extends StatefulWidget {
  final String title;
  final int page;

  const PdfPage({
    super.key,
    required this.title,
    required this.page,
  });

  @override
  State<PdfPage> createState() =>
      _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  static const int totalPages = 368;

  final PdfCacheService cache =
      PdfCacheService();

  final PdfViewerController controller =
      PdfViewerController();

  late int page;
  late Future<File> pdfFuture;

  @override
  void initState() {
    super.initState();

    page = widget.page.clamp(
      1,
      totalPages,
    );

    pdfFuture =
        cache.getCachedPdf();
  }

  Future<void> _goToPage(
    int targetPage,
  ) async {
    final target =
        targetPage.clamp(
      1,
      totalPages,
    );

    setState(() {
      page = target;
    });

    if (controller.isReady) {
      await controller.goToPage(
        pageNumber: target,
        anchor:
            PdfPageAnchor.top,
      );
    }

    // 중요:
    // 여기서는 조회수를 기록하지 않습니다.
    // 이전/다음 버튼이나 PDF 내부 스크롤은 "직접 콘텐츠 진입" 통계가 아닙니다.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<File>(
              future: pdfFuture,
              builder:
                  (context, snapshot) {
                if (snapshot
                        .connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError ||
                    snapshot.data == null) {
                  return Center(
                    child: Text(
                      'PDF를 불러오지 못했습니다.\n'
                      '${snapshot.error ?? ''}',
                      textAlign:
                          TextAlign.center,
                    ),
                  );
                }

                return PdfViewer.file(
                  snapshot.data!.path,
                  controller:
                      controller,
                  initialPageNumber:
                      page,
                  params:
                      PdfViewerParams(
                    pageAnchor:
                        PdfPageAnchor.top,

                    // 손가락 스크롤로 다른 페이지에 가더라도
                    // 화면의 현재 페이지 표시만 바꿉니다.
                    // 조회수는 절대 올리지 않습니다.
                    onPageChanged:
                        (pageNumber) {
                      if (!mounted ||
                          pageNumber ==
                              null) {
                        return;
                      }

                      if (page ==
                          pageNumber) {
                        return;
                      }

                      setState(() {
                        page =
                            pageNumber;
                      });
                    },
                  ),
                );
              },
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                12,
                8,
                12,
                12,
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: page > 1
                        ? () =>
                            _goToPage(
                              page - 1,
                            )
                        : null,
                    icon:
                        const Icon(
                      Icons.chevron_left,
                    ),
                    label:
                        const Text(
                      '이전',
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$page / $totalPages',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed:
                        page <
                                totalPages
                            ? () =>
                                _goToPage(
                                  page + 1,
                                )
                            : null,
                    icon:
                        const Icon(
                      Icons
                          .chevron_right,
                    ),
                    label:
                        const Text(
                      '다음',
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
