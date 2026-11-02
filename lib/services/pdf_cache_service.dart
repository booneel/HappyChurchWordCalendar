import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_config.dart';
import 'nas_api_client.dart';

class PdfCacheService {
  PdfCacheService._();
  static final PdfCacheService instance = PdfCacheService._();
  factory PdfCacheService() => instance;

  static const String storagePath = '365일 매일묵상말씀.pdf';
  static const String _cacheFileName = '365_daily_devotional.pdf';
  static const String _generationKey = 'cached_pdf_generation';
  static const String _lastCheckKey = 'cached_pdf_last_check';

  // Check the remote file when a new cache load starts. The metadata request
  // is small, and it prevents a user who missed a push notification from
  // seeing an old PDF for hours after reopening the app.
  static const Duration metadataCheckInterval = Duration.zero;
  static const Duration offlineProbeTimeout = Duration(seconds: 4);

  final NasApiClient _nas = NasApiClient.instance;

  FirebaseStorage get _storage => FirebaseStorage.instance;

  File? _memoryFile;
  Future<File>? _loading;
  bool _lastNasLoadSucceeded = false;

  bool get hasLoadedNasPdfFromServer => _lastNasLoadSucceeded;

  Future<File> preload() => getCachedPdf();

  Future<File> getCachedPdf({bool forceRefresh = false}) {
    if (!forceRefresh && _loading != null) return _loading!;

    final future = _load(forceRefresh: forceRefresh);
    if (!forceRefresh) _loading = future;
    return future;
  }

  Future<File> _load({required bool forceRefresh}) async {
    if (!forceRefresh && _memoryFile != null) {
      if (await _memoryFile!.exists()) return _memoryFile!;
    }

    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/pdf_cache');
    await cacheDir.create(recursive: true);

    final file = File('${cacheDir.path}/$_cacheFileName');
    final prefs = await SharedPreferences.getInstance();

    // A file can exist even when a previous download was interrupted or the
    // filesystem returned a damaged copy. Never treat existence as validity.
    if (await file.exists() && !await _isUsablePdf(file)) {
      await file.delete();
      await prefs.remove(_lastCheckKey);
      await prefs.remove(_generationKey);
      _memoryFile = null;
    }

    if (BackendConfig.useNas) {
      return _loadFromNas(file: file, prefs: prefs, forceRefresh: forceRefresh);
    }

    if (!forceRefresh && await file.exists()) {
      final lastCheckMillis = prefs.getInt(_lastCheckKey);

      if (lastCheckMillis != null) {
        final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckMillis);

        if (DateTime.now().difference(lastCheck) < metadataCheckInterval) {
          _memoryFile = file;
          return file;
        }
      }

      try {
        final ref = _storage.ref(storagePath);
        final metadata = await ref.getMetadata().timeout(offlineProbeTimeout);

        final remoteGeneration = metadata.generation;
        final localGeneration = prefs.getString(_generationKey);

        await prefs.setInt(
          _lastCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );

        if (remoteGeneration == null || remoteGeneration == localGeneration) {
          _memoryFile = file;
          return file;
        }

        await _download(ref, file);

        await prefs.setString(_generationKey, remoteGeneration);

        _memoryFile = file;
        return file;
      } catch (_) {
        // 네트워크가 없어도 기존 캐시가 있으면 사용합니다.
        _memoryFile = file;
        return file;
      }
    }

    final ref = _storage.ref(storagePath);
    final metadata = await ref.getMetadata();

    await _download(ref, file);

    if (metadata.generation != null) {
      await prefs.setString(_generationKey, metadata.generation!);
    }

    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

    _memoryFile = file;
    return file;
  }

  Future<File> _loadFromNas({
    required File file,
    required SharedPreferences prefs,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && await file.exists()) {
      final lastCheckMillis = prefs.getInt(_lastCheckKey);
      if (lastCheckMillis != null &&
          DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(lastCheckMillis),
              ) <
              metadataCheckInterval) {
        _memoryFile = file;
        return file;
      }
    }

    try {
      final candidate = File('${file.path}.candidate');
      final download = _downloadAndReplaceNas(file, candidate);
      if (forceRefresh) {
        await download;
      } else {
        await download.timeout(offlineProbeTimeout);
      }
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      _lastNasLoadSucceeded = true;
    } catch (_) {
      // NAS가 잠시 끊겨도 기존 캐시가 있으면 앱을 계속 사용할 수 있습니다.
      if (await file.exists()) {
        _lastNasLoadSucceeded = false;
        _memoryFile = file;
        return file;
      }
      rethrow;
    }
    _memoryFile = file;
    return file;
  }

  Future<void> refresh() async {
    _loading = null;
    _memoryFile = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await prefs.remove(_generationKey);

    await getCachedPdf(forceRefresh: true);
  }

  /// Marks the local copy as stale so the next PDF open checks the server.
  ///
  /// The notification callback can run while the app is in the background,
  /// so invalidating is safer than downloading the PDF from that callback.
  Future<void> invalidate() async {
    _loading = null;
    _memoryFile = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await prefs.remove(_generationKey);
  }

  Future<void> _download(Reference ref, File file) async {
    final candidate = File('${file.path}.candidate');
    try {
      await ref.writeToFile(candidate);
      if (!await _isUsablePdf(candidate)) {
        throw const FormatException('다운로드한 PDF 파일이 손상되었습니다.');
      }
      await _replaceFile(candidate, file);
    } finally {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<void> _downloadAndReplaceNas(File target, File candidate) async {
    try {
      await _nas.downloadPdf(candidate);
      if (!await _isUsablePdf(candidate)) {
        throw const FormatException('NAS에서 받은 PDF 파일이 손상되었습니다.');
      }
      await _replaceFile(candidate, target);
    } finally {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<void> _replaceFile(File candidate, File target) async {
    if (await target.exists()) await target.delete();
    await candidate.rename(target.path);
  }

  Future<bool> _isUsablePdf(File file) async {
    if (!await file.exists() || await file.length() < 8) return false;
    pdfrx.PdfDocument? document;
    try {
      document = await pdfrx.PdfDocument.openFile(file.path);
      return document.pages.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      await document?.dispose();
    }
  }
}
