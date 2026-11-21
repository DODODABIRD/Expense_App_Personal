import 'package:expenseapp/pages/ai_context_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shows the learned price range for every category', (
    tester,
  ) async {
    await _pumpPage(tester, () async => _reference);

    expect(find.text('7'), findsOneWidget);
    expect(find.text('expenses remembered'), findsOneWidget);
    expect(find.text('Where each category lands'), findsOneWidget);
    expect(find.text('Makanan'), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Rp 20.000'), findsWidgets);
    expect(find.text('Rp 50.000'), findsWidgets);
    expect(find.text('Nasi Goreng'), findsOneWidget);
    expect(find.text('LOWEST'), findsWidgets);
    expect(find.text('AVERAGE'), findsWidgets);
    expect(find.text('HIGHEST'), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Transportasi'), findsWidgets);
    expect(find.text('Ojek'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty state when the AI has no memory', (tester) async {
    await _pumpPage(
      tester,
      () async => {
        'updated': true,
        'itemCount': 0,
        'updatedAt': null,
        'template': {
          'version': 1,
          'sampleSize': 0,
          'priceRange': null,
          'categories': <dynamic>[],
        },
      },
    );

    expect(find.text('The AI has no memory yet'), findsOneWidget);
    expect(find.text('BUILD AI MEMORY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers a retry when the reference cannot be loaded', (
    tester,
  ) async {
    await _pumpPage(tester, () async => throw Exception('offline'));

    expect(find.text('Could not load the AI memory'), findsOneWidget);
    expect(find.text('Exception: offline'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  Future<Map<String, dynamic>> Function() loader,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: AiContextPage(loadReference: loader)),
  );
  await tester.pumpAndSettle();
}

const Map<String, dynamic> _reference = {
  'updated': true,
  'itemCount': 7,
  'updatedAt': '2026-10-08T02:00:00.000Z',
  'template': {
    'version': 1,
    'sampleSize': 7,
    'priceRange': {'min': 15000, 'max': 120000},
    'categories': [
      {
        'category': 'makanan',
        'count': 5,
        'priceRange': {'min': 20000, 'max': 50000},
        'averagePrice': 32000,
        'commonItems': ['Nasi Goreng', 'Bakso'],
        'types': ['expected', 'unexpected'],
      },
      {
        'category': 'transportasi',
        'count': 2,
        'priceRange': {'min': 15000, 'max': 120000},
        'averagePrice': 67500,
        'commonItems': ['Ojek'],
        'types': ['unexpected'],
      },
    ],
  },
};
