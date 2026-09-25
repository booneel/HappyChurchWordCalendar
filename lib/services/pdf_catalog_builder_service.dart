import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

import 'date_page_mapper.dart';
import 'pdf_cache_service.dart';

class ExtractedTitleInfo {
  final String title;
  final double confidence;

  const ExtractedTitleInfo({required this.title, required this.confidence});

  bool get isLowConfidence => confidence < 0.80;
}

class CatalogBuildResult {
  final int year;
  final Map<String, String> titles;
  final Map<String, double> confidences;
  final List<String> lowConfidenceKeys;
  final List<String> failedKeys;

  const CatalogBuildResult({
    required this.year,
    required this.titles,
    required this.confidences,
    required this.lowConfidenceKeys,
    required this.failedKeys,
  });

  int get successCount => titles.length;
  int get lowConfidenceCount => lowConfidenceKeys.length;
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

class _LayoutLine {
  final List<_PhrasePiece> pieces;
  final double centerY;
  final double top;
  final double bottom;
  final double height;

  const _LayoutLine({
    required this.pieces,
    required this.centerY,
    required this.top,
    required this.bottom,
    required this.height,
  });

  String get text => pieces.map((piece) => piece.text).join(' ');
}

class PdfCatalogBuilderService {
  final PdfCacheService _cache = PdfCacheService();

  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
  }

