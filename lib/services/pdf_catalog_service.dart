import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'date_page_mapper.dart';
import 'backend_config.dart';
import 'nas_api_client.dart';

class ImportedTitleCatalog {
  final int year;
  final Map<String, String> titles;
  final Map<String, double> confidences;
  final List<String> skipped;

  const ImportedTitleCatalog({
    required this.year,
    required this.titles,
    required this.confidences,
    required this.skipped,
  });
}

class PdfCatalogService {
  PdfCatalogService._();

  static final PdfCatalogService instance = PdfCatalogService._();

  factory PdfCatalogService() => instance;

  static const String collection = 'pdf_catalog';
  static const String documentId = 'current';
  static const int currentTitleAlgorithmVersion = 5;
  static const String _localKey = 'pdf_catalog_titles_v4';
  static const String _localConfKey = 'pdf_catalog_confidences_v4';
  static const String _localYearKey = 'pdf_catalog_year_v4';

  final NasApiClient _nas = NasApiClient.instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Map<String, String>? _memoryTitles;
  Map<String, double>? _memoryConfidences;
  int? _memoryYear;
  int _memoryTitleAlgorithmVersion = 0;
  Future<Map<String, String>>? _loading;

  Future<Map<String, String>> loadTitles({
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && _memoryTitles != null) {
      return Future.value(_memoryTitles!);
    }

    if (!forceRefresh && _loading != null) {
      return _loading!;
    }

    final future = _load(forceRefresh: forceRefresh);

    if (!forceRefresh) {
      _loading = future;
    }

    return future;
  }

  bool get needsTitleRebuild =>
      _memoryTitleAlgorithmVersion < currentTitleAlgorithmVersion;

  Future<Map<String, String>> _load({
    required bool forceRefresh,
  }) async {
    if (BackendConfig.useNas) {
      return _loadFromNas();
    }

    try {
      final snapshot = await _db.collection(collection).doc(documentId).get();

      if (snapshot.exists) {
        final data = snapshot.data() ?? <String, dynamic>{};
        final rawTitles = data['titles'];
        final rawConf = data['confidences'];
        final year = (data['year'] as num?)?.toInt();
        _memoryTitleAlgorithmVersion =
            (data['titleAlgorithmVersion'] as num?)?.toInt() ?? 0;

        if (rawTitles is Map) {
          final result = <String, String>{};
          for (final entry in rawTitles.entries) {
            final value = entry.value;
            if (value is String && value.trim().isNotEmpty) {
              result[entry.key.toString()] = value.trim();
            }
          }

          if (rawConf is Map) {
            final confResult = <String, double>{};
            for (final entry in rawConf.entries) {
              final val = (entry.value as num?)?.toDouble();
              if (val != null) confResult[entry.key.toString()] = val;
            }
            _memoryConfidences = confResult;
          }

          if (result.isNotEmpty) {
            _memoryTitles = result;
            _memoryYear = year;

            await _saveLocal(
              result,
              year: year,
              confidences: _memoryConfidences,
            );

            return result;
          }
        }
      }
    } catch (_) {}

    final local = await _loadLocal();

    _memoryTitles = local.$1;
    _memoryConfidences = local.$2;
    _memoryYear = local.$3;

    return _memoryTitles!;
  }

  Future<Map<String, String>> _loadFromNas() async {
    try {
      final data = await _nas.getJson('/api/catalog/current');
      final rawTitles = data['titles'];
      final result = <String, String>{};
      if (rawTitles is Map) {
        for (final entry in rawTitles.entries) {
          final value = entry.value?.toString().trim() ?? '';
          if (value.isNotEmpty) result[entry.key.toString()] = value;
        }
      }
      final rawConf = data['confidences'];
      final confs = <String, double>{};
      if (rawConf is Map) {
        for (final entry in rawConf.entries) {
          final value = (entry.value as num?)?.toDouble();
          if (value != null) confs[entry.key.toString()] = value;
        }
      }
      _memoryTitles = result;
      _memoryConfidences = confs;
      _memoryYear = (data['year'] as num?)?.toInt();
      _memoryTitleAlgorithmVersion =
          (data['titleAlgorithmVersion'] as num?)?.toInt() ?? 0;
      await _saveLocal(result, year: _memoryYear, confidences: confs);
      return result;
    } catch (_) {
      final local = await _loadLocal();
      _memoryTitles = local.$1;
      _memoryConfidences = local.$2;
      _memoryYear = local.$3;
      return _memoryTitles!;
    }
  }

  String? getTitleFromLoadedCatalog(DateTime date) {
    return _memoryTitles?[DatePageMapper.monthDayKey(date)];
  }

  double? getConfidenceFromLoadedCatalog(DateTime date) {
    return _memoryConfidences?[DatePageMapper.monthDayKey(date)];
  }

  String formatTitleForDate(DateTime date) {
    final monthDay = '${date.month}월 ${date.day}일';
    final customTitle = getTitleFromLoadedCatalog(date);
    if (customTitle != null && customTitle.trim().isNotEmpty) {
      return '$monthDay - ${customTitle.trim()}';
    }
    return '$monthDay - 말씀';
  }

