import 'package:http/http.dart' as http;
import 'dart:convert';
import 'databaseHelper.dart';

const String baseUrl = "https://expense-app-personal.vercel.app/api";

class Throw {
  static Future<void> getUsers() async {
    final url = Uri.parse('$baseUrl/users');

    final response = await http.get(url);

    print(response.statusCode);
    print(response.body);
  }

  Future<void> getUserById(String id) async {
    final url = Uri.parse('$baseUrl/users/$id');

    final response = await http.get(url);

    print(response.statusCode);
    print(response.body);
  }

  Future<void> updateUser(String id) async {
    final url = Uri.parse('$baseUrl/users/$id');

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"name": "Updated Name"}),
    );

    print(response.statusCode);
    print(response.body);
  }

  Future<void> deleteUser(String id) async {
    final url = Uri.parse('$baseUrl/users/$id');

    final response = await http.delete(url);

    print(response.statusCode);
    print(response.body);
  }

  static Future<String?> getMongoIdFromLocalId(int localId) async {
    final url = Uri.parse('$baseUrl/users/local/$localId');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['_id']; // ✅ Mongo ObjectId
    }

    print('User not found');
    return null;
  }

  static Future<void> updateUserByLocalId(
    int? localId,
    String name,
    int amount,        // ← Change from String to int
    String category,
    String type,
    String date
  ) async {
    final mongoId = await getMongoIdFromLocalId(localId!);

    if (mongoId == null) return;

    final url = Uri.parse('$baseUrl/users/$mongoId');

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "name": name,
        "amount": amount,
        "category": category,
        "type": type,
        "date": date,
      }),
    );

    print(response.statusCode);
    print(response.body);
  }

  static Future<void> deleteUserByLocalId(int localId) async {
    final mongoId = await getMongoIdFromLocalId(localId);

    if (mongoId == null) return;

    final url = Uri.parse('$baseUrl/users/$mongoId');

    final response = await http.delete(url);

    print(response.statusCode);
    print(response.body);
  }

  static Future<void> createExpense(
    int localId,
    String name,
    int amount,        // ← Change from String to int
    String category,
    String type,
    String date,
  ) async {
    final url = Uri.parse('$baseUrl/expenses');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "localId": localId,
          "name": name,
          "amount": amount,
          "category": category,
          "type": type,
          "date": date,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final mongoResponse = jsonDecode(response.body);
        final mongoId = mongoResponse['_id'];
        
        // ✅ Store mongoId back to SQLite
        await DatabaseHelp.updateMongoId(localId, mongoId);
      }

      print(response.statusCode);
      print(response.body);
    } catch (e) {
      print('Sync failed: $e');
      // Expense stays local, marked as not synced
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
