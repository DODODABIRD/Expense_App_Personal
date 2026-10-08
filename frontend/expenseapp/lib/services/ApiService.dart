import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'databaseHelper.dart';
import 'auth_service.dart';
import 'error_log_service.dart';

const String baseUrl = String.fromEnvironment(
  'EXPENSE_API_BASE_URL',
  defaultValue: 'https://vps.dododabird.us/api',
);

const String wsUrl = String.fromEnvironment(
  'EXPENSE_WS_URL',
  defaultValue: 'wss://vps.dododabird.us/ws',
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

class Throw {
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

  static Future<int> updateAiNotificationReference() async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/ai-notification-reference/refresh'),
          headers: await _headers(),
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

  static Future<String?> getServerIdFromLocalId(int localId) async {
    final url = Uri.parse('$baseUrl/users/local/$localId');

    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['_id'] as String?;
    }

    print('User not found');
    return null;
  }

  static Future<String?> getMongoIdFromLocalId(int localId) =>
      getServerIdFromLocalId(localId);

  static Future<bool> updateUserByLocalId(
    int? localId,
    String name,
    int amount,
    String category,
    String type,
    String date,
  ) async {
    if (localId == null) return false;
    final serverId = await getServerIdFromLocalId(localId);

    if (serverId == null) return false;

    final url = Uri.parse('$baseUrl/users/$serverId');

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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Update failed (${response.statusCode}): ${response.body}',
      );
    }

    await DatabaseHelp.updateMongoId(localId, serverId);
    return true;
  }

  static Future<void> deleteUserByLocalId(int localId) async {
    final serverId = await getServerIdFromLocalId(localId);

    if (serverId == null) return;

    final url = Uri.parse('$baseUrl/users/$serverId');

    await http.delete(url, headers: await _headers());
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

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final serverId = responseData['_id'] as String?;
      if (serverId != null) {
        await DatabaseHelp.updateMongoId(localId, serverId);
      }

      return serverId != null;
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Create expense sync');
      print('Sync failed: $error');
      // Expense stays local, marked as not synced
      return false;
    }
  }

  static Future<void> syncPendingExpenses() async {
    final pendingExpenses = await DatabaseHelp.getUnsyncedData();

    for (final expense in pendingExpenses) {
      try {
        final serverId = expense['mongoId'] as String?;
        if (serverId == null || serverId.isEmpty) {
          await createExpense(
            expense['id'] as int,
            expense['name'] as String,
            expense['amount'] as int,
            expense['category'] as String,
            expense['type'] as String,
            expense['date'] as String,
          );
        } else {
          await updateUserByLocalId(
            expense['id'] as int,
            expense['name'] as String,
            expense['amount'] as int,
            expense['category'] as String,
            expense['type'] as String,
            expense['date'] as String,
          );
        }
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Pending expense sync');
        print('Pending sync failed: $error');
      }
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
