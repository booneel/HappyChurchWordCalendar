import 'package:flutter_test/flutter_test.dart';

import 'package:date_pdf/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DatePdfApp());
  });
}
