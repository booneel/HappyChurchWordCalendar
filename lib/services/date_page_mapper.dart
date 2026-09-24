import 'pdf_settings_service.dart';

class DatePageMapper {
  static int get dailyStartPdfPage =>
      PdfSettingsService.instance.currentSettings.dailyStartPdfPage;

  static int get dailyPageCount =>
      PdfSettingsService.instance.currentSettings.dailyPageCount;

  static int pdfPageForDate(DateTime date, {int? startPage}) {
    final yearStart = DateTime(date.year, 1, 1);
    final daysInYear =
        DateTime(date.year, 12, 31).difference(yearStart).inDays + 1;

    if (daysInYear != 365) {
      throw ArgumentError(
        '현재 PDF는 365일 기준입니다. 윤년 PDF는 별도 매핑이 필요합니다.',
      );
    }

    final effectiveStart = startPage ?? dailyStartPdfPage;
    final dayOfYear = date.difference(yearStart).inDays + 1;
    return effectiveStart + dayOfYear - 1;
  }

  static DateTime dateForPdfPage(
    int pdfPage, {
    required int year,
    int? startPage,
    int? pageCount,
  }) {
    final effectiveStart = startPage ?? dailyStartPdfPage;
    final effectiveCount = pageCount ?? dailyPageCount;

    if (!isDailyPage(pdfPage, startPage: effectiveStart, pageCount: effectiveCount)) {
      throw ArgumentError('일일 말씀 페이지 범위가 아닙니다: $pdfPage');
    }

    return DateTime(year, 1, 1).add(
      Duration(days: pdfPage - effectiveStart),
    );
  }

  static bool isDailyPage(
    int pdfPage, {
    int? startPage,
    int? pageCount,
  }) {
    final effectiveStart = startPage ?? dailyStartPdfPage;
    final effectiveCount = pageCount ?? dailyPageCount;

    return pdfPage >= effectiveStart &&
        pdfPage < effectiveStart + effectiveCount;
  }

  static String monthDayKey(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
