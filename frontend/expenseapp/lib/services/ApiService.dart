import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'databaseHelper.dart';
import 'auth_service.dart';

const String baseUrl = "https://expense-app-personal.vercel.app/api";

class Throw {
  static Future<Map<String, String>> _headers() async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${await AuthService.getIdToken()}',
    };
  }

  static Future<void> getUsers() async {
    final url = Uri.parse('$baseUrl/users');

    final response = await http.get(url, headers: await _headers());

    print(response.statusCode);
    print(response.body);
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

  static Future<Map<String, dynamic>> parseReceipt(
    File imageFile,
  ) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final lowerPath = imageFile.path.toLowerCase();
    final mimeType = lowerPath.endsWith('.png') ? 'image/png' : 'image/jpeg';

    final response = await http
        .post(
          Uri.parse('$baseUrl/parse-receipt'),
          headers: await _headers(),
          body: jsonEncode({'image': base64Image, 'mimeType': mimeType}),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      String message = response.statusCode == 413
          ? 'Receipt image is too large. Please retake the photo closer or use a smaller image.'
          : 'Receipt parsing failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) message = body['error'].toString();
      } catch (_) {
        // Keep the status-based message when the backend response is not JSON.
      }
      throw Exception(message);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'date': data['date']?.toString(),
      'items': (data['items'] as List<dynamic>).cast<Map<String, dynamic>>(),
    };
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
      } catch (_) {
        // Keep the status-based message when the backend response is not JSON.
      }
      throw Exception(message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> getUserById(String id) async {
    final url = Uri.parse('$baseUrl/users/$id');

    final response = await http.get(url, headers: await _headers());

    print(response.statusCode);
    print(response.body);
  }

  Future<void> updateUser(String id) async {
    final url = Uri.parse('$baseUrl/users/$id');

    final response = await http.put(
      url,
      headers: await _headers(),
      body: jsonEncode({"name": "Updated Name"}),
    );

    print(response.statusCode);
    print(response.body);
  }

  Future<void> deleteUser(String id) async {
    final url = Uri.parse('$baseUrl/users/$id');

    final response = await http.delete(url, headers: await _headers());

    print(response.statusCode);
    print(response.body);
  }

  static Future<String?> getMongoIdFromLocalId(int localId) async {
    final url = Uri.parse('$baseUrl/users/local/$localId');

    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['_id']; // ✅ Mongo ObjectId
    }

    print('User not found');
    return null;
  }

  static Future<bool> updateUserByLocalId(
    int? localId,
    String name,
    int amount, // ← Change from String to int
    String category,
    String type,
    String date,
  ) async {
    final mongoId = await getMongoIdFromLocalId(localId!);

    if (mongoId == null) return false;

    final url = Uri.parse('$baseUrl/users/$mongoId');

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

    await DatabaseHelp.updateMongoId(localId, mongoId);

    print(response.statusCode);
    print(response.body);
    return true;
  }

  static Future<void> deleteUserByLocalId(int localId) async {
    final mongoId = await getMongoIdFromLocalId(localId);

    if (mongoId == null) return;

    final url = Uri.parse('$baseUrl/users/$mongoId');

    final response = await http.delete(url, headers: await _headers());

    print(response.statusCode);
    print(response.body);
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
      } catch (_) {
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

      final mongoResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final mongoId = mongoResponse['_id'] as String?;
      if (mongoId != null) {
        await DatabaseHelp.updateMongoId(localId, mongoId);
      }

      print(response.statusCode);
      print(response.body);
      return mongoId != null;
    } catch (e) {
      print('Sync failed: $e');
      // Expense stays local, marked as not synced
      return false;
    }
  }

  static Future<void> syncPendingExpenses() async {
    final pendingExpenses = await DatabaseHelp.getUnsyncedData();

    for (final expense in pendingExpenses) {
      try {
        final mongoId = expense['mongoId'] as String?;
        if (mongoId == null || mongoId.isEmpty) {
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
      } catch (e) {
        print('Pending sync failed: $e');
      }
    }
  }
}

// void main() async {
//   for (int index = 0; index <= 10; index++) {
//     await Throw.createUser(index, 'Nigga $index', '4', 'nigga', 'nigga', 'nigga');
//   }
//   ;

//   // for (int index = 0; index<=10; index++){
//   //   deleteUserByLocalId(index);

//   // }
//   // await getUsers();
// }
