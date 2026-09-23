import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'pdf_page.dart';
import '../services/date_page_mapper.dart';
import '../services/view_history_service.dart';

class SchedulePage extends StatefulWidget {
  final String displayName;

  const SchedulePage({
    super.key,
    required this.displayName,
  });

  @override
  State<SchedulePage> createState() =>
      _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final ViewHistoryService history = ViewHistoryService();

  DateTime selected = DateTime.now();

  Future<void> _openSelected() async {
    final page =
        DatePageMapper.pdfPageForDate(selected);

    // "보기"를 직접 눌렀을 때만 조회수 집계.
    unawaited(
      history.recordDirectOpen(
        page: page,
        date: selected,
      ),
    );

    final dateText =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selected);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPage(
          title: '$dateText · 오늘의 말씀',
          page: page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selected);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text(
            '찾아보기',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            '날짜를 선택해 말씀을 찾아보세요.',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 18),

          Card(
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              onDateChanged: (value) {
                setState(() {
                  selected = value;
                });
              },
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const Icon(
                Icons.menu_book_outlined,
              ),
              title: const Text(
                '오늘의 말씀',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(dateText),
              trailing: FilledButton(
                onPressed: _openSelected,
                child: const Text('보기'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
