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
  DateTime? _lastCalendarDate;
  final GlobalKey _calendarKey = GlobalKey();
  bool _ignoreCalendarDoubleTap = false;

  @override
  void initState() {
    super.initState();
    catalogService.loadTitles().then((_) {
      if (mounted) {
        setState(() => titlesLoaded = true);
      }
    });
  }

  Future<void> _openDate(DateTime date) async {
    late final int page;
    try {
      page = DatePageMapper.pdfPageForDate(date);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }

    // "보기"를 직접 눌렀을 때만 조회수 집계.
    await history.recordDirectOpen(page: page, date: date);

    final title = catalogService.formatTitleForDate(date);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPage(title: title, page: page, year: date.year),
      ),
    );
  }

  Future<void> _openSelected() => _openDate(selected);

  void _onDateChanged(DateTime value) {
    _lastCalendarDate = value;
    setState(() {
      selected = value;
    });
  }

  void _openLastCalendarDate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ignoreCalendarDoubleTap) return;
      unawaited(_openDate(_lastCalendarDate ?? selected));
    });
  }

  void _onCalendarDoubleTapDown(TapDownDetails details) {
    final renderObject = _calendarKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      _ignoreCalendarDoubleTap = false;
      return;
    }

    final localPosition = renderObject.globalToLocal(details.globalPosition);
    // CalendarDatePicker의 월 이동 헤더와 좌우 화살표 영역은 PDF 열기에서 제외한다.
    _ignoreCalendarDoubleTap = localPosition.dy <= 80;
  }

  @override
  Widget build(BuildContext context) {
    final selectedPage = DatePageMapper.pdfPageForDateOrNull(selected);
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
            onDoubleTapDown: _onCalendarDoubleTapDown,
            onDoubleTap: _openLastCalendarDate,
            child: Card(
              key: _calendarKey,
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
              onPressed: selectedPage == null ? null : _openSelected,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(
                selectedPage == null
                    ? '해당 날짜의 PDF 페이지가 없습니다'
                    : titlesLoaded
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
