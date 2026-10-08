import 'package:flutter_test/flutter_test.dart';

import 'package:wordcalendar/services/pdf_catalog_service.dart';

void main() {
  final service = PdfCatalogService.instance;

  test('imports simple date map and keeps supplied confidence', () {
    final result = service.parseTitleCatalogJson(
      '{"year":2026,"titles":{"01-01":"새해의 소망","1월 2일":"믿음의 길"},'
      '"confidences":{"01-01":0.72}}',
    );

    expect(result.year, 2026);
    expect(result.titles['01-01'], '새해의 소망');
    expect(result.titles['01-02'], '믿음의 길');
    expect(result.confidences['01-01'], 0.72);
    expect(result.confidences['01-02'], 1.0);
  });

  test('imports array entries with date and title fields', () {
    final result = service.parseTitleCatalogJson(
      '[{"date":"2026-03-04","title":"감사의 시작"},'
      '{"month":3,"day":5,"name":"평안"}]',
      fallbackYear: 2026,
    );

    expect(result.titles, {
      '03-04': '감사의 시작',
      '03-05': '평안',
    });
  });
}
