import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ErrorLogEntry {
  const ErrorLogEntry({
    required this.timestamp,
    required this.context,
    required this.message,
    required this.stackTrace,
  });

  final DateTime timestamp;
  final String context;
  final String message;
  final String stackTrace;

  factory ErrorLogEntry.fromJson(Map<String, dynamic> json) {
    return ErrorLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      context: json['context'] as String,
      message: json['message'] as String,
      stackTrace: json['stackTrace'] as String,
    );
  }

  Map<String, Object> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'context': context,
    'message': message,
    'stackTrace': stackTrace,
  };

  String toText() {
    final parts = [
      '[${timestamp.toLocal().toIso8601String()}] $context',
      message,
      if (stackTrace.isNotEmpty) 'Stack trace:\n$stackTrace',
    ];
    return parts.join('\n');
  }
}

class ErrorLogService {
  ErrorLogService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final instance = ErrorLogService();
  static const _logFileName = 'developer_error_logs.jsonl';

  final Future<Directory> Function() _directoryProvider;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> recordError(
    Object error, {
    required String context,
    StackTrace? stackTrace,
  }) {
    final entry = ErrorLogEntry(
      timestamp: DateTime.now(),
      context: context,
      message: error.toString(),
      stackTrace: stackTrace?.toString() ?? '',
    );
    final write = _writeQueue.then((_) => _append(entry));
    _writeQueue = write;
    return write;
  }

  Future<List<ErrorLogEntry>> readLogs() async {
    await _writeQueue;
    final file = await _logFile();
    if (!await file.exists()) return [];

    final entries = <ErrorLogEntry>[];
    for (final line in await file.readAsLines()) {
      try {
        entries.add(
          ErrorLogEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
        );
      } catch (_) {
        // Ignore an incomplete or malformed line without losing other logs.
      }
    }
    entries.sort(
      (first, second) => second.timestamp.compareTo(first.timestamp),
    );
    return entries;
  }

  Future<File> exportToTextFile({DateTime? exportedAt}) async {
    final entries = await readLogs();
    final directory = await _directoryProvider();
    await directory.create(recursive: true);

    final exportTime = exportedAt ?? DateTime.now();
    final safeTimestamp = exportTime.toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}error-logs-$safeTimestamp.txt',
    );
    final content = [
      'Expense App Error Logs',
      'Exported at: ${exportTime.toLocal().toIso8601String()}',
      'Total errors: ${entries.length}',
      if (entries.isEmpty) '\nNo errors recorded.',
      if (entries.isNotEmpty)
        '\n${entries.map((entry) => entry.toText()).join('\n\n')}',
    ].join('\n');
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<File> _logFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}$_logFileName');
  }

  Future<void> deleteAllLogs() async {
    await _writeQueue;
    final file = await _logFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _append(ErrorLogEntry entry) async {
    try {
      final file = await _logFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never make the original app error worse.
    }
  }
}

void captureAppError(Object error, StackTrace stackTrace, String context) {
  unawaited(
    ErrorLogService.instance.recordError(
      error,
      context: context,
      stackTrace: stackTrace,
    ),
  );
}
