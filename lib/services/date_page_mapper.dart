import 'pdf_settings_service.dart';

class DatePageMapper {
  static int get dailyStartPdfPage =>
      PdfSettingsService.instance.currentSettings.dailyStartPdfPage;

  static int get dailyPageCount {
    final settings = PdfSettingsService.instance.currentSettings;
    final availablePages =
        settings.pdfPageCount - settings.dailyStartPdfPage + 1;
    if (availablePages < 1) return 0;
    return settings.dailyPageCount < availablePages
        ? settings.dailyPageCount
        : availablePages;
  }

  static int pdfPageForDate(DateTime date, {int? startPage}) {
    final page = pdfPageForDateOrNull(date, startPage: startPage);
    if (page == null) {
      throw ArgumentError(
        '이 날짜에 연결된 PDF 페이지가 없습니다: ${date.year}-${date.month}-${date.day}',
      );
    }
    return page;
  }

  static int? pdfPageForDateOrNull(DateTime date, {int? startPage}) {
    final yearStart = DateTime(date.year, 1, 1);
    final effectiveStart = startPage ?? dailyStartPdfPage;
    final dayOfYear = date.difference(yearStart).inDays + 1;

    if (dayOfYear < 1 || dayOfYear > dailyPageCount) return null;
    return effectiveStart + dayOfYear - 1;
  }

  static bool isDateAvailable(DateTime date, {int? startPage}) {
    return pdfPageForDateOrNull(date, startPage: startPage) != null;
  }

  static DateTime dateForPdfPage(
    int pdfPage, {
    required int year,
    int? startPage,
    int? pageCount,
  }) {
    final effectiveStart = startPage ?? dailyStartPdfPage;
    final effectiveCount = pageCount ?? dailyPageCount;

    if (!isDailyPage(
      pdfPage,
      startPage: effectiveStart,
      pageCount: effectiveCount,
    )) {
      throw ArgumentError('일일 말씀 페이지 범위가 아닙니다: $pdfPage');
    }

    return DateTime(year, 1, 1).add(Duration(days: pdfPage - effectiveStart));
  }

  static bool isDailyPage(int pdfPage, {int? startPage, int? pageCount}) {
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