  Future<String?> getTitleForDate(DateTime date) async {
    final titles = await loadTitles();
    return titles[DatePageMapper.monthDayKey(date)];
  }

  Future<String?> getTitleForPage(
    int pdfPage, {
    int? year,
  }) async {
    if (!DatePageMapper.isDailyPage(pdfPage)) {
      return null;
    }

    final effectiveYear = year ?? _memoryYear ?? DateTime.now().year;

    final date = DatePageMapper.dateForPdfPage(
      pdfPage,
      year: effectiveYear,
    );

    return getTitleForDate(date);
  }

  Future<int> getCatalogYear() async {
    await loadTitles();
    return _memoryYear ?? DateTime.now().year;
  }

  Future<Map<String, String>> getEditableCatalog() async {
    return Map<String, String>.from(
      await loadTitles(forceRefresh: true),
    );
  }

  Future<Map<String, double>> getEditableConfidences() async {
    await loadTitles();
    return Map<String, double>.from(_memoryConfidences ?? {});
  }

  /// Accepts either a simple `{ "01-01": "title" }` map, the app's
  /// exported `{ "year": ..., "titles": {...} }` shape, or an array of
  /// objects such as `{ "date": "01-01", "title": "..." }`.
  ImportedTitleCatalog parseTitleCatalogJson(
    String source, {
    int? fallbackYear,
  }) {
    final decoded = jsonDecode(source);
    final root = decoded is Map ? decoded : null;
    final year = _toInt(root?['year']) ?? fallbackYear ?? DateTime.now().year;
    final titles = <String, String>{};
    final confidences = <String, double>{};
    final skipped = <String>[];

    void addEntry(dynamic key, dynamic value) {
      final mapValue = value is Map ? value : null;
      final dateKey = _monthDayKeyFromValue(
        key,
        mapValue,
        year: year,
      );
      final title = _titleFromValue(value);

      if (dateKey == null || title == null) {
        final keyText = key?.toString().trim() ?? '';
        if (keyText.isNotEmpty && !_isMetadataKey(keyText)) {
          skipped.add(keyText);
        }
        return;
      }

      titles[dateKey] = title;
      final confidence = _confidenceFromValue(mapValue);
      if (confidence != null) confidences[dateKey] = confidence;
    }

    final rawTitles = root?['titles'] ?? root?['catalog'] ?? root?['items'];
    if (rawTitles is Map) {
      for (final entry in rawTitles.entries) {
        addEntry(entry.key, entry.value);
      }
    } else if (rawTitles is List) {
      for (var index = 0; index < rawTitles.length; index++) {
        addEntry(index, rawTitles[index]);
      }
    } else if (decoded is Map) {
      for (final entry in decoded.entries) {
        addEntry(entry.key, entry.value);
      }
    } else if (decoded is List) {
      for (var index = 0; index < decoded.length; index++) {
        addEntry(index, decoded[index]);
      }
    } else {
      throw const FormatException('JSON 최상위 값은 객체 또는 배열이어야 합니다.');
    }

    final rawConfidences = root?['confidences'];
    if (rawConfidences is Map) {
      for (final entry in rawConfidences.entries) {
        final key = _monthDayKeyFromValue(entry.key, null, year: year);
        final value = _toDouble(entry.value);
        if (key != null && value != null) {
          confidences[key] = value.clamp(0.0, 1.0);
        }
      }
    }

    for (final key in titles.keys) {
      confidences.putIfAbsent(key, () => 1.0);
    }

    if (titles.isEmpty) {
      throw const FormatException(
        '날짜와 제목을 찾지 못했습니다. 01-01 키 또는 date/title 형식을 확인해 주세요.',
      );
    }

    return ImportedTitleCatalog(
      year: year,
      titles: titles,
      confidences: confidences,
      skipped: skipped,
    );
  }

