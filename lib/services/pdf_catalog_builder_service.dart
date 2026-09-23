import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

import 'date_page_mapper.dart';
import 'pdf_cache_service.dart';

class CatalogBuildResult {
  final int year;
  final Map<String, String> titles;
  final List<String> failedKeys;

  const CatalogBuildResult({
    required this.year,
    required this.titles,
    required this.failedKeys,
  });

  int get successCount => titles.length;
  int get failedCount => failedKeys.length;
}

class _PhrasePiece {
  final String text;
  final double left;
  final double centerY;
  final double height;

  const _PhrasePiece({
    required this.text,
    required this.left,
    required this.centerY,
    required this.height,
  });
}

class PdfCatalogBuilderService {
  final PdfCacheService _cache = PdfCacheService();

  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
  }

  Future<CatalogBuildResult> build({
    required int year,
    required void Function(
      int current,
      int total,
      String message,
    ) onProgress,
  }) async {
    _cancelRequested = false;

    final yearStart = DateTime(year, 1, 1);
    final dayCount =
        DateTime(year, 12, 31).difference(yearStart).inDays + 1;

    if (dayCount != 365) {
      throw ArgumentError(
        '$year년은 윤년입니다. 현재 PDF는 365일 기준입니다.',
      );
    }

    onProgress(0, 365, 'PDF 준비 중...');

    final file = await _cache.getCachedPdf();

    onProgress(0, 365, 'PDF 열기...');

    final document = await PdfDocument.openFile(file.path);

    final recognizer =
        (Platform.isAndroid || Platform.isIOS)
            ? TextRecognizer(
                script: TextRecognitionScript.korean,
              )
            : null;

    final titles = <String, String>{};
    final failed = <String>[];

    try {
      for (int index = 0;
          index < DatePageMapper.dailyPageCount;
          index++) {
        if (_cancelRequested) break;

        final date =
            yearStart.add(Duration(days: index));
        final key = DatePageMapper.monthDayKey(date);
        final pageNumber =
            DatePageMapper.dailyStartPdfPage + index;

        onProgress(
          index + 1,
          DatePageMapper.dailyPageCount,
          '$key · PDF $pageNumber 제목 분석 중',
        );

        if (pageNumber > document.pages.length) {
          failed.add(key);
          continue;
        }

        final page = document.pages[pageNumber - 1];

        // 1) PDF 실제 텍스트가 있으면 같은 줄의 조각들을 합칩니다.
        String? title =
            await _extractStructuredPhrase(page);

        // 2) 붓글씨/여러 폰트라면 OCR 요소를 한 줄로 재조합합니다.
        if (title == null && recognizer != null) {
          title = await _extractOcrPhrase(
            page,
            recognizer,
          );
        }

        if (title != null && title.trim().isNotEmpty) {
          titles[key] = title.trim();
        } else {
          failed.add(key);
        }
      }
    } finally {
      await recognizer?.close();
      await document.dispose();
    }

    return CatalogBuildResult(
      year: year,
      titles: titles,
      failedKeys: failed,
    );
  }

  Future<String?> _extractStructuredPhrase(
    PdfPage page,
  ) async {
    try {
      final structured = await page.loadStructuredText();

      final pieces = <_PhrasePiece>[];

      for (final fragment in structured.fragments) {
        final text = _normalize(fragment.text);
        if (!_canBeTitlePiece(text)) continue;

        final bounds = fragment.bounds;

        final xRatio = bounds.center.x / page.width;
        final yRatio = bounds.center.y / page.height;

        // 제목은 페이지 중앙 상단 영역.
        if (xRatio < 0.08 || xRatio > 0.92) continue;
        if (yRatio < 0.50 || yRatio > 0.86) continue;

        pieces.add(
          _PhrasePiece(
            text: text,
            left: bounds.left,
            centerY: yRatio,
            height: bounds.height / page.height,
          ),
        );
      }

      return _bestMergedPhrase(
        pieces,
        expectedY: 0.68,
        yTolerance: 0.075,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _extractOcrPhrase(
    PdfPage page,
    TextRecognizer recognizer,
  ) async {
    PdfImage? rendered;
    ui.Image? image;

    try {
      // 날짜와 제목만 포함하도록 상단 중앙을 크게 렌더링.
      // 본문 영역은 최대한 제외합니다.
      final fullWidth = page.width * 3.4;
      final fullHeight = page.height * 3.4;

      final cropX = (fullWidth * 0.05).round();
      final cropY = (fullHeight * 0.08).round();
      final cropWidth = (fullWidth * 0.90).round();
      final cropHeight = (fullHeight * 0.40).round();

      rendered = await page.render(
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: 0xFFFFFFFF,
      );

      if (rendered == null) return null;

      image = await rendered.createImage();

      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (bytes == null) return null;

      final input = InputImage.fromBitmap(
        bitmap: bytes.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        rotation: 0,
      );

      final result =
          await recognizer.processImage(input);

      final pieces = <_PhrasePiece>[];

      // TextLine 전체만 보지 않고 element 단위로 수집합니다.
      // "하나님의" / "뜻" / "을 행하는 자" 처럼 폰트가 달라
      // 여러 조각으로 분리되어도 같은 줄이면 다시 합칠 수 있습니다.
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final text = _normalize(element.text);

            if (!_canBeTitlePiece(text)) continue;

            final bounds = element.boundingBox;

            final xRatio =
                bounds.center.dx / image.width;
            final yRatio =
                bounds.center.dy / image.height;

            // crop 안에서 제목 예상 위치.
            if (xRatio < 0.04 || xRatio > 0.96) {
              continue;
            }

            if (yRatio < 0.30 || yRatio > 0.84) {
              continue;
            }

            pieces.add(
              _PhrasePiece(
                text: text,
                left: bounds.left / image.width,
                centerY: yRatio,
                height: bounds.height / image.height,
              ),
            );
          }

          // element가 하나도 없는 특수 OCR 결과를 대비해 line도 후보로 넣음.
          if (line.elements.isEmpty) {
            final text = _normalize(line.text);
            if (!_canBeTitlePiece(text)) continue;

            final bounds = line.boundingBox;
            final yRatio =
                bounds.center.dy / image.height;

            if (yRatio < 0.30 || yRatio > 0.84) {
              continue;
            }

            pieces.add(
              _PhrasePiece(
                text: text,
                left: bounds.left / image.width,
                centerY: yRatio,
                height: bounds.height / image.height,
              ),
            );
          }
        }
      }

      final merged = _bestMergedPhrase(
        pieces,
        expectedY: 0.60,
        yTolerance: 0.14,
      );

      if (merged != null) {
        return merged;
      }

      // 마지막 fallback: OCR line 자체가 이미 완전한 문구인 경우.
      String? bestLine;
      double bestScore = -999999;

      for (final block in result.blocks) {
        for (final line in block.lines) {
          final value = _normalize(line.text);

          if (!_looksLikeCompleteTitle(value)) {
            continue;
          }

          final y =
              line.boundingBox.center.dy / image.height;

          if (y < 0.30 || y > 0.84) continue;

          final score =
              line.boundingBox.height -
                  (y - 0.60).abs() * 100;

          if (score > bestScore) {
            bestScore = score;
            bestLine = value;
          }
        }
      }

      return bestLine;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      rendered?.dispose();
    }
  }

  String? _bestMergedPhrase(
    List<_PhrasePiece> pieces, {
    required double expectedY,
    required double yTolerance,
  }) {
    if (pieces.isEmpty) return null;

    final remaining = [...pieces]
      ..sort((a, b) => a.centerY.compareTo(b.centerY));

    final groups = <List<_PhrasePiece>>[];

    for (final piece in remaining) {
      List<_PhrasePiece>? target;

      for (final group in groups) {
        final avgY = group
                .map((e) => e.centerY)
                .reduce((a, b) => a + b) /
            group.length;

        if ((piece.centerY - avgY).abs() <=
            yTolerance) {
          target = group;
          break;
        }
      }

      if (target == null) {
        groups.add([piece]);
      } else {
        target.add(piece);
      }
    }

    String? best;
    double bestScore = -999999;

    for (final group in groups) {
      group.sort((a, b) => a.left.compareTo(b.left));

      final phrase = _smartJoin(
        group.map((e) => e.text).toList(),
      );

      if (!_looksLikeCompleteTitle(phrase)) {
        continue;
      }

      final avgY = group
              .map((e) => e.centerY)
              .reduce((a, b) => a + b) /
          group.length;

      final avgHeight = group
              .map((e) => e.height)
              .reduce((a, b) => a + b) /
          group.length;

      final hangulCount =
          RegExp(r'[가-힣]').allMatches(phrase).length;

      double score = 0;

      // 한 단어만 고르는 것보다 여러 의미 있는 조각이 합쳐진 문구를 선호.
      score += hangulCount * 3.5;
      score += group.length * 8;
      score += avgHeight * 200;
      score -= (avgY - expectedY).abs() * 100;

      // 너무 긴 본문 문장은 제외되지만,
      // "하나님의 뜻을 행하는 자" 정도는 충분히 허용.
      if (phrase.length >= 5 && phrase.length <= 22) {
        score += 20;
      }

      if (score > bestScore) {
        bestScore = score;
        best = phrase;
      }
    }

    return best;
  }

  String _smartJoin(List<String> pieces) {
    final unique = <String>[];

    for (final piece in pieces) {
      final normalized = _normalize(piece);
      if (normalized.isEmpty) continue;

      if (unique.isEmpty ||
          unique.last != normalized) {
        unique.add(normalized);
      }
    }

    var value = unique.join(' ');

    // OCR이 "뜻" + "을"처럼 조사만 별도 element로 분리할 때 복원.
    const particles = [
      '은',
      '는',
      '이',
      '가',
      '을',
      '를',
      '의',
      '에',
      '도',
      '와',
      '과',
      '로',
      '만',
      '께',
      '서',
    ];

    for (final particle in particles) {
      value = value.replaceAllMapped(
        RegExp('([가-힣])\\s+$particle(?=\\s|\$)'),
        (match) => '${match.group(1)}$particle',
      );
    }

    // OCR 결과에서 불필요한 다중 공백 정리.
    return _normalize(value);
  }

  bool _canBeTitlePiece(String value) {
    if (value.isEmpty || value.length > 18) {
      return false;
    }

    if (!RegExp(r'[가-힣]').hasMatch(value)) {
      return false;
    }

    if (RegExp(r'\d').hasMatch(value)) {
      return false;
    }

    final upper = value.toUpperCase();

    if (upper.contains('HAPPY') ||
        upper.contains('CHURCH')) {
      return false;
    }

    if (RegExp(r'[,.!?;:“”‘’]').hasMatch(value)) {
      return false;
    }

    return true;
  }

  bool _looksLikeCompleteTitle(String value) {
    final normalized = _normalize(value);

    if (normalized.length < 2 ||
        normalized.length > 30) {
      return false;
    }

    if (!RegExp(r'[가-힣]').hasMatch(normalized)) {
      return false;
    }

    if (RegExp(r'\d').hasMatch(normalized)) {
      return false;
    }

    if (RegExp(r'[.!?;:“”‘’]').hasMatch(normalized)) {
      return false;
    }

    final hangulCount =
        RegExp(r'[가-힣]').allMatches(normalized).length;

    if (hangulCount < 2 || hangulCount > 24) {
      return false;
    }

    // 본문처럼 너무 많은 어절은 제외.
    final words = normalized
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();

    return words.length <= 7;
  }

  String _normalize(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
