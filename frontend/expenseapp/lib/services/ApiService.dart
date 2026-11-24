import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'databaseHelper.dart';
import 'auth_service.dart';
import 'error_log_service.dart';

const String baseUrl = String.fromEnvironment(
  'EXPENSE_API_BASE_URL',
  defaultValue: 'https://dododabird.us/api',
);

const String wsUrl = String.fromEnvironment(
  'EXPENSE_WS_URL',
  defaultValue: 'wss://dododabird.us/ws',
);

const String appVersion = String.fromEnvironment(
  'EXPENSE_APP_VERSION',
  defaultValue: '2.5.0',
);

typedef ReceiptScanProgress =
    void Function(double progress, String message, {String status});

class ReceiptScanCancelledException implements Exception {
  @override
  String toString() => 'Receipt scan cancelled';
}

class ReceiptScanOperation {
  final Future<Map<String, dynamic>> future;
  final void Function() _cancel;

  ReceiptScanOperation(this.future, this._cancel);

  void cancel() => _cancel();
}

class BulkSyncResult {
  final int syncedCount;
  final bool heartbeatSent;
  final bool failed;

  const BulkSyncResult({
    required this.syncedCount,
    required this.heartbeatSent,
    required this.failed,
  });
}

class Throw {
  static const int bulkSyncChunkSize = 500;
  static const Duration _heartbeatCooldown = Duration(seconds: 30);

