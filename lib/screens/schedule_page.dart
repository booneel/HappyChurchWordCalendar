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
  bool _isOpening = false;

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
    if (_isOpening) return;
    _isOpening = true;

    try {
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
    } finally {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

  Future<void> _openSelected() => _openDate(selected);

  void _onDateChanged(DateTime value) {
    _lastCalendarDate = value;
    setState(() {
      selected = value;
    });
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  Future<void> _showYearPicker() async {
    final year = await showDialog<int>(
      context: context,
      builder: (context) => _NumberGridPickerDialog(
        title: '연도 선택',
        values: List.generate(16, (index) => 2020 + index),
        selectedValue: selected.year,
        suffix: '년',
      ),
    );

    if (year != null) {
      final maxDay = _daysInMonth(year, selected.month);
      final day = selected.day.clamp(1, maxDay);
      setState(() {
        selected = DateTime(year, selected.month, day);
      });
    }
  }

  Future<void> _showMonthPicker() async {
    final month = await showDialog<int>(
      context: context,
      builder: (context) => _NumberGridPickerDialog(
        title: '월 선택',
        values: List.generate(12, (index) => index + 1),
        selectedValue: selected.month,
        suffix: '월',
      ),
    );

    if (month != null) {
      final maxDay = _daysInMonth(selected.year, month);
      final day = selected.day.clamp(1, maxDay);
      setState(() {
        selected = DateTime(selected.year, month, day);
      });
    }
  }

  void _openLastCalendarDate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ignoreCalendarDoubleTap || _isOpening) return;
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showYearPicker,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${selected.year}년'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showMonthPicker,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('${selected.month}월'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 달력 뷰
          GestureDetector(
            onDoubleTapDown: _onCalendarDoubleTapDown,
            onDoubleTap: _openLastCalendarDate,
            child: Card(
              key: _calendarKey,
              child: CalendarDatePicker(
                key: ValueKey('calendar_${selected.year}_${selected.month}'),
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
              onPressed:
                  (selectedPage == null || _isOpening) ? null : _openSelected,
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

class _NumberGridPickerDialog extends StatelessWidget {
  final String title;
  final List<int> values;
  final int selectedValue;
  final String suffix;

  const _NumberGridPickerDialog({
    required this.title,
    required this.values,
    required this.selectedValue,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        height: values.length > 12 ? 260 : 220,
        child: GridView.builder(
          itemCount: values.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final value = values[index];
            final isSelected = value == selectedValue;
            return OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: isSelected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                foregroundColor: isSelected
                    ? Theme.of(context).colorScheme.onSecondaryContainer
                    : null,
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.secondary
                      : Colors.grey.shade300,
                ),
              ),
              onPressed: () => Navigator.pop(context, value),
              child: Text('$value$suffix'),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
      ],
    );
  }
}
