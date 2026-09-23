import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'date_page_mapper.dart';

class PdfCatalogService {
  PdfCatalogService._();

  static final PdfCatalogService instance = PdfCatalogService._();

  factory PdfCatalogService() => instance;

  static const String collection = 'pdf_catalog';
  static const String documentId = 'current';
  static const String _localKey = 'pdf_catalog_titles_v4';
  static const String _localYearKey = 'pdf_catalog_year_v4';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Map<String, String>? _memoryTitles;
  int? _memoryYear;
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

  Future<Map<String, String>> _load({
    required bool forceRefresh,
  }) async {
    // 앱 실행 시 Firestore 1회 읽기.
    // 실패하면 기기 로컬 카탈로그를 사용합니다.
    try {
      final snapshot = await _db
          .collection(collection)
          .doc(documentId)
          .get();

      if (snapshot.exists) {
        final data = snapshot.data() ?? <String, dynamic>{};
        final rawTitles = data['titles'];
        final year = (data['year'] as num?)?.toInt();

        if (rawTitles is Map) {
          final result = <String, String>{};

          for (final entry in rawTitles.entries) {
            final value = entry.value;
            if (value is String && value.trim().isNotEmpty) {
              result[entry.key.toString()] = value.trim();
            }
          }

          if (result.isNotEmpty) {
            _memoryTitles = result;
            _memoryYear = year;

            await _saveLocal(
              result,
              year: year,
            );

            return result;
          }
        }
      }
    } catch (_) {}

    final local = await _loadLocal();

    _memoryTitles = local.$1;
    _memoryYear = local.$2;

    return _memoryTitles!;
  }

  String? getTitleFromLoadedCatalog(DateTime date) {
    return _memoryTitles?[DatePageMapper.monthDayKey(date)];
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

    final effectiveYear =
        year ?? _memoryYear ?? DateTime.now().year;

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

  Future<void> saveWholeCatalog({
    required int year,
    required Map<String, String> titles,
    String source = 'admin',
  }) async {
    final cleaned = <String, String>{};

    for (final entry in titles.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) {
        cleaned[entry.key] = value;
      }
    }

    await _db.collection(collection).doc(documentId).set(
      {
        'year': year,
        'startPage': DatePageMapper.dailyStartPdfPage,
        'pageCount': DatePageMapper.dailyPageCount,
        'titles': cleaned,
        'source': source,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    _memoryTitles = cleaned;
    _memoryYear = year;
    _loading = null;

    await _saveLocal(
      cleaned,
      year: year,
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

    final key = DatePageMapper.monthDayKey(date);

    if (title.trim().isEmpty) {
      current.remove(key);
    } else {
      current[key] = title.trim();
    }

    await saveWholeCatalog(
      year: year,
      titles: current,
      source: 'admin-edited',
    );
  }

  Future<void> replaceMemoryCatalog({
    required int year,
    required Map<String, String> titles,
  }) async {
    _memoryTitles = Map<String, String>.from(titles);
    _memoryYear = year;
    _loading = null;

    await _saveLocal(
      titles,
      year: year,
    );
  }

  Future<(Map<String, String>, int?)> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_localKey);
    final year = prefs.getInt(_localYearKey);

    if (jsonString == null || jsonString.isEmpty) {
      return (<String, String>{}, year);
    }

    try {
      final raw = jsonDecode(jsonString);

      if (raw is Map) {
        final result = <String, String>{};

        for (final entry in raw.entries) {
          if (entry.value is String) {
            result[entry.key.toString()] =
                (entry.value as String).trim();
          }
        }

        return (result, year);
      }
    } catch (_) {}

    return (<String, String>{}, year);
  }

  Future<void> _saveLocal(
    Map<String, String> titles, {
    int? year,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _localKey,
      jsonEncode(titles),
    );

    if (year != null) {
      await prefs.setInt(
        _localYearKey,
        year,
      );
    }
  }
}
