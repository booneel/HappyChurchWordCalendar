import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
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

  static const Duration metadataCheckInterval = Duration(hours: 6);

  final NasApiClient _nas = NasApiClient.instance;

  FirebaseStorage get _storage => FirebaseStorage.instance;

  File? _memoryFile;
  Future<File>? _loading;

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

    if (BackendConfig.useNas) {
      return _loadFromNas(
        file: file,
        prefs: prefs,
        forceRefresh: forceRefresh,
      );
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
        final metadata = await ref.getMetadata();

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

        await prefs.setString(
          _generationKey,
          remoteGeneration,
        );

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
      await prefs.setString(
        _generationKey,
        metadata.generation!,
      );
    }

    await prefs.setInt(
      _lastCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );

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
      await _nas.downloadPdf(file);
      await prefs.setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // NAS가 잠시 끊겨도 기존 캐시가 있으면 앱을 계속 사용할 수 있습니다.
      if (await file.exists()) {
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
    await getCachedPdf(forceRefresh: true);
  }

  Future<void> _download(Reference ref, File file) async {
    if (await file.exists()) {
      await file.delete();
    }

    await ref.writeToFile(file);
  }
}
