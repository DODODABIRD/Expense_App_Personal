import 'dart:convert';

import 'package:expenseapp/services/ApiService.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _row(int id) => {
  'id': id,
  'name': 'Expense $id',
  'amount': id * 1000,
  'category': 'makanan',
  'type': 'expected',
  'date': '2026-11-22',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const device = {
    'deviceId': 'dev-test-1',
    'deviceName': 'android 14',
    'platform': 'android',
    'appVersion': '2.0.0',
    'expenseCount': 5,
  };

  test('pushes up to chunkSize items in a single bulk request', () async {
    var tokenCalls = 0;
    final requests = <http.Request>[];
    final syncedBatches = <List<int>>[];

    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'count': 3,
          'syncedLocalIds': ['1', '2', '3'],
        }),
        200,
      );
    });

    final result = await Throw.pushExpenseBatches(
      pendingExpenses: [_row(1), _row(2), _row(3)],
      getToken: () async {
        tokenCalls++;
        return 'test-token';
      },
      onBatchSynced: (ids) async => syncedBatches.add(ids),
      deviceInfo: device,
      client: client,
      apiBaseUrl: 'https://example.test/api',
      chunkSize: 500,
    );

    expect(tokenCalls, 1);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/users/bulk');
    expect(requests.single.headers['Authorization'], 'Bearer test-token');

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect((body['expenses'] as List), hasLength(3));
    expect(body['device'], device);

    expect(syncedBatches, [
      [1, 2, 3],
    ]);
    expect(result.syncedCount, 3);
    expect(result.heartbeatSent, isTrue);
    expect(result.failed, isFalse);
  });

  test('chunks large syncs and attaches device info only on the last chunk', () async {
    var tokenCalls = 0;
    final bodies = <Map<String, dynamic>>[];
    final syncedBatches = <List<int>>[];

    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      final expenses = body['expenses'] as List<dynamic>;
      return http.Response(
        jsonEncode({
          'count': expenses.length,
          'syncedLocalIds': expenses
              .map((e) => (e as Map<String, dynamic>)['localId'].toString())
              .toList(),
        }),
        200,
      );
    });

    final result = await Throw.pushExpenseBatches(
      pendingExpenses: [_row(1), _row(2), _row(3), _row(4), _row(5)],
      getToken: () async {
        tokenCalls++;
        return 'test-token';
      },
      onBatchSynced: (ids) async => syncedBatches.add(ids),
      deviceInfo: device,
      client: client,
      apiBaseUrl: 'https://example.test/api',
      chunkSize: 2,
    );

    expect(tokenCalls, 1);
    expect(bodies, hasLength(3));
    expect(bodies[0].containsKey('device'), isFalse);
    expect(bodies[1].containsKey('device'), isFalse);
    expect(bodies[2]['device'], device);

    expect(syncedBatches, [
      [1, 2],
      [3, 4],
      [5],
    ]);
    expect(result.syncedCount, 5);
    expect(result.heartbeatSent, isTrue);
    expect(result.failed, isFalse);
  });

  test('falls back to per-item POST /users on 404 without re-probing bulk', () async {
    final paths = <String>[];
    final syncedBatches = <List<int>>[];

    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/users/bulk')) {
        return http.Response('Not Found', 404);
      }
      return http.Response('{}', 200);
    });

    final result = await Throw.pushExpenseBatches(
      pendingExpenses: [_row(1), _row(2), _row(3), _row(4)],
      getToken: () async => 'test-token',
      onBatchSynced: (ids) async => syncedBatches.add(ids),
      deviceInfo: device,
      client: client,
      apiBaseUrl: 'https://example.test/api',
      chunkSize: 2,
    );

    expect(paths, [
      '/api/users/bulk',
      '/api/users',
      '/api/users',
      '/api/users',
      '/api/users',
    ]);
    expect(syncedBatches, [
      [1, 2],
      [3, 4],
    ]);
    expect(result.syncedCount, 4);
    expect(result.heartbeatSent, isFalse);
    expect(result.failed, isFalse);
  });

  test('stops on mid-sync failure while preserving earlier synced chunks', () async {
    var calls = 0;
    final syncedBatches = <List<int>>[];

    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'count': 2,
            'syncedLocalIds': ['1', '2'],
          }),
          200,
        );
      }
      return http.Response('Server Error', 500);
    });

    final result = await Throw.pushExpenseBatches(
      pendingExpenses: [_row(1), _row(2), _row(3), _row(4), _row(5), _row(6)],
      getToken: () async => 'test-token',
      onBatchSynced: (ids) async => syncedBatches.add(ids),
      deviceInfo: device,
      client: client,
      apiBaseUrl: 'https://example.test/api',
      chunkSize: 2,
    );

    expect(calls, 2);
    expect(syncedBatches, [
      [1, 2],
    ]);
    expect(result.syncedCount, 2);
    expect(result.heartbeatSent, isFalse);
    expect(result.failed, isTrue);
  });
}
