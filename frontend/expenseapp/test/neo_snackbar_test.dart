import 'package:expenseapp/widgets/neo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildHarness({
    required void Function(BuildContext context) onSuccess,
    required void Function(BuildContext context) onError,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                onPressed: () => onSuccess(context),
                child: const Text('Show Success'),
              ),
              ElevatedButton(
                onPressed: () => onError(context),
                child: const Text('Show Error'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration findSnackBarDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).boxShadow != null,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('NeoSnackBar.success uses green neo-brutalist styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        onSuccess: (context) =>
            NeoSnackBar.success(context, 'Expense saved successfully!'),
        onError: (_) {},
      ),
    );

    await tester.tap(find.text('Show Success'));
    await tester.pumpAndSettle();

    expect(find.text('Expense saved successfully!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    final decoration = findSnackBarDecoration(tester);
    expect(decoration.color, NeoSnackBar.successColor);
    expect(decoration.color, const Color(0xFF06D6A0));
    expect(decoration.border, Border.all(color: Colors.black, width: 2));
    expect(decoration.boxShadow, const [
      BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
    ]);
  });

  testWidgets('NeoSnackBar.error uses red neo-brutalist styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        onSuccess: (_) {},
        onError: (context) =>
            NeoSnackBar.error(context, 'Could not sync expenses'),
      ),
    );

    await tester.tap(find.text('Show Error'));
    await tester.pumpAndSettle();

    expect(find.text('Could not sync expenses'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

    final decoration = findSnackBarDecoration(tester);
    expect(decoration.color, NeoSnackBar.errorColor);
    expect(decoration.color, const Color(0xFFFF5D5D));
    expect(decoration.border, Border.all(color: Colors.black, width: 2));
    expect(decoration.boxShadow, const [
      BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
    ]);
  });

  testWidgets('replaces active snackbar cleanly when triggered again', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        onSuccess: (context) => NeoSnackBar.success(context, 'Saved!'),
        onError: (context) => NeoSnackBar.error(context, 'Sync failed!'),
      ),
    );

    await tester.tap(find.text('Show Success'));
    await tester.pumpAndSettle();
    expect(find.text('Saved!'), findsOneWidget);

    await tester.tap(find.text('Show Error'));
    await tester.pumpAndSettle();

    expect(find.text('Saved!'), findsNothing);
    expect(find.text('Sync failed!'), findsOneWidget);
  });
}