  String? _titleFromValue(dynamic value) {
    if (value is String) {
      final title = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      return title.isEmpty ? null : title;
    }
    if (value is! Map) return null;

    const keys = [
      'title',
      'name',
      'text',
      'content',
      'devotionalTitle',
      '제목',
      '말씀',
    ];
    for (final key in keys) {
      final candidate = value[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }
    return null;
  }

  double? _confidenceFromValue(Map? value) {
    if (value == null) return null;
    final confidence = _toDouble(value['confidence']);
    return confidence?.clamp(0.0, 1.0);
  }

  String? _monthDayKeyFromValue(
    dynamic key,
    Map? value, {
    required int year,
  }) {
    final valueDate = value?['date'] ?? value?['날짜'];
    final fromValue = _monthDayFromText(valueDate?.toString());
    if (fromValue != null) return fromValue;

    final month = _toInt(value?['month'] ?? value?['월']);
    final day = _toInt(value?['dayOfMonth'] ?? value?['day'] ?? value?['일']);
    if (month != null && day != null) {
      return _formatMonthDay(month, day);
    }

    final page = _toInt(value?['page'] ?? value?['pdfPage']);
    if (page != null && DatePageMapper.isDailyPage(page)) {
      return DatePageMapper.monthDayKey(
        DatePageMapper.dateForPdfPage(page, year: year),
      );
    }

    final keyText = key?.toString().trim();
    final keyPage = _toInt(keyText);
    if (keyPage != null && DatePageMapper.isDailyPage(keyPage)) {
      return DatePageMapper.monthDayKey(
        DatePageMapper.dateForPdfPage(keyPage, year: year),
      );
    }
    return _monthDayFromText(keyText);
  }

  String? _monthDayFromText(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return _formatMonthDay(iso.month, iso.day);

    final match = RegExp(
      r'^(?:\d{4}[-/.])?(\d{1,2})\s*[-/.]\s*(\d{1,2})$|'
      r'^(\d{1,2})\s*월\s*(\d{1,2})\s*일?$|'
      r'^(\d{1,2})\s*/\s*(\d{1,2})$',
    ).firstMatch(text);
    if (match == null) return null;

    final month =
        int.tryParse(match.group(1) ?? match.group(3) ?? match.group(5) ?? '');
    final day =
        int.tryParse(match.group(2) ?? match.group(4) ?? match.group(6) ?? '');
    if (month == null || day == null) return null;
    return _formatMonthDay(month, day);
  }

  String? _formatMonthDay(int month, int day) {
    if (month < 1 || month > 12 || day < 1) return null;
    final check = DateTime(2001, month, day);
    if (check.month != month || check.day != day) return null;
    return '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  bool _isMetadataKey(String key) {
    return const {
      'year',
      'startPage',
      'pageCount',
      'source',
      'updatedAt',
      'titleAlgorithmVersion',
      'confidences',
      'lowConfidenceKeys',
    }.contains(key);
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> saveWholeCatalog({
    required int year,
    required Map<String, String> titles,
    Map<String, double>? confidences,
    List<String>? lowConfidenceKeys,
    String source = 'admin',
  }) async {
    final cleaned = <String, String>{};

    for (final entry in titles.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) {
        cleaned[entry.key] = value;
      }
    }

    final dataToSave = <String, dynamic>{
      'year': year,
      'startPage': DatePageMapper.dailyStartPdfPage,
      'pageCount': DatePageMapper.dailyPageCount,
      'titles': cleaned,
      'source': source,
      'titleAlgorithmVersion': currentTitleAlgorithmVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (confidences != null) {
      dataToSave['confidences'] = confidences;
    }

    if (lowConfidenceKeys != null) {
      dataToSave['lowConfidenceKeys'] = lowConfidenceKeys;
    }

    if (BackendConfig.useNas) {
      await _nas.putJson('/api/catalog/current', {
        ...dataToSave,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await _db.collection(collection).doc(documentId).set(
            dataToSave,
            SetOptions(merge: true),
          );
    }

    _memoryTitles = cleaned;
    _memoryConfidences = confidences ?? _memoryConfidences;
    _memoryYear = year;
    _loading = null;

    await _saveLocal(
      cleaned,
      year: year,
      confidences: confidences,
    );
  }

  Future<void> updateOneTitle({
    required int year,
    required DateTime date,
    required String title,
  }) async {
    final current = Map<String, String>.from(
      await loadTitles(),
    );

    final conf = Map<String, double>.from(
      _memoryConfidences ?? {},
    );

    final key = DatePageMapper.monthDayKey(date);

    if (title.trim().isEmpty) {
      current.remove(key);
      conf.remove(key);
    } else {
      current[key] = title.trim();
      conf[key] = 1.0; // 관리자가 수동 확인/수정한 항목은 확신도 100% (1.0)
    }

    await saveWholeCatalog(
      year: year,
      titles: current,
      confidences: conf,
      source: 'admin-edited',
    );
  }

  Future<(Map<String, String>, Map<String, double>?, int?)> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_localKey);
    final confString = prefs.getString(_localConfKey);
    final year = prefs.getInt(_localYearKey);

    Map<String, String> titles = {};
    Map<String, double>? confs;

    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final raw = jsonDecode(jsonString);
        if (raw is Map) {
          for (final entry in raw.entries) {
            if (entry.value is String) {
              titles[entry.key.toString()] = (entry.value as String).trim();
            }
          }
        }
      } catch (_) {}
    }

    if (confString != null && confString.isNotEmpty) {
      try {
        final raw = jsonDecode(confString);
        if (raw is Map) {
          confs = {};
          for (final entry in raw.entries) {
            final val = (entry.value as num?)?.toDouble();
            if (val != null) confs[entry.key.toString()] = val;
          }
        }
      } catch (_) {}
    }

    return (titles, confs, year);
  }

  Future<void> _saveLocal(
    Map<String, String> titles, {
    int? year,
    Map<String, double>? confidences,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _localKey,
      jsonEncode(titles),
    );

    if (confidences != null) {
      await prefs.setString(
        _localConfKey,
        jsonEncode(confidences),
      );
    }

    if (year != null) {
      await prefs.setInt(
        _localYearKey,
        year,
      );
    }
  }
}
