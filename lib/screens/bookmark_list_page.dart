import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bookmark_service.dart';
import '../services/pdf_catalog_service.dart';
import 'pdf_page.dart';

class BookmarkListPage extends StatefulWidget {
  const BookmarkListPage({super.key});

  @override
  State<BookmarkListPage> createState() => _BookmarkListPageState();
}

class _BookmarkListPageState extends State<BookmarkListPage> {
  final BookmarkService _bookmarkService = BookmarkService.instance;
  final PdfCatalogService _catalogService = PdfCatalogService.instance;

  Future<void> _openPdf(BookmarkItem item) async {
    final title = _catalogService.formatTitleForDate(item.date);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPage(
          title: title,
          page: item.page,
          year: item.date.year,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('즐겨찾기 한 말씀'),
      ),
      body: StreamBuilder<List<BookmarkItem>>(
        stream: _bookmarkService.streamBookmarks(),
        builder: (context, snapshot) {
          final bookmarks = snapshot.data ?? [];

          if (snapshot.connectionState == ConnectionState.waiting &&
              bookmarks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (bookmarks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_outline, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    '아직 즐겨찾기 한 말씀이 없습니다.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'PDF 말씀 보기 화면에서 상단 별(⭐) 버튼을 눌러 추가하세요!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookmarks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = bookmarks[index];
              final title = _catalogService.formatTitleForDate(item.date);

              return ListTile(
                leading: const Icon(
                  Icons.star,
                  color: Colors.amber,
                  size: 28,
                ),
                title: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${dateFormat.format(item.date)} · PDF ${item.page}페이지',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: IconButton(
                  tooltip: '즐겨찾기 해제',
                  icon: const Icon(Icons.star, color: Colors.amber),
                  onPressed: () async {
                    await _bookmarkService.toggleBookmark(
                      page: item.page,
                      date: item.date,
                    );
                    if (mounted) setState(() {});
                  },
                ),
                onTap: () => _openPdf(item),
              );
            },
          );
        },
      ),
    );
  }
}
