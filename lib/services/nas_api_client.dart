import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'backend_config.dart';

/// Small HTTP client for a self-hosted DatePDF NAS API.
///
/// The API is intentionally boring: JSON for metadata and catalog/statistics,
/// and one PDF endpoint. This makes it possible to host it with Node, PHP,
/// Python/FastAPI, or a NAS vendor's reverse proxy.
class NasApiClient {
  NasApiClient._();

  static final NasApiClient instance = NasApiClient._();

  factory NasApiClient() => instance;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = BackendConfig.nasBaseUri;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final joined = '${base.path.replaceFirst(RegExp(r'/$'), '')}/$cleanPath';
    return base.replace(
      path: joined,
      queryParameters: query,
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (BackendConfig.nasToken.trim().isNotEmpty)
          'Authorization': 'Bearer ${BackendConfig.nasToken.trim()}',
      };

  Future<http.Response> get(String path, {Map<String, String>? query}) {
    return http.get(_uri(path, query), headers: _headers);
  }

  Future<http.Response> head(String path) {
    return http.head(_uri(path), headers: _headers);
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await get(path, query: query);
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
    final response = await http.put(
      _uri(path),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    _check(response);
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      _uri(path),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
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
        headers: _headers,
      );
      _check(fileResponse);
      bytes = fileResponse.bodyBytes;
    }

    if (bytes.isEmpty) throw const FormatException('NAS PDF가 비어 있습니다.');
    await target.writeAsBytes(bytes, flush: true);
  }

  Future<Map<String, dynamic>> uploadPdf(
    File file, {
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/pdf/current'));
    request.headers.addAll(_headers);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: fileName,
      ),
    );
    final response = await request.send();
    final result = await http.Response.fromStream(response);
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
