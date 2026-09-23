class DatePageMapper {
  static const int dailyStartPdfPage = 4;
  static const int dailyPageCount = 365;

  static int pdfPageForDate(DateTime date) {
    final yearStart = DateTime(date.year, 1, 1);
    final daysInYear =
        DateTime(date.year, 12, 31).difference(yearStart).inDays + 1;

    if (daysInYear != 365) {
      throw ArgumentError(
        '현재 PDF는 365일 기준입니다. 윤년 PDF는 별도 매핑이 필요합니다.',
      );
    }

    final dayOfYear = date.difference(yearStart).inDays + 1;
    return dailyStartPdfPage + dayOfYear - 1;
  }

  static DateTime dateForPdfPage(int pdfPage, {required int year}) {
    if (!isDailyPage(pdfPage)) {
      throw ArgumentError('일일 말씀 페이지 범위가 아닙니다: $pdfPage');
    }

    return DateTime(year, 1, 1).add(
      Duration(days: pdfPage - dailyStartPdfPage),
    );
  }

  static bool isDailyPage(int pdfPage) {
    return pdfPage >= dailyStartPdfPage &&
        pdfPage < dailyStartPdfPage + dailyPageCount;
  }

  static String monthDayKey(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
