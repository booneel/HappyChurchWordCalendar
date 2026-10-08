import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backend_config.dart';

/// Small HTTP client for a self-hosted TheWordCalendar NAS API.
///
/// The API is intentionally boring: JSON for metadata and catalog/statistics,
/// and one PDF endpoint. This makes it possible to host it with Node, PHP,
/// Python/FastAPI, or a NAS vendor's reverse proxy.
class NasApiClient {
  NasApiClient._();

  static final NasApiClient instance = NasApiClient._();

  factory NasApiClient() => instance;

  static const _requestTimeout = Duration(seconds: 15);
  static const _maxAttempts = 3;
  static final ValueNotifier<bool?> serverReachability = ValueNotifier(null);
  String? _adminToken;

  void setAdminToken(String? value) => _adminToken = value;
  bool get hasAdminToken => _adminToken != null;
  bool get isServerReachable => serverReachability.value == true;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = BackendConfig.nasBaseUri;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final joined = '${base.path.replaceFirst(RegExp(r'/$'), '')}/$cleanPath';
    return base.replace(
      path: joined,
      queryParameters: query,
    );
  }

  Map<String, String> _headers({bool admin = false}) => {
        'Accept': 'application/json',
        if (admin && _adminToken != null)
          'Authorization': 'Bearer $_adminToken'
        else if (BackendConfig.nasToken.trim().isNotEmpty)
          'Authorization': 'Bearer ${BackendConfig.nasToken.trim()}',
      };

  Future<bool> verifyAdminToken(String candidate) async {
    late final http.Response response;
    try {
      response = await http.get(
        _uri('/api/admin/check'),
        headers: {'Authorization': 'Bearer $candidate'},
      ).timeout(_requestTimeout);
      serverReachability.value = true;
    } catch (_) {
      serverReachability.value = false;
      rethrow;
    }
    if (response.statusCode == 200) {
      _adminToken = candidate;
      return true;
    }
    return false;
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request,
  ) async {
    Object? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final response = await request();
        serverReachability.value = true;
        if (!_isRetryableStatus(response.statusCode) ||
            attempt == _maxAttempts - 1) {
          return response;
        }
      } catch (error) {
        lastError = error;
        if (attempt == _maxAttempts - 1 || !_isRetryableError(error)) {
          serverReachability.value = false;
          rethrow;
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }

    serverReachability.value = false;
    throw lastError ?? const HttpException('NAS 요청이 실패했습니다.');
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  bool _isRetryableError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException;
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? query,
    bool admin = false,
  }) {
    return _requestWithRetry(
      () => http
          .get(_uri(path, query), headers: _headers(admin: admin))
          .timeout(_requestTimeout),
    );
  }

  Future<http.Response> head(String path) {
    return _requestWithRetry(
      () => http.head(_uri(path), headers: _headers()).timeout(_requestTimeout),
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool admin = false,
  }) async {
    final response = await get(path, query: query, admin: admin);
    _check(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('NAS 응답이 JSON 객체가 아닙니다.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _requestWithRetry(
      () => http
          .put(
            _uri(path),
            headers: {
              ..._headers(admin: true),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout),
    );
    _check(response);
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<void> delete(String path, {bool admin = true}) async {
    final response = await _requestWithRetry(
      () => http
          .delete(_uri(path), headers: _headers(admin: admin))
          .timeout(_requestTimeout),
    );
    _check(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _requestWithRetry(
      () => http
          .post(
            _uri(path),
            headers: {
              ..._headers(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout),
    );
    _check(response);
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<void> downloadPdf(File target) async {
    final response = await get('/api/pdf/current');
    _check(response);

    var bytes = response.bodyBytes;
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final decoded = jsonDecode(utf8.decode(bytes));
      final url = decoded is Map ? decoded['downloadUrl']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw const FormatException('NAS PDF 응답에 downloadUrl이 없습니다.');
      }
      final fileResponse = await http.get(
        Uri.parse(url),
        headers: _headers(),
      );
      _check(fileResponse);
      bytes = fileResponse.bodyBytes;
    }

    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('NAS PDF 응답이 유효한 PDF가 아닙니다.');
    }
    final temporary = File('${target.path}.download');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Map<String, dynamic>> uploadPdf(
    File file, {
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/pdf/current'));
    request.headers.addAll(_headers(admin: true));
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: fileName,
      ),
    );
    late final http.Response result;
    try {
      final response = await request.send();
      result = await http.Response.fromStream(response);
      serverReachability.value = true;
    } catch (_) {
      serverReachability.value = false;
      rethrow;
    }
    _check(result);
    if (result.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(result.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'NAS API ${response.statusCode}: ${response.reasonPhrase ?? ''}',
      );
    }
  }
}