  Future<CatalogBuildResult> build({
    required int year,
    required void Function(int current, int total, String message) onProgress,
  }) async {
    _cancelRequested = false;

    final yearStart = DateTime(year, 1, 1);
    final dayCount = DateTime(year, 12, 31).difference(yearStart).inDays + 1;

    if (dayCount != 365) {
      throw ArgumentError('$year년은 윤년입니다. 현재 PDF는 365일 기준입니다.');
    }

    onProgress(0, 365, 'PDF 준비 중...');

    final file = await _cache.getCachedPdf();

    onProgress(0, 365, 'PDF 열기...');

    final document = await PdfDocument.openFile(file.path);

    TextRecognizer? recognizer;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        recognizer = TextRecognizer(script: TextRecognitionScript.korean);
      } catch (_) {
        recognizer = null;
      }
    }

    final titles = <String, String>{};
    final confidences = <String, double>{};
    final lowConfidenceKeys = <String>[];
    final failed = <String>[];

    try {
      for (int index = 0; index < DatePageMapper.dailyPageCount; index++) {
        if (_cancelRequested) break;

        final date = yearStart.add(Duration(days: index));
        final key = DatePageMapper.monthDayKey(date);
        final pageNumber = DatePageMapper.dailyStartPdfPage + index;

        onProgress(
          index + 1,
          DatePageMapper.dailyPageCount,
          '$key · PDF $pageNumber 제목 및 레이아웃 문맥 분석 중',
        );

        if (pageNumber > document.pages.length) {
          failed.add(key);
          continue;
        }

        try {
          final page = document.pages[pageNumber - 1];

          // 1. PDF 레이아웃 구조 분석 (날짜 줄 바로 아래, 본문 위)
          ExtractedTitleInfo? info = await _extractTitleWithContext(page);

          // 2. OCR 요소를 통한 시각적 보완 및 한 문장 조합
          if ((info == null || info.confidence < 0.90) && recognizer != null) {
            final ocrInfo = await _extractOcrTitleWithContext(page, recognizer);
            if (ocrInfo != null &&
                (info == null || ocrInfo.confidence > info.confidence)) {
              info = ocrInfo;
            }
          }

          if (info != null && info.title.trim().isNotEmpty) {
            final cleanTitle = info.title.trim();
            titles[key] = cleanTitle;
            confidences[key] = info.confidence;

            if (info.isLowConfidence) {
              lowConfidenceKeys.add(key);
            }
          } else {
            failed.add(key);
          }
        } catch (_) {
          failed.add(key);
        }

        // 메모리 해제 및 이벤트 루프 양보 (앱 튕김 방지)
        await Future.delayed(const Duration(milliseconds: 15));
      }
    } finally {
      await recognizer?.close();
      await document.dispose();
    }

    return CatalogBuildResult(
      year: year,
      titles: titles,
      confidences: confidences,
      lowConfidenceKeys: lowConfidenceKeys,
      failedKeys: failed,
    );
  }

  /// PDF 텍스트 구조 분석 (날짜 줄 -> 제목 -> 성경 본문 관계)
  Future<ExtractedTitleInfo?> _extractTitleWithContext(PdfPage page) async {
    try {
      final structured = await page.loadStructuredText();
      final pieces = <_PhrasePiece>[];

      for (final fragment in structured.fragments) {
        final text = _normalize(fragment.text);
        if (text.isEmpty) continue;

        final bounds = fragment.bounds;
        pieces.add(
          _PhrasePiece(
            text: text,
            left: bounds.left / page.width,
            centerY: bounds.center.y / page.height,
            height: bounds.height / page.height,
          ),
        );
      }

      final lines = _groupLayoutLines(pieces);
      ExtractedTitleInfo? best;

      void consider(ExtractedTitleInfo? candidate) {
        if (candidate == null || candidate.title.trim().isEmpty) return;
        if (best == null || candidate.confidence > best!.confidence) {
          best = candidate;
        }
      }

      consider(_extractTitleFromLayout(lines));
      consider(_extractRankedLayoutCandidate(lines));
      consider(_extractTitleFromPlainText(structured.fullText));

      // 일부 PDF는 텍스트 순서만 제공하므로, 마지막으로 위치 기반 후보를 시도합니다.
      final fallbackPieces = pieces.where((piece) {
        return piece.centerY >= 0.48 &&
            piece.centerY <= 0.88 &&
            piece.left >= 0.08 &&
            piece.left <= 0.92 &&
            _canBeTitlePiece(piece.text);
      }).toList();
      final merged = _bestMergedPhrase(
        fallbackPieces,
        expectedY: 0.68,
        yTolerance: 0.04,
      );
      if (merged != null && merged.isNotEmpty) {
        consider(ExtractedTitleInfo(title: merged, confidence: 0.55));
      }

      return best;
    } catch (_) {}

    return null;
  }

  ExtractedTitleInfo? _extractTitleFromPlainText(String fullText) {
    final lines = fullText
        .split(RegExp(r'[\r\n]+'))
        .map(_normalize)
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;

    final dateIndex = lines.indexWhere(_isDateText);
    final startIndex = dateIndex < 0 ? 0 : dateIndex + 1;
    final scanCount = dateIndex < 0 ? 12 : 8;

    final titleLines = <String>[];
    for (final line in lines.skip(startIndex).take(scanCount)) {
      if (_isHappyChurch(line) || _isScriptureReference(line)) continue;
      if (_isLikelyBodyLine(line, 0)) {
        if (titleLines.isNotEmpty) break;
        continue;
      }
      if (!_canBeTitleLine(line)) {
        if (titleLines.isNotEmpty) break;
        continue;
      }

      titleLines.add(line);
      if (titleLines.length == 3) break;
    }

    if (titleLines.isEmpty) return null;

    final title = _smartJoin(titleLines);
    if (!_canBeTitleLine(title)) return null;

    return ExtractedTitleInfo(
      title: title,
      confidence: dateIndex < 0
          ? 0.48
          : titleLines.length == 1
              ? 0.58
              : 0.63,
    );
  }

  List<_LayoutLine> _groupLayoutLines(List<_PhrasePiece> pieces) {
    final sorted = [...pieces]..sort((a, b) => b.centerY.compareTo(a.centerY));
    final groups = <List<_PhrasePiece>>[];

    for (final piece in sorted) {
      List<_PhrasePiece>? target;
      for (final group in groups) {
        final averageY =
            group.map((e) => e.centerY).reduce((a, b) => a + b) / group.length;
        final averageHeight =
            group.map((e) => e.height).reduce((a, b) => a + b) / group.length;
        final tolerance = (averageHeight * 0.65).clamp(0.008, 0.035);
        if ((piece.centerY - averageY).abs() <= tolerance) {
          target = group;
          break;
        }
      }
      (target ??= <_PhrasePiece>[]).add(piece);
      if (!groups.contains(target)) groups.add(target);
    }

    return groups.map((group) {
      group.sort((a, b) => a.left.compareTo(b.left));
      final centerY =
          group.map((e) => e.centerY).reduce((a, b) => a + b) / group.length;
      final height =
          group.map((e) => e.height).reduce((a, b) => a + b) / group.length;
      return _LayoutLine(
        pieces: group,
        centerY: centerY,
        top: centerY + height / 2,
        bottom: centerY - height / 2,
        height: height,
      );
    }).toList()
      ..sort((a, b) => b.centerY.compareTo(a.centerY));
  }

  ExtractedTitleInfo? _extractTitleFromLayout(List<_LayoutLine> lines) {
    if (lines.isEmpty) return null;

    // PDF 텍스트 좌표의 원점은 PDF 제작 방식에 따라 위/아래가 다를 수
    // 있습니다. 날짜를 기준으로 양쪽 읽기 방향을 모두 시도하고, 문맥
    // 점수가 높은 결과를 선택합니다.
    final directions = [
      [...lines]..sort((a, b) => b.centerY.compareTo(a.centerY)),
      [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY)),
    ];
    ExtractedTitleInfo? best;
    for (final ordered in directions) {
      final candidate = _extractTitleFromOrderedLayout(ordered);
      if (candidate != null &&
          (best == null || candidate.confidence > best.confidence)) {
        best = candidate;
      }
    }
    return best;
  }

  ExtractedTitleInfo? _extractRankedLayoutCandidate(
    List<_LayoutLine> lines,
  ) {
    if (lines.isEmpty) return null;

    final ordered = [...lines]..sort((a, b) => b.centerY.compareTo(a.centerY));
    final dateLines = ordered.where((line) => _isDateText(line.text)).toList();
    final bodyHeights = ordered
        .where((line) => _isLikelyBodyLine(line.text, line.height))
        .map((line) => line.height)
        .where((height) => height > 0)
        .toList()
      ..sort();
    final typicalBodyHeight =
        bodyHeights.isEmpty ? 0.02 : bodyHeights[bodyHeights.length ~/ 2];

    ExtractedTitleInfo? best;
    var bestScore = -double.infinity;

    for (var start = 0; start < ordered.length; start++) {
      for (var length = 1; length <= 2; length++) {
        final end = start + length;
        if (end > ordered.length) break;

        final group = ordered.sublist(start, end);
        if (group.length == 2) {
          final gap = (group[0].centerY - group[1].centerY).abs();
          if (gap > (group[0].height * 3.4).clamp(0.035, 0.14)) {
            break;
          }
        }

        final phrase = _smartJoin(group.map((line) => line.text).toList());
        if (!_canBeTitleLine(phrase) ||
            _isLikelyBodyLine(phrase, group.first.height)) {
          continue;
        }

        final averageY =
            group.map((line) => line.centerY).reduce((a, b) => a + b) /
                group.length;
        final averageHeight =
            group.map((line) => line.height).reduce((a, b) => a + b) /
                group.length;
        final nearestDateGap = dateLines.isEmpty
            ? 0.0
            : dateLines
                .map((line) => (line.centerY - averageY).abs())
                .reduce((a, b) => a < b ? a : b);

        if (dateLines.isNotEmpty &&
            nearestDateGap < dateLines.first.height * 0.45) {
          continue;
        }

        final heightRatio = averageHeight / typicalBodyHeight;
        final heightScore = ((heightRatio - 0.85) * 0.18).clamp(-0.08, 0.18);
        final dateScore = dateLines.isEmpty
            ? 0.0
            : (0.24 - nearestDateGap).clamp(0.0, 0.24) * 0.85;
        final lengthScore =
            phrase.length >= 3 && phrase.length <= 32 ? 0.10 : 0.0;
        final lineScore = group.length == 1 ? 0.04 : 0.08;
        final score = 0.45 + heightScore + dateScore + lengthScore + lineScore;

        if (score > bestScore) {
          bestScore = score;
          best = ExtractedTitleInfo(
            title: phrase,
            confidence: score.clamp(0.45, 0.82),
          );
        }
      }
    }

    return best;
  }

  ExtractedTitleInfo? _extractTitleFromOrderedLayout(List<_LayoutLine> lines) {
    if (lines.isEmpty) return null;

    final dateIndex = lines.indexWhere((line) => _isDateText(line.text));
    if (dateIndex < 0) return null;

    final titleLines = <_LayoutLine>[];
    final dateLine = lines[dateIndex];
    final following = lines.skip(dateIndex + 1).toList();

    for (var lineIndex = 0; lineIndex < following.take(8).length; lineIndex++) {
      final line = following[lineIndex];
      final text = _normalize(line.text);
      if (text.isEmpty || _isHappyChurch(text) || _isScriptureReference(text)) {
        continue;
      }
      if (titleLines.isNotEmpty &&
          line.height < titleLines.first.height * 0.72) {
        // 본문은 제목보다 작은 글자로 여러 줄 배치되는 것이 일반적입니다.
        break;
      }
      if (_isLikelyBodyLine(text, line.height)) {
        if (titleLines.isNotEmpty) break;
        continue;
      }
      if (_looksLikeParagraphStart(following, lineIndex)) {
        if (titleLines.isNotEmpty) break;
        continue;
      }
      if (!_canBeTitleLine(text)) {
        if (titleLines.isNotEmpty) break;
        continue;
      }

      // 제목은 날짜 바로 아래에 있으며, 본문보다 큰 글자로 배치되는 경우가 많습니다.
      final gapFromDate = (dateLine.centerY - line.centerY).abs();
      if (gapFromDate < dateLine.height * 0.45) continue;
      if (titleLines.isNotEmpty) {
        final previous = titleLines.last;
        final gap = (previous.centerY - line.centerY).abs();
        if (gap > (previous.height * 2.8).clamp(0.035, 0.12)) break;
      }
      titleLines.add(line);
      if (titleLines.length == 3) break;
    }

    if (titleLines.isEmpty) return null;

    final title = _smartJoin(titleLines.map((line) => line.text).toList());
    if (!_canBeTitleLine(title)) return null;

    var nextBody = titleLines.last;
    var hasBodyLine = false;
    for (final line in following) {
      if (!titleLines.contains(line) &&
          _isLikelyBodyLine(line.text, line.height)) {
        nextBody = line;
        hasBodyLine = true;
        break;
      }
    }
    final heightRatio =
        titleLines.map((e) => e.height).reduce((a, b) => a + b) /
            titleLines.length /
            (nextBody.height == 0 ? 1 : nextBody.height);
    final lengthScore = title.length <= 45 ? 0.08 : -0.08;
    final lineScore = titleLines.length <= 2 ? 0.08 : 0.0;
    final confidence = ((hasBodyLine ? 0.74 : 0.62) +
            (heightRatio - 1.0).clamp(0.0, 0.18) +
            lengthScore +
            lineScore)
        .clamp(0.45, 0.98);

    return ExtractedTitleInfo(title: title, confidence: confidence);
  }

  bool _looksLikeParagraphStart(List<_LayoutLine> lines, int index) {
    final line = lines[index];
    final text = _normalize(line.text);
    if (text.length < 14 || index + 1 >= lines.length) return false;

    final next = lines[index + 1];
    final nextText = _normalize(next.text);
    if (nextText.isEmpty || _isHappyChurch(nextText)) return false;

    final heightRatio = next.height / (line.height == 0 ? 1 : line.height);
    final closeInLineSpacing = (next.centerY - line.centerY).abs() <=
        (line.height * 3.2).clamp(0.04, 0.18);
    final aligned =
        (next.pieces.first.left - line.pieces.first.left).abs() < 0.12;

    // 본문은 같은 크기의 긴 줄이 연속되고 시작 위치도 비슷합니다.
    // 이 조건을 만족하면 첫 줄을 제목으로 채택하지 않습니다.
    return heightRatio >= 0.62 &&
        heightRatio <= 1.55 &&
        closeInLineSpacing &&
        aligned;
  }

  /// OCR 시각 레이아웃 기반 분석 (손글씨 / 다양한 폰트 한 문구 복원)
  Future<ExtractedTitleInfo?> _extractOcrTitleWithContext(
    PdfPage page,
    TextRecognizer recognizer,
  ) async {
    PdfImage? rendered;
    ui.Image? image;

    try {
      final fullWidth = page.width * 1.5;
      final fullHeight = page.height * 1.5;

      final cropX = (fullWidth * 0.05).round();
      // 날짜와 제목, 본문 첫 줄까지 함께 렌더링해 관계를 판단합니다.
      // 기존 40% 높이는 제목이 날짜 아래에 있는 레이아웃에서 제목을 잘라냈습니다.
      final cropY = (fullHeight * 0.04).round();
      final cropWidth = (fullWidth * 0.90).round();
      final cropHeight = (fullHeight * 0.66).round();

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

      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (bytes == null) return null;

      final input = InputImage.fromBitmap(
        bitmap: bytes.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        rotation: 0,
      );

      final result = await recognizer.processImage(input);

      final pieces = <_PhrasePiece>[];

      for (final block in result.blocks) {
        for (final line in block.lines) {
          final text = _normalize(line.text);
          if (!_isDateText(text) &&
              (!_canBeTitleLine(text) || _isLikelyBodyLine(text, 0))) {
            continue;
          }

          final bounds = line.boundingBox;
          final xRatio = bounds.center.dx / image.width;
          final yRatio = bounds.center.dy / image.height;

          if (xRatio < 0.04 || xRatio > 0.96) continue;
          if (yRatio < 0.18 || yRatio > 0.88) continue;

          pieces.add(
            _PhrasePiece(
              text: text,
              left: bounds.left / image.width,
              // OCR 좌표는 화면 위쪽이 0이므로 PDF 구조 분석과 동일하게 뒤집습니다.
              centerY: 1 - yRatio,
              height: bounds.height / image.height,
            ),
          );
        }
      }

      final contextual = _extractTitleFromLayout(_groupLayoutLines(pieces));
      if (contextual != null) {
        return contextual;
      }

      final merged = _bestMergedPhrase(
        pieces,
        expectedY: 0.56,
        yTolerance: 0.07,
      );

      if (merged != null && merged.isNotEmpty) {
        final confidence = merged.length <= 45 ? 0.62 : 0.50;
        return ExtractedTitleInfo(title: merged, confidence: confidence);
      }
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      rendered?.dispose();
    }

    return null;
  }

  bool _isDateText(String value) {
    final text = _normalize(value);
    if (RegExp(r'(^|\s)\d{1,2}\s*월\s*\d{1,2}\s*일?(\s|$)').hasMatch(text) ||
        RegExp(r'(^|\s)\d{1,2}\s*[.-]\s*\d{1,2}(\s|$)').hasMatch(text)) {
      return true;
    }
    return RegExp(r'(^|\s)\d{1,2}\s*/\s*\d{1,2}(\s|$)').hasMatch(text);
  }

  bool _isHappyChurch(String value) {
    final upper = value.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    return upper.contains('HAPPYCHURCH');
  }

  bool _isScriptureReference(String value) {
    final text = _normalize(value);
    if (RegExp(r'\b\d{1,3}\s*장\s*\d{1,3}\s*절?\b').hasMatch(text)) {
      return true;
    }
    if (RegExp(r'\b\d{1,3}\s*[:：]\s*\d{1,3}\b').hasMatch(text)) {
      return true;
    }
    return RegExp(
      r'^(창세기|출애굽기|레위기|민수기|신명기|여호수아|사사기|룻기|사무엘|열왕기|역대|에스라|느헤미야|에스더|욥기|시편|잠언|전도서|아가|이사야|예레미야|예레미야애가|에스겔|다니엘|호세아|요엘|아모스|오바댜|요나|미가|나훔|하박국|스바냐|학개|스가랴|말라기|마태복음|마가복음|누가복음|요한복음|사도행전|로마서|고린도전서|고린도후서|갈라디아서|에베소서|빌립보서|골로새서|데살로니가|디모데|디도서|빌레몬서|히브리서|야고보서|베드로|요한일서|요한이서|요한삼서|유다서|요한계시록|[가-힣]{1,4})\s*\d{1,3}\s*[:：]\s*\d{1,3}',
    ).hasMatch(text);
  }

  bool _isLikelyBodyLine(String value, double height) {
    final text = _normalize(value);
    if (text.isEmpty || _isDateText(text) || _isHappyChurch(text)) return true;
    if (_isScriptureReference(text)) return true;
    if (RegExp(r'[.,!?;:“”‘’"()]').hasMatch(text)) return true;
    if (text.length > 36 || text.split(RegExp(r'\s+')).length > 10) return true;
    final hangulCount = RegExp(r'[\uAC00-\uD7A3]').allMatches(text).length;
    if (hangulCount >= 26) return true;
    const bodyStarts = [
      '근신하라',
      '깨어라',
      '삼킬',
      '찾나',
      '기록되었으되',
      '예수께서',
      '가라사대',
      '이르시되',
      '무릇',
      '너희는',
      '내가',
      '네가',
      '저희가',
      '주께서',
      '사람이',
      '누구든지',
      '그런즉',
      '오직',
    ];
    if (bodyStarts.any(text.startsWith)) return true;
    return false;
  }

  bool _canBeTitleLine(String value) {
    final text = _normalize(value);
    if (text.length < 2 || text.length > 60) return false;
    if (!RegExp(r'[가-힣]').hasMatch(text)) return false;
    if (_isDateText(text) ||
        _isHappyChurch(text) ||
        _isScriptureReference(text)) {
      return false;
    }
    if (RegExp(r'[,.!?;:“”‘’"()]').hasMatch(text)) return false;
    if (text.split(RegExp(r'\s+')).length > 10) return false;
    return true;
  }

  /// 짧은 묵상 제목 단어/구문 판별 (본문 및 성경구절 배제)
  bool _looksLikeDevotionalTitleWord(String line) {
    return _canBeTitleLine(line) && !_isLikelyBodyLine(line, 0);
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
        final avgY =
            group.map((e) => e.centerY).reduce((a, b) => a + b) / group.length;

        if ((piece.centerY - avgY).abs() <= yTolerance) {
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

      final phrase = _smartJoin(group.map((e) => e.text).toList());

      if (!_looksLikeDevotionalTitleWord(phrase)) {
        continue;
      }

      final avgY =
          group.map((e) => e.centerY).reduce((a, b) => a + b) / group.length;

      final avgHeight =
          group.map((e) => e.height).reduce((a, b) => a + b) / group.length;

      final hangulCount = RegExp(r'[가-힣]').allMatches(phrase).length;

      double score = 0;
      score += hangulCount * 3.5;
      score += group.length * 8;
      score += avgHeight * 200;
      score -= (avgY - expectedY).abs() * 100;

      if (phrase.length >= 2 && phrase.length <= 12) {
        score += 20;
      }

      if (score > bestScore) {
        bestScore = score;
        best = phrase;
      }
    }

    return best;
  }

  /// OCR 조각 및 한국어 조사를 자연스럽게 한 문장으로 결합
  String _smartJoin(List<String> pieces) {
    final unique = <String>[];

    for (final piece in pieces) {
      final normalized = _normalize(piece);
      if (normalized.isEmpty) continue;

      if (unique.isEmpty || unique.last != normalized) {
        unique.add(normalized);
      }
    }

    var value = unique.join(' ');

    final tokens = value.split(RegExp(r'\s+'));
    final singleCharacterTokens =
        tokens.where((token) => token.runes.length == 1).length;
    if (tokens.length >= 4 && singleCharacterTokens / tokens.length >= 0.75) {
      value = tokens.join();
    }

    // 한국어 조사가 별도 조각으로 분리된 경우 앞 단어에 자연스럽게 복원 연결
    // 예: "고난" + "을" -> "고난을", "움직임" + "을" -> "움직임을", "하나님의" + "뜻" + "을" -> "하나님의 뜻을"
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
      '부터',
      '으로',
      '에서',
    ];

    for (final particle in particles) {
      value = value.replaceAllMapped(
        RegExp('([가-힣])\\s+$particle(?=\\s|\$)'),
        (match) => '${match.group(1)}$particle',
      );
    }

    return _normalize(value);
  }

  bool _canBeTitlePiece(String value) {
    if (value.isEmpty || value.length > 18) return false;
    if (!RegExp(r'[가-힣]').hasMatch(value)) return false;
    if (RegExp(r'\d').hasMatch(value)) return false;

    final upper = value.toUpperCase();
    if (upper.contains('HAPPY') || upper.contains('CHURCH')) return false;
    if (RegExp(r'[,.!?;:“”‘’]').hasMatch(value)) return false;

    return true;
  }

  String _normalize(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
