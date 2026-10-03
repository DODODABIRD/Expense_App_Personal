import 'package:expenseapp/pages/ExpenseSumarry.dart';
import 'package:expenseapp/pages/hp2.dart' show ExpenseModel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID');
  });

  testWidgets(
    'explains when there are too few expenses for outlier detection',
    (tester) async {
      await _pumpSummary(tester, [
        _expense(1, 'Groceries', 100),
        _expense(2, 'Bus fare', 150),
      ]);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(
        find.text('Tambahkan minimal 3 transaksi untuk mendeteksi outlier.'),
        findsOneWidget,
      );
      expect(find.textContaining('Tidak ada outlier terdeteksi'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows proportional expense type segments', (tester) async {
    await _pumpSummary(tester, [
      _expense(1, 'Planned', 50),
      _expense(2, 'Unexpected', 30, type: 'unexpected'),
      _expense(3, 'Other', 20, type: 'others'),
    ]);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final chart = find.byKey(const ValueKey('expense-type-distribution-bar'));
    final segments = tester.widgetList<Flexible>(
      find.descendant(of: chart, matching: find.byType(Flexible)),
    );

    expect(chart, findsOneWidget);
    expect(segments.map((segment) => segment.flex), [500, 300, 200]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty state when there are no expenses', (
    tester,
  ) async {
    await _pumpSummary(tester, []);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada tipe pengeluaran tercatat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detects an outlier with interpolated quartiles', (tester) async {
    await _pumpSummary(tester, [
      _expense(1, 'Ordinary expense 1', 100),
      _expense(2, 'Ordinary expense 2', 100),
      _expense(3, 'Ordinary expense 3', 100),
      _expense(4, 'Large purchase', 1000),
    ]);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('Large purchase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSummary(
  WidgetTester tester,
  List<ExpenseModel> expenses,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(
    MaterialApp(home: ExpenseSumarryPage(initialExpenses: expenses)),
  );
  await tester.pumpAndSettle();
}

ExpenseModel _expense(
  int expenseId,
  String name,
  int amount, {
  String type = 'expected',
}) {
  return ExpenseModel(
    id: expenseId,
    name: name,
    amount: amount,
    date: DateTime(2026, 9, 28),
    category: 'makanan',
    type: type,
  );
}
