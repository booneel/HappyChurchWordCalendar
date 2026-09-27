import 'dart:async';

import 'package:flutter/material.dart';

import 'pdf_page.dart';
import '../services/date_page_mapper.dart';
import '../services/pdf_catalog_service.dart';
import '../services/view_history_service.dart';

class SchedulePage extends StatefulWidget {
  final String displayName;

  const SchedulePage({super.key, required this.displayName});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final ViewHistoryService history = ViewHistoryService();
  final PdfCatalogService catalogService = PdfCatalogService();

  DateTime selected = DateTime.now();
  bool titlesLoaded = false;
  DateTime? _lastTappedDate;
  DateTime? _lastTappedAt;

  @override
  void initState() {
    super.initState();
    catalogService.loadTitles().then((_) {
      if (mounted) {
        setState(() => titlesLoaded = true);
      }
    });
  }

  Future<void> _openSelected() async {
    late final int page;
    try {
      page = DatePageMapper.pdfPageForDate(selected);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
      return;
    }

    // "보기"를 직접 눌렀을 때만 조회수 집계.
    await history.recordDirectOpen(page: page, date: selected);

    final title = catalogService.formatTitleForDate(selected);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPage(
          title: title,
          page: page,
          year: selected.year,
        ),
      ),
    );
  }

  void _onDateChanged(DateTime value) {
    final now = DateTime.now();
    final isDoubleTap =
        _lastTappedDate != null &&
        _lastTappedAt != null &&
        DateUtils.isSameDay(_lastTappedDate, value) &&
        now.difference(_lastTappedAt!) <= const Duration(milliseconds: 450);

    setState(() {
      selected = value;
    });
    _lastTappedDate = value;
    _lastTappedAt = now;

    if (isDoubleTap) {
      unawaited(_openSelected());
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTitle = catalogService.formatTitleForDate(selected);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text(
            '찾아보기',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '날짜를 선택해 말씀을 찾아보세요.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onDoubleTap: () => unawaited(_openSelected()),
            child: Card(
              child: CalendarDatePicker(
                initialDate: selected,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                onDateChanged: _onDateChanged,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _openSelected,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(
                titlesLoaded
                    ? selectedTitle
                    : '${selected.year}년 ${selected.month}월 ${selected.day}일',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
