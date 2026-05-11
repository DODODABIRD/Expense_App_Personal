import 'package:http/http.dart' as http;
import 'dart:convert';

const String baseUrl = "https://expense-app-personal.vercel.app/api";

Future<void> getUsers() async {
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

Future<void> createUser() async {
  final url = Uri.parse('$baseUrl/users');

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({"name": "Orlando"}),
  );

  print(response.statusCode);
  print(response.body);
}

void main() async {
  await createUser();
  await getUsers();
}
