import 'dart:io';

import 'package:expenseapp/services/error_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late ErrorLogService errorLogService;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'expense-app-error-logs-',
    );
    errorLogService = ErrorLogService(
      directoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('persists errors and reads newest entries first', () async {
    await errorLogService.recordError(
      StateError('database unavailable'),
      context: 'Startup',
      stackTrace: StackTrace.current,
    );
    await errorLogService.recordError(
      ArgumentError('invalid amount'),
      context: 'Expense form',
      stackTrace: StackTrace.current,
    );

    final entries = await errorLogService.readLogs();

    expect(entries, hasLength(2));
    expect(entries.first.context, 'Expense form');
    expect(entries.first.message, contains('invalid amount'));
    expect(entries.first.stackTrace, isNotEmpty);
    expect(entries.last.context, 'Startup');
  });

  test('exports all errors and stack traces to a text file', () async {
    await errorLogService.recordError(
      Exception('network unavailable'),
      context: 'Expense sync',
      stackTrace: StackTrace.fromString('sync.dart:42'),
    );

    final file = await errorLogService.exportToTextFile(
      exportedAt: DateTime(2026, 9, 27, 10, 11, 12),
    );
    final content = await file.readAsString();

    expect(file.path, endsWith('.txt'));
    expect(content, contains('Total errors: 1'));
    expect(content, contains('Expense sync'));
    expect(content, contains('network unavailable'));
    expect(content, contains('sync.dart:42'));
  });

  test('exports an empty log clearly', () async {
    final file = await errorLogService.exportToTextFile();

    expect(await file.readAsString(), contains('No errors recorded.'));
  });
}
