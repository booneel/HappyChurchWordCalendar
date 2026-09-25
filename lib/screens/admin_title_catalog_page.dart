import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/date_page_mapper.dart';
import '../services/pdf_catalog_builder_service.dart';
import '../services/pdf_catalog_service.dart';

class AdminTitleCatalogPage extends StatefulWidget {
  const AdminTitleCatalogPage({super.key});

  @override
  State<AdminTitleCatalogPage> createState() => _AdminTitleCatalogPageState();
}

class _AdminTitleCatalogPageState extends State<AdminTitleCatalogPage> {
  final PdfCatalogService _catalog = PdfCatalogService.instance;

  PdfCatalogBuilderService? _builder;

  bool loading = true;
  bool building = false;
  bool saving = false;

  int year = DateTime.now().year;
  int current = 0;
  int total = DatePageMapper.dailyPageCount;
  String status = '';
  String searchQuery = '';
  String filterMode = 'all'; // 'all', 'review_needed'

  Map<String, String> titles = {};
  Map<String, double> confidences = {};
  List<String> failed = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await _catalog.getEditableCatalog();
      final confs = await _catalog.getEditableConfidences();
      final catalogYear = await _catalog.getCatalogYear();

      if (!mounted) return;

      setState(() {
        titles = catalog;
        confidences = confs;
        year = catalogYear;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _showError(e);
    }
  }

