import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/pdf_settings_service.dart';
import 'admin_title_catalog_page.dart';

class AdminPageSettingsPage extends StatefulWidget {
  const AdminPageSettingsPage({super.key});

  @override
  State<AdminPageSettingsPage> createState() => _AdminPageSettingsPageState();
}

class _AdminPageSettingsPageState extends State<AdminPageSettingsPage> {
  final PdfSettingsService _settingsService = PdfSettingsService();

  late TextEditingController _startPageController;
  late TextEditingController _pageCountController;

  bool _loading = true;
  bool _saving = false;

  int _startPage = 4;
  int _pageCount = 365;
  int _pdfPageCount = 368;
  final int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _startPageController = TextEditingController();
    _pageCountController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _startPageController.dispose();
    _pageCountController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    try {
      final settings = await _settingsService.loadSettings(forceRefresh: true);
      _startPage = settings.dailyStartPdfPage;
      _pageCount = settings.dailyPageCount;
      _pdfPageCount = settings.pdfPageCount;

      final availableDays = _availableDayCount(_startPage);
      if (_pageCount > availableDays) {
        _pageCount = availableDays;
      }

      _startPageController.text = _startPage.toString();
      _pageCountController.text = _pageCount.toString();
    } catch (e) {
      _showError('설정을 불러오는 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    final startInput = int.tryParse(_startPageController.text.trim());
    final countInput = int.tryParse(_pageCountController.text.trim());

    if (startInput == null || startInput < 1) {
      _showSnackBar('시작 페이지 번호는 1 이상의 정수여야 합니다.');
      return;
    }

    if (startInput > _pdfPageCount) {
      _showSnackBar('시작 페이지는 PDF 전체 페이지 수($_pdfPageCount)보다 클 수 없습니다.');
      return;
    }

    if (countInput == null || countInput < 1 || countInput > 366) {
      _showSnackBar('1~366일 범위로 입력해 주세요.');
      return;
    }

    final availableDays = _availableDayCount(startInput);
    if (countInput > availableDays) {
      _showSnackBar(
        '현재 PDF에서 매핑할 수 있는 날짜는 최대 $availableDays일입니다. 페이지 수와 시작 페이지를 확인해 주세요.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _settingsService.saveSettings(
        dailyStartPdfPage: startInput,
        dailyPageCount: countInput,
        pdfPageCount: _pdfPageCount,
      );

      setState(() {
        _startPage = startInput;
        _pageCount = countInput;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('날짜/페이지 매핑 설정이 저장되었습니다.')));
    } catch (e) {
      _showError('설정 저장 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  int _availableDayCount(int startPage) {
    final remainingPages = _pdfPageCount - startPage + 1;
    if (remainingPages < 1) return 0;
    return remainingPages > 366 ? 366 : remainingPages;
  }

  int _mappedDayCount(int availableDays) {
    if (_pageCount < 1) return 0;
    return _pageCount < availableDays ? _pageCount : availableDays;
  }

  @override
  Widget build(BuildContext context) {
    final yearStart = DateTime(_year, 1, 1);
    final availableDays = _availableDayCount(_startPage);
    final mappedDayCount = _mappedDayCount(availableDays);
    final endPage =
        mappedDayCount > 0 ? _startPage + mappedDayCount - 1 : _startPage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('날짜 / 페이지 관리'),
        actions: [
          IconButton(
            tooltip: '저장',
            onPressed: _loading || _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // 1. 설정 입력 카드
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚙️ PDF 페이지 시작점 설정',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '1월 1일 말씀이 시작하는 PDF 페이지 번호를 지정합니다.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final startPageField = TextField(
                                controller: _startPageController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '1월 1일 PDF 페이지',
                                  hintText: '예: 4',
                                  suffixText: '페이지',
                                ),
                                onChanged: (val) {
                                  final parsed = int.tryParse(val);
                                  if (parsed != null && parsed >= 1) {
                                    setState(() {
                                      _startPage = parsed;
                                      final availableDays =
                                          _availableDayCount(parsed);
                                      if (_pageCount > availableDays) {
                                        _pageCount = availableDays;
                                        _pageCountController.text =
                                            availableDays.toString();
                                      }
                                    });
                                  }
                                },
                              );
                              final pageCountField = TextField(
                                controller: _pageCountController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '총 일수 (기본 365)',
                                  hintText: '365',
                                  suffixText: '일',
                                ),
                                onChanged: (val) {
                                  final parsed = int.tryParse(val);
                                  if (parsed != null && parsed >= 1) {
                                    setState(() => _pageCount = parsed);
                                  }
                                },
                              );

                              if (constraints.maxWidth < 360) {
                                return Column(
                                  children: [
                                    startPageField,
                                    const SizedBox(height: 12),
                                    pageCountField,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: startPageField),
                                  const SizedBox(width: 12),
                                  Expanded(child: pageCountField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _saveSettings,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('매핑 설정 저장'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminTitleCatalogPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.list_alt_outlined),
                            label: Text('$mappedDayCount일 제목 카탈로그 관리 이동'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. 미리보기 헤더
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📅 매핑 미리보기',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '1월 1일 (PDF ${_startPage}p) ~ 12월 31일 (PDF ${endPage}p)',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PDF 전체 $_pdfPageCount페이지 · 날짜 매핑 $mappedDayCount일',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      if (_pageCount > availableDays)
                        Text(
                          '현재 시작 페이지 기준 최대 매핑 일수: $availableDays일',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),

                // 3. PDF 페이지와 날짜 매핑 리스트
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mappedDayCount,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final date = yearStart.add(Duration(days: index));
                    final pdfPage = _startPage + index;
                    final isToday = DateTime.now().year == date.year &&
                        DateTime.now().month == date.month &&
                        DateTime.now().day == date.day;

                    return ListTile(
                      tileColor: isToday ? Colors.amber.shade50 : null,
                      leading: SizedBox(
                        width: 80,
                        child: Text(
                          DateFormat('M월 d일 (E)', 'ko_KR').format(date),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isToday ? FontWeight.w800 : FontWeight.w600,
                            color: isToday
                                ? const Color(0xFF4F7CAC)
                                : Colors.black87,
                          ),
                        ),
                      ),
                      title: Text(
                        'PDF $pdfPage 페이지',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isToday ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      trailing: isToday
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F7CAC),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '오늘',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : SizedBox(
                              width: 58,
                              child: Text(
                                '${index + 1}번째 날',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
