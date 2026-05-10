import 'package:postgres/postgres.dart';


Future<void> sendExpenseToNeon({
  required int id, // Explicit integer type
  required String name,
  required String amount,
  required String category,
  required String type,
  required String createdAt,
}) async {
  try {
    // 1. Establish the connection with Neon required configurations
    final conn = await Connection.open(
      Endpoint(
        host: 'ep-lively-wind-ait5j0n4-pooler.c-4.us-east-1.aws.neon.tech',
        database: 'expenses',
        username: 'flutter_user',
        password: '@whatthefuck394',
        port: 5432,
      ),
      settings: const ConnectionSettings(
        sslMode: SslMode.require, // Neon requires SSL encryption
      ),
    );

    // 2. Prepare parameterized query using SQL naming conventions
    // "created_at" assumes standard snake_case column names in PostgreSQL
    final query = Sql.named(
      'INSERT INTO expense (id, name, amount, category, type, created_at) '
      'VALUES (@id, @name, @amount, @category, @type, @created_at)',
    );

    // 3. Bind your data into the query parameters map
    await conn.execute(
      query,
      parameters: {
        'id': id,
        'name': name,
        'amount': amount,
        'category': category,
        'type': type,
        'created_at': createdAt,
      },
    );

    print('Expense transaction inserted successfully.');

    // 4. Always safely shut down your connection pool socket
    await conn.close();

  } catch (error) {
    print('Failed to send data to Neon: $error');
  }
}