  Future<void> _buildCatalog() async {
    if (building) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('365개 제목 비전/레이아웃 전체 분석'),
        content: const SingleChildScrollView(
          child: Text(
            'PDF 전체 365페이지의 레이아웃과 문맥을 한 번 분석합니다.\n\n'
            '상단 날짜 아래 문구의 글꼴, 위치, 관계를 고려하여 제목 전체를 복원합니다.\n\n'
            '완료 후 일반 사용자 앱에서는 전혀 분석을 실행하지 않으며, '
            '확신도가 낮거나 검수가 필요한 항목은 🔴 배지로 강조 표시됩니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('분석 시작'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final builder = PdfCatalogBuilderService();
    _builder = builder;

    setState(() {
      building = true;
      current = 0;
      total = DatePageMapper.dailyPageCount;
      status = '준비 중...';
      failed = [];
    });

    try {
      final result = await builder.build(
        year: year,
        onProgress: (currentValue, totalValue, message) {
          if (!mounted) return;

          setState(() {
            current = currentValue;
            total = totalValue;
            status = message;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        titles = result.titles;
        confidences = result.confidences;
        failed = result.failedKeys;
      });

      await _saveCatalog(
        source: 'admin-auto-build-v4',
        confidences: result.confidences,
        lowConfidenceKeys: result.lowConfidenceKeys,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('제목 전체 분석 완료'),
          content: SingleChildScrollView(
            child: Text(
              '성공: ${result.successCount}개\n'
              '🔴 검수 필요 (확신도 낮음): ${result.lowConfidenceCount}개\n'
              '미인식: ${result.failedCount}개\n\n'
              '확신도가 낮거나 미인식된 항목은 [검수 필요] 탭에서 직접 확인/수정하세요.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) {
        setState(() {
          building = false;
        });
      }
    }
  }

  Future<void> _importJsonCatalog() async {
    if (building || saving) return;

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const FormatException('JSON 파일 내용을 읽지 못했습니다.');
      }

      final imported = _catalog.parseTitleCatalogJson(
        utf8.decode(bytes, allowMalformed: true),
        fallbackYear: year,
      );

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('JSON 제목 불러오기'),
          content: SingleChildScrollView(
            child: Text(
              '${file.name}에서 ${imported.titles.length}개 제목을 찾았습니다.\n'
              '현재 카탈로그를 불러온 제목으로 교체합니다.\n\n'
              '검수 필요 항목: ${imported.confidences.values.where((value) => value < 0.8).length}개'
              '${imported.skipped.isEmpty ? '' : '\n읽지 못한 항목: ${imported.skipped.length}개'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('불러오기'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        titles = imported.titles;
        confidences = imported.confidences;
        year = imported.year;
        failed = [];
      });

      await _saveCatalog(
        source: 'json-import',
        confidences: imported.confidences,
        lowConfidenceKeys: imported.confidences.entries
            .where((entry) => entry.value < 0.8)
            .map((entry) => entry.key)
            .toList(),
      );
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  void _showJsonFormatDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('JSON 제목 파일 형식'),
        content: const SingleChildScrollView(
          child: SelectableText('''권장 형식 1: 날짜 키와 제목

{
  "year": 2026,
  "titles": {
    "01-01": "새해의 소망",
    "01-02": "믿음의 길"
  }
}

권장 형식 2: 배열

[
  {"date": "2026-01-01", "title": "새해의 소망"},
  {"month": 1, "day": 2, "title": "믿음의 길"}
]

날짜는 MM-DD, YYYY-MM-DD, 1월 2일 형식을 사용할 수 있습니다.
title 대신 name 또는 제목 필드도 인식합니다.
confidence를 넣으면 검수 필요 여부에 반영합니다.'''),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCatalog({
    String source = 'admin-edited',
    Map<String, double>? confidences,
    List<String>? lowConfidenceKeys,
  }) async {
    if (saving) return;

    setState(() {
      saving = true;
    });

    try {
      await _catalog.saveWholeCatalog(
        year: year,
        titles: titles,
        confidences: confidences ?? this.confidences,
        lowConfidenceKeys: lowConfidenceKeys,
        source: source,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('제목 카탈로그가 저장되었습니다.')));
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  Future<void> _editTitle(DateTime date) async {
    final key = DatePageMapper.monthDayKey(date);

    final controller = TextEditingController(text: titles[key] ?? '');

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(DateFormat('yyyy년 M월 d일', 'ko_KR').format(date)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: '묵상 말씀 제목',
                  hintText: '예: 고난을 통과하면서 / 영생',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '관리자가 수동으로 수정/확인한 제목은 확신도 100%로 검수 완료 처리됩니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('저장 및 검수 완료'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);

    if (value == null) return;

    setState(() {
      if (value.isEmpty) {
        titles.remove(key);
        confidences.remove(key);
      } else {
        titles[key] = value;
        confidences[key] = 1.0; // 관리자 수동 검수 완료 100%
      }

      failed.remove(key);
    });

    await _catalog.updateOneTitle(year: year, date: date, title: value);
  }

  void _showError(Object error) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: SingleChildScrollView(
          child: SelectableText('$error'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final yearStart = DateTime(year, 1, 1);
    final totalDays = DatePageMapper.dailyPageCount;

    final allDays = List.generate(totalDays, (index) {
      final date = yearStart.add(Duration(days: index));
      final page = DatePageMapper.dailyStartPdfPage + index;
      final key = DatePageMapper.monthDayKey(date);
      final title = titles[key] ?? '';
      final confidence = confidences[key] ?? 0.0;
      final isLowConfidence = title.isEmpty || confidence < 0.80;

      return (
        date: date,
        page: page,
        key: key,
        title: title,
        confidence: confidence,
        isLowConfidence: isLowConfidence,
      );
    });

    final reviewNeededCount =
        allDays.where((item) => item.isLowConfidence).length;

    final filteredDays = allDays.where((item) {
      if (filterMode == 'review_needed' && !item.isLowConfidence) {
        return false;
      }

      if (searchQuery.isEmpty) return true;
      final dateStr = DateFormat('yyyy년 M월 d일', 'ko_KR').format(item.date);
      final shortDateStr = DateFormat('M/d', 'ko_KR').format(item.date);
      return (dateStr.contains(searchQuery) ||
              shortDateStr.contains(searchQuery)) ||
          item.title.contains(searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('제목 카탈로그 & 검수 센터'),
        actions: [
          IconButton(
            tooltip: '저장',
            onPressed: saving || building ? null : _saveCatalog,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '365일 제목 검수 관리',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Text(
                          '${titles.length}/$totalDays',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '일반 사용자 앱에서는 어떠한 이미지/OCR 분석도 실행하지 않으며, '
                      '이 화면에서 관리자가 1회 분석 후 검수한 제목만 즉시 읽어옵니다.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                      ),
                    ),
                    if (_catalog.needsTitleRebuild) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Text(
                          '기존 제목 카탈로그가 현재 분석 버전보다 오래되었습니다.\n'
                          '아래의 전체 분석을 다시 실행한 뒤 저장해야 잘못 추출된 본문이 교체됩니다.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: building ? null : _importJsonCatalog,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('JSON 제목 파일 불러오기'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _showJsonFormatDialog,
                        icon: const Icon(Icons.help_outline, size: 18),
                        label: const Text('JSON 형식 예시 보기'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: building ? null : _buildCatalog,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('PDF 전체 365일 제목 분석 다시 실행'),
                      ),
                    ),
                    if (building) ...[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: total == 0 ? 0 : current / total,
                      ),
                      const SizedBox(height: 8),
                      Text('$current / $total'),
                      Text(
                        status,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          _builder?.cancel();
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('중단 요청'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('전체 ($totalDays)'),
                              selected: filterMode == 'all',
                              onSelected: (_) =>
                                  setState(() => filterMode = 'all'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              avatar: reviewNeededCount > 0
                                  ? const Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: Colors.red,
                                    )
                                  : null,
                              label: Text('🔴 검수 필요 ($reviewNeededCount)'),
                              selected: filterMode == 'review_needed',
                              selectedColor: Colors.red.shade100,
                              onSelected: (_) =>
                                  setState(() => filterMode = 'review_needed'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              onChanged: (val) => setState(() => searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: '날짜 또는 제목 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: filteredDays.isEmpty
                ? const Center(child: Text('검색 또는 검수 필요 항목이 없습니다.'))
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filteredDays.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filteredDays[index];
                        final confPercent =
                            (item.confidence * 100).toStringAsFixed(0);

                        return ListTile(
                          tileColor: item.isLowConfidence
                              ? Colors.amber.shade50
                              : null,
                          leading: SizedBox(
                            width: 112,
                            child: Text(
                              DateFormat(
                                'yyyy년 M월 d일',
                                'ko_KR',
                              ).format(item.date),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: item.isLowConfidence
                                    ? Colors.red.shade800
                                    : null,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title.isNotEmpty
                                      ? item.title
                                      : '제목 미입력 (확인 필요)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: item.title.isEmpty
                                        ? Colors.red
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (item.title.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.isLowConfidence
                                        ? Colors.amber.shade100
                                        : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: item.isLowConfidence
                                          ? Colors.amber.shade400
                                          : Colors.green.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    '$confPercent%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: item.isLowConfidence
                                          ? Colors.amber.shade900
                                          : Colors.green.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editTitle(item.date),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
