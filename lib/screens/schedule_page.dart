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

  Future<void> _showYearMonthPicker() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _YearMonthPickerDialog(
        initialYear: selected.year,
        initialMonth: selected.month,
      ),
    );

    if (picked != null) {
      final maxDay = _daysInMonth(picked.year, picked.month);
      final day = selected.day.clamp(1, maxDay);
      setState(() {
        selected = DateTime(picked.year, picked.month, day);
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
              // 깔끔한 연도/월 빠른 선택 버튼
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showYearMonthPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${selected.year}년 ${selected.month}월',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

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

class _YearMonthPickerDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;

  const _YearMonthPickerDialog({
    required this.initialYear,
    required this.initialMonth,
  });

  @override
  State<_YearMonthPickerDialog> createState() => _YearMonthPickerDialogState();
}

class _YearMonthPickerDialogState extends State<_YearMonthPickerDialog> {
  int step = 1; // 1: 연도 선택, 2: 월 선택
  late int selectedYear;
  late int selectedMonth;

  @override
  void initState() {
    super.initState();
    selectedYear = widget.initialYear;
    selectedMonth = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              step == 1 ? '📅 연도 선택 (1/2단계)' : '📅 $selectedYear년 - 월 선택 (2/2단계)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (step == 2)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => setState(() => step = 1),
              child: const Text('연도 변경'),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: step == 1 ? _buildYearGrid() : _buildMonthGrid(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
      ],
    );
  }

  Widget _buildYearGrid() {
    final years = List.generate(16, (i) => 2020 + i);
    return GridView.builder(
      shrinkWrap: true,
      itemCount: years.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final year = years[index];
        final isSelected = year == selectedYear;
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade300,
            ),
          ),
          onPressed: () {
            setState(() {
              selectedYear = year;
              step = 2; // 연도 선택 후 자동으로 월 선택으로 이동
            });
          },
          child: Text(
            '$year년',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black87,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthGrid() {
    return GridView.builder(
      shrinkWrap: true,
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final month = index + 1;
        final isSelected = month == selectedMonth;
        return FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: isSelected ? Colors.white : Colors.black87,
          ),
          onPressed: () {
            Navigator.pop(
              context,
              DateTime(selectedYear, month),
            );
          },
          child: Text(
            '$month월',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}
