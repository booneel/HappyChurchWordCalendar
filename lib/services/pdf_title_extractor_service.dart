import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfTitleExtractionResult {
  final int total;
  final int success;
  final int failed;

  const PdfTitleExtractionResult({
    required this.total,
    required this.success,
    required this.failed,
  });
}

class PdfTitleExtractorService {
  static const int dailyStartPdfPage = 4;
  static const int dailyPageCount = 365;
  static const String storageFileName = '365일 매일묵상말씀.pdf';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// PDF 4페이지부터 365일치를 읽어서
  /// Firestore의 pdf_pages/yyyy-MM-dd 문서에 page/title을 저장합니다.
  Future<PdfTitleExtractionResult> extractAndSaveAll({
    required int year,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    final yearStart = DateTime(year, 1, 1);
    final daysInYear =
        DateTime(year, 12, 31).difference(yearStart).inDays + 1;

    if (daysInYear != 365) {
      throw ArgumentError(
        '$year년은 윤년입니다. 현재 PDF는 365일 기준이라 자동 매핑할 수 없습니다.',
      );
    }

    onProgress?.call(0, dailyPageCount, 'Firebase Storage에서 PDF 주소를 가져오는 중...');

    final downloadUrl =
        await _storage.ref(storageFileName).getDownloadURL();

    onProgress?.call(0, dailyPageCount, 'PDF를 여는 중...');

    final document = await PdfDocument.openUri(Uri.parse(downloadUrl));

    try {
      final requiredLastPage = dailyStartPdfPage + dailyPageCount - 1;
      if (document.pages.length < requiredLastPage) {
        throw StateError(
          'PDF 페이지 수가 부족합니다. '
          '필요: $requiredLastPage페이지, 실제: ${document.pages.length}페이지',
        );
      }

      final batch = _db.batch();
      int success = 0;
      int failed = 0;

      for (int dayIndex = 0; dayIndex < dailyPageCount; dayIndex++) {
        final pdfPage = dailyStartPdfPage + dayIndex;
        final date = yearStart.add(Duration(days: dayIndex));

        onProgress?.call(
          dayIndex + 1,
          dailyPageCount,
          '${_dateKey(date)} · PDF $pdfPage 페이지 분석 중',
        );

        final page = document.pages[pdfPage - 1];

        String? title;

        try {
          // 구조화된 텍스트를 먼저 사용합니다.
          final structured = await page.loadStructuredText();
          title = _extractTitle(
            structured.fullText,
            fragments: structured.fragments.map((e) => e.text).toList(),
          );

          // 구조화 텍스트에서 못 찾았으면 raw text로 한 번 더 시도합니다.
          if (title == null || title.isEmpty) {
            final raw = await page.loadText();
            title = _extractTitle(raw?.fullText ?? '');
          }
        } catch (_) {
          // 특정 페이지만 텍스트 추출에 실패해도 전체 작업은 계속합니다.
          title = null;
        }

        final ref = _db.collection('pdf_pages').doc(_dateKey(date));

        final data = <String, dynamic>{
          'date': _dateKey(date),
          'page': pdfPage,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (title != null && title.isNotEmpty) {
          data['title'] = title;
          success++;
        } else {
          data['titleExtractionFailed'] = true;
          failed++;
        }

        batch.set(ref, data, SetOptions(merge: true));
      }

      onProgress?.call(
        dailyPageCount,
        dailyPageCount,
        'Firestore에 제목을 저장하는 중...',
      );

      await batch.commit();

      return PdfTitleExtractionResult(
        total: dailyPageCount,
        success: success,
        failed: failed,
      );
    } finally {
      await document.dispose();
    }
  }

  String? _extractTitle(
    String fullText, {
    List<String> fragments = const [],
  }) {
    final candidates = <String>[];

    // PDF의 읽기 순서가 유지된다면 fragment가 제목 탐지에 더 유리합니다.
    for (final fragment in fragments) {
      final normalized = _normalize(fragment);
      if (normalized.isNotEmpty) {
        candidates.add(normalized);
      }
    }

    for (final line in fullText.split(RegExp(r'[\r\n]+'))) {
      final normalized = _normalize(line);
      if (normalized.isNotEmpty) {
        candidates.add(normalized);
      }
    }

    // 중복 제거하되 원래 순서는 유지합니다.
    final unique = <String>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      if (seen.add(candidate)) {
        unique.add(candidate);
      }
    }

    for (final candidate in unique.take(30)) {
      if (_looksLikeTitle(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String _normalize(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeTitle(String value) {
    if (value.isEmpty) return false;

    // 제목은 한글을 포함해야 합니다.
    if (!RegExp(r'[가-힣]').hasMatch(value)) return false;

    // 날짜/성경구절/브랜드/본문 문장은 제외합니다.
    if (RegExp(r'\d').hasMatch(value)) return false;

    final upper = value.toUpperCase();
    if (upper.contains('HAPPY CHURCH')) return false;

    // 본문 문장처럼 긴 문자열은 제외합니다.
    if (value.length > 12) return false;

    // 제목은 보통 짧은 한두 단어이므로 공백이 너무 많은 것은 제외합니다.
    final words = value.split(' ').where((e) => e.isNotEmpty).toList();
    if (words.length > 2) return false;

    // 구두점이 많은 본문 조각 제외
    if (RegExp(r'[,:;.!?。、“”‘’]').hasMatch(value)) return false;

    // 한글 글자 수가 너무 적거나 너무 많은 경우 제외
    final hangulCount = RegExp(r'[가-힣]').allMatches(value).length;
    if (hangulCount < 2 || hangulCount > 10) return false;

    return true;
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