  static Future<void>? _inFlightSync;
  static Future<void>? _queuedSync;
  static DateTime? _lastHeartbeatAt;
  static Future<Map<String, String>> _headers() async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${await AuthService.getIdToken()}',
    };
  }


  static Future<List<Map<String, dynamic>>> getOnlineExpenses() async {
    final response = await http
        .get(Uri.parse('$baseUrl/users'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'Could not load online expenses (${response.statusCode})',
      );
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, double>> getExchangeRates() async {
    final response = await http
        .get(Uri.parse('$baseUrl/exchange-rates'), headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Exchange rates unavailable (${response.statusCode})');
    }

    final rates = jsonDecode(response.body)['rates'] as Map<String, dynamic>;
    return rates.map(
      (currency, rate) => MapEntry(currency, (rate as num).toDouble()),
    );
  }

  static ReceiptScanOperation parseReceipt(
    File imageFile, {
    ReceiptScanProgress? onProgress,
  }) {
    final client = http.Client();
    var cancelled = false;

    void cancel() {
      cancelled = true;
      client.close();
    }

    final future = _parseReceipt(
      imageFile,
      client,
      onProgress,
      () => cancelled,
    ).whenComplete(client.close);
    return ReceiptScanOperation(future, cancel);
  }

  static Future<Map<String, dynamic>> _parseReceipt(
    File imageFile,
    http.Client client,
    ReceiptScanProgress? onProgress,
    bool Function() isCancelled,
  ) async {
    final bytes = await imageFile.readAsBytes();
    onProgress?.call(0.15, 'Preparing receipt image', status: 'processing');
    final base64Image = base64Encode(bytes);
    final lowerPath = imageFile.path.toLowerCase();
    final mimeType = lowerPath.endsWith('.png') ? 'image/png' : 'image/jpeg';
    onProgress?.call(0.3, 'Uploading receipt', status: 'processing');

    late final http.StreamedResponse response;
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/parse-receipt'))
        ..headers.addAll(await _headers())
        ..body = jsonEncode({'image': base64Image, 'mimeType': mimeType});
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        final responseBody = await response.stream.bytesToString();
        String message = response.statusCode == 413
            ? 'Receipt image is too large. Please retake the photo closer or use a smaller image.'
            : 'Receipt parsing failed (${response.statusCode})';
        try {
          final body = jsonDecode(responseBody) as Map<String, dynamic>;
          if (body['error'] != null) message = body['error'].toString();
        } catch (error, stackTrace) {
          captureAppError(error, stackTrace, 'Parse receipt error response');
          // Keep the status-based message when the backend response is not JSON.
        }
        onProgress?.call(1, message, status: 'failed');
        throw Exception(message);
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/x-ndjson')) {
        final body =
            jsonDecode(await response.stream.bytesToString())
                as Map<String, dynamic>;
        onProgress?.call(1, 'Receipt data received', status: 'success');
        return {
          'date': body['date']?.toString(),
          'items': (body['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>(),
          'provider': body['provider']?.toString(),
        };
      }

      Map<String, dynamic>? result;
      String? streamError;
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['type'] == 'progress') {
          final progress = event['progress'];
          onProgress?.call(
            progress is num ? progress.toDouble() : 0.5,
            event['message']?.toString() ?? 'Processing receipt',
            status: event['status']?.toString() ?? 'processing',
          );
        } else if (event['type'] == 'result') {
          result = event;
        } else if (event['type'] == 'error') {
          streamError =
              event['message']?.toString() ?? 'Receipt parsing failed';
          onProgress?.call(1, streamError, status: 'failed');
        }
      }

      if (streamError != null) throw Exception(streamError);
      if (result == null) throw Exception('Receipt parser returned no result');
      onProgress?.call(1, 'Receipt data received', status: 'success');
      return {
        'date': result['date']?.toString(),
        'items': (result['items'] as List<dynamic>)
            .cast<Map<String, dynamic>>(),
        'provider': result['provider']?.toString(),
      };
    } catch (error) {
      if (isCancelled()) throw ReceiptScanCancelledException();
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> parseNotification({
    required String title,
    required String message,
    required String packageName,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/parse-notification'),
          headers: await _headers(),
          body: jsonEncode({
            'title': title,
            'message': message,
            'packageName': packageName,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      String message = 'Notification parsing failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) message = body['error'].toString();
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Parse notification error response');
        // Keep the status-based message when the backend response is not JSON.
      }
      throw Exception(message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getAiNotificationReference() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/ai-notification-reference'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      String message =
          'Could not load AI notification context (${response.statusCode})';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) message = body['error'].toString();
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Load AI reference error response');
        // Keep the status-based message when the backend response is not JSON.
      }
      throw Exception(message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<int> saveAiNotificationReference(
    List<Map<String, dynamic>> items,
  ) async {
    final response = await http
        .put(
          Uri.parse('$baseUrl/ai-notification-reference'),
          headers: await _headers(),
          body: jsonEncode({'items': items}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message =
          'Could not update AI notification reference (${response.statusCode})';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) message = body['error'].toString();
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Parse AI reference error response');
        // Keep the status-based message when the response is not JSON.
      }
      throw Exception(message);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['updated'] != true) {
      throw Exception('The server did not confirm the reference update');
    }
    return body['itemCount'] is int ? body['itemCount'] as int : 0;
  }

  static Future<bool> updateUserByLocalId(
    int? localId,
    String name,
    int amount,
    String category,
    String type,
    String date, {
    required int syncVersion,
  }) async {
    if (localId == null) return false;

    final url = Uri.parse('$baseUrl/users/$localId');

    final response = await http
        .put(
          url,
          headers: await _headers(),
          body: jsonEncode({
            "name": name,
            "amount": amount,
            "category": category,
            "type": type,
            "date": date,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) return false;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Update failed (${response.statusCode}): ${response.body}',
      );
    }

    await DatabaseHelp.markSynced(localId, syncVersion);
    return true;
  }

  /// Throws unless the server confirms; 404 counts as already deleted.
  static Future<void> deleteUserByLocalId(int localId) async {
    final url = Uri.parse('$baseUrl/users/$localId');

    final response = await http
        .delete(url, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Delete failed (${response.statusCode})');
    }
  }

  /// Bulk-deletes every expense owned by the current user in one request.
  static Future<void> deleteAllExpenses() async {
    final url = Uri.parse('$baseUrl/users/delete-all');

    final response = await http
        .post(url, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Delete all failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) message = body['error'].toString();
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Parse delete-all error response');
        // Keep the status-based message when the backend response is not JSON.
      }
      throw Exception(message);
    }
  }

  static Future<bool> createExpense(
    int localId,
    String name,
    int amount, // ← Change from String to int
    String category,
    String type,
    String date,
  ) async {
    final url = Uri.parse('$baseUrl/users');

    try {
      final response = await http
          .post(
            url,
            headers: await _headers(),
            body: jsonEncode({
              "localId": localId,
              "name": name,
              "amount": amount,
              "category": category,
              "type": type,
              "date": date,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception(
          'Create failed (${response.statusCode}): ${response.body}',
        );
      }

      // New rows start at syncVersion 0; an edit made meanwhile bumps it, so
      // that row stays unsynced and the edit is pushed later.
      await DatabaseHelp.markSynced(localId, 0);
      return true;
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Create expense sync');
      print('Sync failed: $error');
      // Expense stays local, marked as not synced
      return false;
    }
  }

  static Future<BulkSyncResult> pushExpenseBatches({
    required List<Map<String, dynamic>> pendingExpenses,
    required Future<String> Function() getToken,
    required Future<void> Function(List<int> syncedLocalIds) onBatchSynced,
    Map<String, dynamic>? deviceInfo,
    http.Client? client,
    String apiBaseUrl = baseUrl,
    int chunkSize = bulkSyncChunkSize,
  }) async {
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be >= 1');
    }
    if (pendingExpenses.isEmpty) {
      return const BulkSyncResult(
        syncedCount: 0,
        heartbeatSent: false,
        failed: false,
      );
    }

    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final httpClient = client ?? http.Client();
    var bulkUnsupported = false;
    var syncedCount = 0;
    var heartbeatSent = false;
    var failed = false;

    try {
      for (var i = 0; i < pendingExpenses.length; i += chunkSize) {
        final end = (i + chunkSize) > pendingExpenses.length
            ? pendingExpenses.length
            : i + chunkSize;
        final chunk = pendingExpenses.sublist(i, end);
        final isLastChunk = end >= pendingExpenses.length;
        final chunkIds = chunk.map((e) => (e['id'] as num).toInt()).toList();

        if (!bulkUnsupported) {
          try {
            final payload = <String, dynamic>{
              'expenses': chunk
                  .map(
                    (e) => {
                      'localId': (e['id'] as num).toInt(),
                      'name': e['name'],
                      'amount': (e['amount'] as num).toInt(),
                      'category': e['category'],
                      'type': e['type'],
                      'date': e['date'],
                    },
                  )
                  .toList(),
              if (isLastChunk && deviceInfo != null) 'device': deviceInfo,
            };

            final response = await httpClient
                .post(
                  Uri.parse('$apiBaseUrl/users/bulk'),
                  headers: headers,
                  body: jsonEncode(payload),
                )
                .timeout(const Duration(seconds: 30));

            if (response.statusCode == 404) {
              bulkUnsupported = true;
            } else if (response.statusCode >= 200 &&
                response.statusCode < 300) {
              final confirmedIds = _parseConfirmedLocalIds(
                response.body,
                chunkIds,
              );
              if (confirmedIds.isNotEmpty) {
                await onBatchSynced(confirmedIds);
                syncedCount += confirmedIds.length;
              }
              if (isLastChunk && deviceInfo != null) {
                heartbeatSent = true;
              }
              continue;
            } else {
              throw Exception(
                'Bulk sync failed (${response.statusCode}): ${response.body}',
              );
            }
          } catch (error, stackTrace) {
            captureAppError(error, stackTrace, 'Bulk expense sync');
            failed = true;
            break;
          }
        }

        // Fallback for older backend servers that do not expose /users/bulk.
        final succeededIds = <int>[];
        for (final expense in chunk) {
          final localId = (expense['id'] as num).toInt();
          try {
            final response = await httpClient
                .post(
                  Uri.parse('$apiBaseUrl/users'),
                  headers: headers,
                  body: jsonEncode({
                    'localId': localId,
                    'name': expense['name'],
                    'amount': (expense['amount'] as num).toInt(),
                    'category': expense['category'],
                    'type': expense['type'],
                    'date': expense['date'],
                  }),
                )
                .timeout(const Duration(seconds: 10));

            if (response.statusCode != 200 && response.statusCode != 201) {
              throw Exception(
                'Create failed (${response.statusCode}): ${response.body}',
              );
            }
            succeededIds.add(localId);
          } catch (error, stackTrace) {
            captureAppError(error, stackTrace, 'Pending expense sync');
            failed = true;
          }
        }
        if (succeededIds.isNotEmpty) {
          await onBatchSynced(succeededIds);
          syncedCount += succeededIds.length;
        }
      }
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }

    return BulkSyncResult(
      syncedCount: syncedCount,
      heartbeatSent: heartbeatSent,
      failed: failed,
    );
  }

  static List<int> _parseConfirmedLocalIds(
    String responseBody,
    List<int> fallbackIds,
  ) {
    if (responseBody.trim().isEmpty) return fallbackIds;
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic> &&
          decoded['syncedLocalIds'] is List) {
        return (decoded['syncedLocalIds'] as List<dynamic>)
            .map((id) => id is int ? id : int.tryParse(id.toString()))
            .whereType<int>()
            .toList();
      }
    } catch (_) {
      // Fall back to the chunk's local IDs on unexpected 2xx bodies.
    }
    return fallbackIds;
  }

  static Future<void> syncPendingExpenses() {
    if (_inFlightSync != null) {
      return _queuedSync ??= _runQueuedSync();
    }
    return _startSyncPass();
  }

  static Future<void> _startSyncPass() {
    final future = _runSyncPendingExpenses().whenComplete(() {
      _inFlightSync = null;
    });
    _inFlightSync = future;
    return future;
  }

  static Future<void> _runQueuedSync() async {
    try {
      await _inFlightSync;
    } catch (_) {
      // Let the queued follow-up pass run and report its own outcome.
    }
    _queuedSync = null;
    final active = _inFlightSync ?? _startSyncPass();
    await active;
  }

  static Future<void> _runSyncPendingExpenses() async {
    await _pushUnsyncedExpenses();
    // After the push, so a delete never races an upsert of the same row.
    await _pushPendingDeletes();
  }

  static Future<void> _pushUnsyncedExpenses() async {
    final pendingExpenses = await DatabaseHelp.getUnsyncedData();
    if (pendingExpenses.isEmpty) {
      await _maybeReportDeviceSync();
      return;
    }

    Map<String, dynamic>? deviceInfo;
    try {
      deviceInfo = await _buildDeviceSyncPayload();
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Build device sync payload');
    }

    final sentVersions = {
      for (final expense in pendingExpenses)
        (expense['id'] as num).toInt():
            (expense['syncVersion'] as num?)?.toInt() ?? 0,
    };

    final result = await pushExpenseBatches(
      pendingExpenses: pendingExpenses,
      getToken: AuthService.getIdToken,
      onBatchSynced: (ids) => DatabaseHelp.markManySynced({
        for (final id in ids)
          if (sentVersions[id] != null) id: sentVersions[id]!,
      }),
      deviceInfo: deviceInfo,
    );

    if (result.heartbeatSent) {
      _lastHeartbeatAt = DateTime.now();
    } else if (!result.failed) {
      unawaited(_maybeReportDeviceSync(deviceInfo: deviceInfo));
    }
  }

  static Future<void> _pushPendingDeletes() async {
    final localIds = await DatabaseHelp.getPendingDeletes();
    for (final localId in localIds) {
      try {
        await deleteUserByLocalId(localId);
        await DatabaseHelp.clearPendingDelete(localId);
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Pending expense delete sync');
        // Likely offline; the rest are retried on the next sync pass.
        break;
      }
    }
  }

  static Future<Map<String, dynamic>> _buildDeviceSyncPayload() async {
    final deviceId = await DatabaseHelp.getOrCreateDeviceId();
    final expenseCount = await DatabaseHelp.getLocalExpenseCount();
    return {
      'deviceId': deviceId,
      'deviceName':
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'platform': Platform.operatingSystem,
      'appVersion': appVersion,
      'expenseCount': expenseCount,
    };
  }

  static Future<void> _maybeReportDeviceSync({
    Map<String, dynamic>? deviceInfo,
  }) async {
    final last = _lastHeartbeatAt;
    if (last != null &&
        DateTime.now().difference(last) < _heartbeatCooldown) {
      return;
    }
    await reportDeviceSync(deviceInfo: deviceInfo);
  }

  /// Reports this device's last successful sync so the admin panel can show
  /// per-device activity. Failures are logged and never block expense sync.
  static Future<void> reportDeviceSync({
    Map<String, dynamic>? deviceInfo,
  }) async {
    try {
      final payload = deviceInfo ?? await _buildDeviceSyncPayload();

      final response = await http
          .post(
            Uri.parse('$baseUrl/sync/beat'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastHeartbeatAt = DateTime.now();
      }
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Device sync heartbeat');
    }
  }

  static WebSocket? _liveWs;
  static Timer? _pingTimer;
  static final StreamController<Map<String, dynamic>> _liveEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of real-time events broadcasted by the VPS server (create, update, delete).
  static Stream<Map<String, dynamic>> get liveEvents =>
      _liveEventsController.stream;

  /// Returns true if the live WebSocket is currently connected.
  static bool get isWebSocketConnected =>
      _liveWs != null && _liveWs!.readyState == WebSocket.open;

  /// Connects to the VPS backend WebSocket server defined in backend/server.js.
  /// Sends auth token and streams live changes from backend/api/index.js.
  static Future<void> connectLiveWebSocket() async {
    if (isWebSocketConnected) return;

    try {
      final token = await AuthService.getIdToken();
      final uri = Uri.parse(wsUrl).replace(
        queryParameters: {'token': token},
      );

      final socket = await WebSocket.connect(uri.toString());
      _liveWs = socket;

      socket.add(jsonEncode({'type': 'auth', 'token': token}));

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
        if (_liveWs != null && _liveWs!.readyState == WebSocket.open) {
          _liveWs!.add(jsonEncode({'type': 'ping'}));
        } else {
          timer.cancel();
        }
      });

      socket.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is Map<String, dynamic>) {
              if (decoded['type'] == 'pong') return;
              _liveEventsController.add(decoded);
            }
          } catch (e, stackTrace) {
            captureAppError(e, stackTrace, 'WebSocket message decode');
          }
        },
        onError: (error, stackTrace) {
          captureAppError(error, stackTrace, 'WebSocket connection error');
          disconnectLiveWebSocket();
        },
        onDone: () {
          disconnectLiveWebSocket();
        },
        cancelOnError: true,
      );
    } catch (e, stackTrace) {
      captureAppError(e, stackTrace, 'WebSocket connect failed');
    }
  }

  /// Closes the live WebSocket connection and stops the heartbeat timer.
  static Future<void> disconnectLiveWebSocket() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    final socket = _liveWs;
    _liveWs = null;
    if (socket != null && socket.readyState == WebSocket.open) {
      await socket.close();
    }
  }

  /// Fetches public configuration from VPS backend /api/public-config
  static Future<Map<String, dynamic>> getPublicConfig() async {
    final response = await http
        .get(Uri.parse('$baseUrl/public-config'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Could not fetch public config (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
