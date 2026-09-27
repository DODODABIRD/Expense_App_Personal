import 'dart:io';

import 'package:expenseapp/pages/developer_logs_page.dart';
import 'package:expenseapp/services/error_log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an empty state when there are no errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeveloperLogsPage(errorLogService: _FakeErrorLogService([])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No errors recorded.'), findsOneWidget);
  });

  testWidgets('shows an error and its expandable stack trace', (tester) async {
    const fullMessage =
        'Bad state: receipt scan failed\nline two\nline three\ncomplete error detail';
    await tester.pumpWidget(
      MaterialApp(
        home: DeveloperLogsPage(
          errorLogService: _FakeErrorLogService([
            ErrorLogEntry(
              timestamp: DateTime(2026, 9, 27),
              context: 'Receipt scan',
              message: fullMessage,
              stackTrace: 'receipt_scan.dart:42',
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('receipt scan failed'), findsOneWidget);
    expect(find.textContaining('Receipt scan'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == fullMessage,
      ),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('receipt_scan.dart:42'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == fullMessage,
      ),
      findsOneWidget,
    );
  });
}

class _FakeErrorLogService extends ErrorLogService {
  _FakeErrorLogService(this.entries)
    : super(directoryProvider: () async => Directory.systemTemp);

  final List<ErrorLogEntry> entries;

  @override
  Future<List<ErrorLogEntry>> readLogs() async => entries;
}
