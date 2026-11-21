import 'package:expenseapp/widgets/neo_brutalist_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID');
  });

  testWidgets('fits inside the width a dialog leaves on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(339, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // Dialog's default insetPadding removes 40 px per side.
              width: 339 - 80,
              child: NeoBrutalistCalendar(
                singleDateMode: true,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                onRangeSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
