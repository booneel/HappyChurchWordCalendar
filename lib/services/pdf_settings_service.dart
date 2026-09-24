import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_config.dart';
import 'nas_api_client.dart';

class PdfSettings {
  final int dailyStartPdfPage;
  final int dailyPageCount;
  final String pdfFileName;
  final DateTime? updatedAt;

  const PdfSettings({
    required this.dailyStartPdfPage,
    required this.dailyPageCount,
    required this.pdfFileName,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'dailyStartPdfPage': dailyStartPdfPage,
        'dailyPageCount': dailyPageCount,
        'pdfFileName': pdfFileName,
      };

  factory PdfSettings.fromDefaults() => const PdfSettings(
        dailyStartPdfPage: 4,
        dailyPageCount: 365,
        pdfFileName: '365일 매일묵상말씀.pdf',
      );
}

class PdfSettingsService {
  PdfSettingsService._();
  static final PdfSettingsService instance = PdfSettingsService._();
  factory PdfSettingsService() => instance;

  static const String _collection = 'pdf_settings';
  static const String _documentId = 'config';

  static const String _prefsStartPageKey = 'pdf_settings_start_page';
  static const String _prefsPageCountKey = 'pdf_settings_page_count';
  static const String _prefsFileNameKey = 'pdf_settings_file_name';

  final NasApiClient _nas = NasApiClient.instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  PdfSettings? _cachedSettings;

  /// 현재 메모리 캐시된 설정 (없으면 기본값)
  PdfSettings get currentSettings =>
      _cachedSettings ?? PdfSettings.fromDefaults();

  /// 설정 로드 (Firestore 1순위 -> SharedPreferences 2순위 -> 기본값)
  Future<PdfSettings> loadSettings({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      if (BackendConfig.useNas) {
        final data = await _nas.getJson('/api/settings/pdf');
        final settings = PdfSettings(
          dailyStartPdfPage: (data['dailyStartPdfPage'] as num?)?.toInt() ?? 4,
          dailyPageCount: (data['dailyPageCount'] as num?)?.toInt() ?? 365,
          pdfFileName:
              (data['pdfFileName'] as String?)?.trim() ?? '365일 매일묵상말씀.pdf',
          updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
        );
        _cachedSettings = settings;
        await _saveToPrefs(settings);
        return settings;
      }
      final doc = await _db.collection(_collection).doc(_documentId).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final startPage = (data['dailyStartPdfPage'] as num?)?.toInt() ?? 4;
        final pageCount = (data['dailyPageCount'] as num?)?.toInt() ?? 365;
        final fileName =
            (data['pdfFileName'] as String?)?.trim() ?? '365일 매일묵상말씀.pdf';
        final timestamp = (data['updatedAt'] as Timestamp?)?.toDate();

        final settings = PdfSettings(
          dailyStartPdfPage: startPage,
          dailyPageCount: pageCount,
          pdfFileName: fileName,
          updatedAt: timestamp,
        );

        _cachedSettings = settings;
        await _saveToPrefs(settings);
        return settings;
      }
    } catch (_) {}

    // Firestore 불러오기 실패 시 로컬 SharedPreferences 확인
    final local = await _loadFromPrefs();
    _cachedSettings = local;
    return local;
  }

  /// PDF 페이지 설정 저장 (Firestore & 로컬)
  Future<void> saveSettings({
    required int dailyStartPdfPage,
    required int dailyPageCount,
    String? pdfFileName,
  }) async {
    final fileName = pdfFileName ?? currentSettings.pdfFileName;

    final settings = PdfSettings(
      dailyStartPdfPage: dailyStartPdfPage,
      dailyPageCount: dailyPageCount,
      pdfFileName: fileName,
      updatedAt: DateTime.now(),
    );

    if (BackendConfig.useNas) {
      await _nas.putJson('/api/settings/pdf', {
        'dailyStartPdfPage': dailyStartPdfPage,
        'dailyPageCount': dailyPageCount,
        'pdfFileName': fileName,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await _db.collection(_collection).doc(_documentId).set(
        {
          'dailyStartPdfPage': dailyStartPdfPage,
          'dailyPageCount': dailyPageCount,
          'pdfFileName': fileName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    _cachedSettings = settings;
    await _saveToPrefs(settings);
  }

  Future<PdfSettings> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final startPage = prefs.getInt(_prefsStartPageKey) ?? 4;
    final pageCount = prefs.getInt(_prefsPageCountKey) ?? 365;
    final fileName = prefs.getString(_prefsFileNameKey) ?? '365일 매일묵상말씀.pdf';

    return PdfSettings(
      dailyStartPdfPage: startPage,
      dailyPageCount: pageCount,
      pdfFileName: fileName,
    );
  }

  Future<void> _saveToPrefs(PdfSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsStartPageKey, settings.dailyStartPdfPage);
    await prefs.setInt(_prefsPageCountKey, settings.dailyPageCount);
    await prefs.setString(_prefsFileNameKey, settings.pdfFileName);
  }
}
