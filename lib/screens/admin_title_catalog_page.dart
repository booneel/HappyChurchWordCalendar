import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/date_page_mapper.dart';
import '../services/pdf_catalog_builder_service.dart';
import '../services/pdf_catalog_service.dart';

class AdminTitleCatalogPage extends StatefulWidget {
  const AdminTitleCatalogPage({super.key});

  @override
  State<AdminTitleCatalogPage> createState() =>
      _AdminTitleCatalogPageState();
}

class _AdminTitleCatalogPageState
    extends State<AdminTitleCatalogPage> {
  final PdfCatalogService _catalog =
      PdfCatalogService();

  PdfCatalogBuilderService? _builder;

  bool loading = true;
  bool building = false;
  bool saving = false;

  int year = DateTime.now().year;
  int current = 0;
  int total = DatePageMapper.dailyPageCount;
  String status = '';

  Map<String, String> titles = {};
  List<String> failed = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog =
          await _catalog.getEditableCatalog();
      final catalogYear =
          await _catalog.getCatalogYear();

      if (!mounted) return;

      setState(() {
        titles = catalog;
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
      builder: (_) => AlertDialog(
        title: const Text('365개 제목 자동 생성'),
        content: const Text(
          'PDF 전체 365일을 한 번 분석합니다.\n\n'
          '이 작업은 관리자에서만 실행하며 시간이 걸릴 수 있습니다. '
          '완료 후 일반 사용자 앱에서는 OCR을 실행하지 않습니다.\n\n'
          '자동 인식이 틀린 항목은 아래 목록에서 직접 수정할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text('시작'),
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
        onProgress: (
          currentValue,
          totalValue,
          message,
        ) {
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
        failed = result.failedKeys;
      });

      await _saveCatalog(
        source: 'admin-auto-build',
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('제목 생성 완료'),
          content: Text(
            '성공: ${result.successCount}개\n'
            '미인식: ${result.failedCount}개\n\n'
            '미인식 또는 틀린 제목은 목록에서 눌러 직접 수정하세요.',
          ),
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context),
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

  Future<void> _saveCatalog({
    String source = 'admin-edited',
  }) async {
    if (saving) return;

    setState(() {
      saving = true;
    });

    try {
      await _catalog.saveWholeCatalog(
        year: year,
        titles: titles,
        source: source,
      );
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  Future<void> _editTitle(
    DateTime date,
    int page,
  ) async {
    final key =
        DatePageMapper.monthDayKey(date);

    final controller = TextEditingController(
      text: titles[key] ?? '',
    );

    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          DateFormat(
            'M월 d일 · PDF $page',
            'ko_KR',
          ).format(date),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: '말씀 제목',
            hintText: '예: 충성',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (value == null) return;

    setState(() {
      if (value.isEmpty) {
        titles.remove(key);
      } else {
        titles[key] = value;
      }

      failed.remove(key);
    });

    await _catalog.updateOneTitle(
      year: year,
      date: date,
      title: value,
    );
  }

  void _showError(Object error) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: SelectableText('$error'),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final yearStart = DateTime(year, 1, 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('제목 카탈로그 관리'),
        actions: [
          IconButton(
            tooltip: '저장',
            onPressed:
                saving || building ? null : _saveCatalog,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '365일 제목 카탈로그',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Text('${titles.length}/365'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '일반 사용자는 이 목록만 읽으므로 '
                      '제목 표시가 즉시 이루어집니다.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            building ? null : _buildCatalog,
                        icon: const Icon(
                          Icons.auto_awesome,
                        ),
                        label: const Text(
                          'PDF에서 365개 제목 자동 생성',
                        ),
                      ),
                    ),
                    if (building) ...[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value:
                            total == 0 ? 0 : current / total,
                      ),
                      const SizedBox(height: 8),
                      Text('$current / $total'),
                      Text(
                        status,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                        ),
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
                    if (failed.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '미인식 ${failed.length}개 · '
                        '목록에서 직접 입력할 수 있습니다.',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: ListView.separated(
              itemCount:
                  DatePageMapper.dailyPageCount,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1),
              itemBuilder: (context, index) {
                final date = yearStart.add(
                  Duration(days: index),
                );
                final page =
                    DatePageMapper.dailyStartPdfPage +
                        index;
                final key =
                    DatePageMapper.monthDayKey(date);

                final title = titles[key];
                final isFailed =
                    failed.contains(key);

                return ListTile(
                  leading: SizedBox(
                    width: 58,
                    child: Text(
                      DateFormat(
                        'M/d',
                        'ko_KR',
                      ).format(date),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    title?.isNotEmpty == true
                        ? title!
                        : '제목 미입력',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w600,
                      color: isFailed
                          ? Theme.of(context)
                              .colorScheme
                              .error
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    'PDF $page',
                  ),
                  trailing:
                      const Icon(Icons.edit_outlined),
                  onTap: () =>
                      _editTitle(date, page),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
