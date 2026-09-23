import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'date_page_mapper.dart';
import 'pdf_cache_service.dart';

class PdfTitleService {
  PdfTitleService._();
  static final PdfTitleService instance = PdfTitleService._();
  factory PdfTitleService() => instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final PdfCacheService _cache = PdfCacheService();

  PdfDocument? _document;
  Future<PdfDocument>? _documentFuture;

  Future<String?> getOrExtractTitle({
    required DateTime date,
    required int pdfPage,
  }) async {
    final key = _dateKey(date);

    // 1. Firestore가 정답 저장소
    final firestoreTitle = await _readFirestore(key);
    if (firestoreTitle != null) {
      await _saveLocal(key, firestoreTitle);
      return firestoreTitle;
    }

    // 2. 기기 로컬 캐시
    final localTitle = await _readLocal(key);
    if (localTitle != null) return localTitle;

    // 3. 실제 PDF 페이지에서 자동 추출
    final title = await _extractFromPage(pdfPage);
    if (title == null) return null;

    await _saveLocal(key, title);

    try {
      await _db.collection('pdf_pages').doc(key).set(
        {
          'date': key,
          'page': pdfPage,
          'title': title,
          'titleSource': 'auto-v3',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 쓰기 권한이 없더라도 로컬 제목은 계속 사용
    }

    return title;
  }

  Future<String?> getOrExtractTitleForPage(
    int pdfPage, {
    int? year,
  }) async {
    if (!DatePageMapper.isDailyPage(pdfPage)) return null;
    final date = DatePageMapper.dateForPdfPage(
      pdfPage,
      year: year ?? DateTime.now().year,
    );
    return getOrExtractTitle(date: date, pdfPage: pdfPage);
  }

  Future<String?> _readFirestore(String key) async {
    try {
      final doc = await _db.collection('pdf_pages').doc(key).get();
      final value = doc.data()?['title'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<PdfDocument> _getDocument() {
    if (_document != null) return Future.value(_document);
    if (_documentFuture != null) return _documentFuture!;

    _documentFuture = () async {
      final file = await _cache.getCachedPdf();
      final doc = await PdfDocument.openFile(file.path);
      _document = doc;
      return doc;
    }();

    return _documentFuture!;
  }

  Future<String?> _extractFromPage(int pdfPage) async {
    try {
      final document = await _getDocument();
      if (pdfPage < 1 || pdfPage > document.pages.length) return null;

      final page = document.pages[pdfPage - 1];

      // A. 실제 PDF 텍스트 + 위치정보로 먼저 판별
      final structuredTitle = await _extractStructuredTitle(page);
      if (structuredTitle != null) return structuredTitle;

      // B. 손글씨/벡터 글자인 경우 제목 부분만 고해상도 OCR
      if (Platform.isAndroid || Platform.isIOS) {
        final ocrTitle = await _extractTitleCropWithOcr(page);
        if (ocrTitle != null) return ocrTitle;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _extractStructuredTitle(PdfPage page) async {
    try {
      final text = await page.loadStructuredText();

      String? best;
      double bestScore = -999999;

      for (final fragment in text.fragments) {
        final candidate = _normalize(fragment.text);
        if (!_looksLikeTitle(candidate)) continue;

        final b = fragment.bounds;

        // PDF 좌표는 좌하단이 원점.
        // 화면 기준 위쪽 10~48% = PDF 좌표 중심 y 약 52~90%.
        final yRatio = b.center.y / page.height;
        if (yRatio < 0.52 || yRatio > 0.90) continue;

        final xRatio = b.center.x / page.width;
        if (xRatio < 0.15 || xRatio > 0.85) continue;

        // 큰 글자 + 중앙 배치 + 페이지 상단 중간 위치 선호
        double score = 0;
        score += b.height * 8;
        score -= (xRatio - 0.50).abs() * 100;
        score -= (yRatio - 0.70).abs() * 80;
        score -= candidate.length * 1.5;

        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      return best;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _extractTitleCropWithOcr(PdfPage page) async {
    TextRecognizer? recognizer;

    try {
      // 전체 페이지를 3배 해상도로 가정한 뒤
      // 제목이 있는 상단 중앙 부분만 렌더링합니다.
      final fullWidth = page.width * 3.0;
      final fullHeight = page.height * 3.0;

      final x = (fullWidth * 0.12).round();
      final y = (fullHeight * 0.12).round();
      final width = (fullWidth * 0.76).round();
      final height = (fullHeight * 0.38).round();

      final image = await page.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: 0xFFFFFFFF,
      );

      if (image == null) return null;

      ui.Image? uiImage;
      try {
        uiImage = await image.createImage();
        final data = await uiImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) return null;

        final input = InputImage.fromBitmap(
          bitmap: data.buffer.asUint8List(),
          width: uiImage.width,
          height: uiImage.height,
          rotation: 0,
        );

        recognizer = TextRecognizer(
          script: TextRecognitionScript.korean,
        );

        final result = await recognizer.processImage(input);
        return _bestOcrCandidate(
          result,
          width: uiImage.width.toDouble(),
          height: uiImage.height.toDouble(),
        );
      } finally {
        uiImage?.dispose();
        image.dispose();
      }
    } catch (_) {
      return null;
    } finally {
      await recognizer?.close();
    }
  }

  String? _bestOcrCandidate(
    RecognizedText result, {
    required double width,
    required double height,
  }) {
    String? best;
    double bestScore = -999999;

    for (final block in result.blocks) {
      for (final line in block.lines) {
        final candidate = _normalize(line.text);
        if (!_looksLikeTitle(candidate)) continue;

        final b = line.boundingBox;
        final xRatio = b.center.dx / width;
        final yRatio = b.center.dy / height;

        // crop 내부에서도 중앙 부근을 우선
        if (xRatio < 0.12 || xRatio > 0.88) continue;

        double score = 0;
        score += b.height * 6;
        score -= (xRatio - 0.50).abs() * 120;
        score -= (yRatio - 0.50).abs() * 35;
        score -= candidate.length * 2;

        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
    }

    return best;
  }

  bool _looksLikeTitle(String value) {
    if (value.length < 2 || value.length > 10) return false;
    if (!RegExp(r'[가-힣]').hasMatch(value)) return false;
    if (RegExp(r'\d').hasMatch(value)) return false;
    if (RegExp(r'[,.!?;:”“‘’/\\]').hasMatch(value)) return false;

    final upper = value.toUpperCase();
    if (upper.contains('HAPPY') || upper.contains('CHURCH')) {
      return false;
    }

    final words =
        value.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (words.length > 2) return false;

    final hangulCount = RegExp(r'[가-힣]').allMatches(value).length;
    return hangulCount >= 2 && hangulCount <= 8;
  }

  String _normalize(String value) => value
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<String?> _readLocal(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('pdf_title_$key');
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> _saveLocal(String key, String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pdf_title_$key', title);
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
