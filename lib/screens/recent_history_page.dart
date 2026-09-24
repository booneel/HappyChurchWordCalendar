import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/pdf_catalog_service.dart';
import '../services/view_history_service.dart';
import 'pdf_page.dart';

class RecentHistoryPage extends StatefulWidget {
  const RecentHistoryPage({super.key});

  @override
  State<RecentHistoryPage> createState() => _RecentHistoryPageState();
}

class _RecentHistoryPageState extends State<RecentHistoryPage> {
  final ViewHistoryService _historyService = ViewHistoryService();
  final PdfCatalogService _catalogService = PdfCatalogService();

  bool _loading = true;
  List<RecentDirectOpen> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final list = await _historyService.getRecent(limit: 100);
    if (!mounted) return;
    setState(() {
      _history = list;
      _loading = false;
    });
  }

  Future<void> _openPdf(RecentDirectOpen item) async {
    await _historyService.recordDirectOpen(
      page: item.page,
      date: item.date,
    );

    if (!mounted) return;

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
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('최근 이용 기록'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _loadHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Text('아직 직접 열람한 말씀 기록이 없습니다.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    final title = _catalogService.formatTitleForDate(item.date);

                    return ListTile(
                      leading: const Icon(
                        Icons.history,
                        color: Color(0xFF4F7CAC),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'PDF ${item.page}페이지 · ${timeFormat.format(item.openedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openPdf(item),
                    );
                  },
                ),
    );
  }
}
