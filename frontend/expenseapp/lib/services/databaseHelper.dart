import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'ApiService.dart';
import 'auth_service.dart';
import 'error_log_service.dart';

// import 'mongoServices.dart';
// import 'NeonDBHelper.dart';

class DatabaseHelp {
  static Database? _db;
  static const _pendingNotificationsTable = 'pending_notification_expenses';

  DatabaseHelp._privateConstructor();
  static final DatabaseHelp instance = DatabaseHelp._privateConstructor();
  //Inisialisasi Database
  static Future<Database> initDB() async {
    if (_db != null) {
      await _ensureSettingsTable(_db!);
      return _db!;
    }
    String path = join(
      await getDatabasesPath(),
      'my_db.db',
    ); // Basically, join itu menggabungkan dua string jadi satu. kayak naro di ujung gitu kayak print gitu
    _db = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
              CREATE TABLE my_table (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                mongoId TEXT,
                ownerId TEXT NOT NULL,
                name TEXT NOT NULL,
                amount INTEGER NOT NULL,
                date TEXT NOT NULL,
                category TEXT NOT NULL,
                type TEXT NOT NULL,
                synced INTEGER DEFAULT 0
              )
          ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await _createPendingNotificationTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE my_table ADD COLUMN mongoId TEXT');
          await db.execute(
            'ALTER TABLE my_table ADD COLUMN synced INTEGER DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE my_table ADD COLUMN ownerId TEXT');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 6) {
          await _createPendingNotificationTable(db);
        }
      },
    );

    await _ensureSettingsTable(_db!);
    return _db!;
  }

  static Future<void> _ensureSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createPendingNotificationTable(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_pendingNotificationsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ownerId TEXT NOT NULL,
        name TEXT NOT NULL,
        amount INTEGER NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        type TEXT NOT NULL,
        sourceApp TEXT NOT NULL,
        receivedAt TEXT NOT NULL
      )
    ''');
  }

  static Future<void> assignLegacyExpensesToCurrentUser() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return;

    final db = await initDB();
    await db.update('my_table', {'ownerId': userId}, where: 'ownerId IS NULL');
  }

  static Future<double?> getCachedExchangeRate(String currency) async {
    final db = await initDB();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['rate_$currency'],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : double.tryParse(rows.first['value'].toString());
  }

  static Future<String?> getSetting(String key) async {
    final db = await initDB();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await initDB();
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> cacheExchangeRate(String currency, double rate) async {
    final db = await initDB();
    await db.insert('app_settings', {
      'key': 'rate_$currency',
      'value': rate.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> insertData(
    String name,
    int amount,
    String date,
    String category,
    String type,
  ) async {
    final db = await initDB();

    final int insertId = await db.insert('my_table', {
      'ownerId': AuthService.currentUser?.uid,
      'name': name,
      'amount': amount,
      'date': date,
      'category': category,
      'type': type,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _syncCreatedExpense(insertId, name, amount, category, type, date);

    return insertId;
  }

  static Future<int> insertPendingNotificationExpense({
    required String name,
    required int amount,
    required String date,
    required String category,
    required String type,
    required String sourceApp,
    required DateTime receivedAt,
  }) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) throw StateError('You must be signed in');
    if (name.trim().isEmpty || amount <= 0) {
      throw ArgumentError('A pending expense requires a name and amount');
    }

    final db = await initDB();
    return db.insert(_pendingNotificationsTable, {
      'ownerId': userId,
      'name': name.trim(),
      'amount': amount,
      'date': date,
      'category': category,
      'type': type,
      'sourceApp': sourceApp,
      'receivedAt': receivedAt.toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>>
  getPendingNotificationExpenses() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return [];

    final db = await initDB();
    return db.query(
      _pendingNotificationsTable,
      where: 'ownerId = ?',
      whereArgs: [userId],
      orderBy: 'receivedAt DESC, id DESC',
    );
  }

  static Future<int> getPendingNotificationExpenseCount() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return 0;

    final db = await initDB();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_pendingNotificationsTable WHERE ownerId = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<int> updatePendingNotificationExpense({
    required int id,
    required String name,
    required int amount,
    required String date,
    required String category,
    required String type,
  }) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return 0;
    if (name.trim().isEmpty || amount <= 0) {
      throw ArgumentError('A pending expense requires a name and amount');
    }

    final db = await initDB();
    return db.update(
      _pendingNotificationsTable,
      {
        'name': name.trim(),
        'amount': amount,
        'date': date,
        'category': category,
        'type': type,
      },
      where: 'id = ? AND ownerId = ?',
      whereArgs: [id, userId],
    );
  }

  static Future<int> discardPendingNotificationExpense(int id) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return 0;

    final db = await initDB();
    return db.delete(
      _pendingNotificationsTable,
      where: 'id = ? AND ownerId = ?',
      whereArgs: [id, userId],
    );
  }

  static Future<bool> approvePendingNotificationExpense(int id) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return false;

    final db = await initDB();
    Map<String, dynamic>? approvedExpense;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _pendingNotificationsTable,
        where: 'id = ? AND ownerId = ?',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final pending = rows.first;
      final name = pending['name'] as String;
      final amount = pending['amount'] as int;
      final date = pending['date'] as String;
      final category = pending['category'] as String;
      final type = pending['type'] as String;
      final expenseId = await txn.insert('my_table', {
        'ownerId': userId,
        'name': name,
        'amount': amount,
        'date': date,
        'category': category,
        'type': type,
      });
      await txn.delete(
        _pendingNotificationsTable,
        where: 'id = ? AND ownerId = ?',
        whereArgs: [id, userId],
      );
      approvedExpense = {
        'id': expenseId,
        'name': name,
        'amount': amount,
        'date': date,
        'category': category,
        'type': type,
      };
    });

    if (approvedExpense == null) return false;
    _syncCreatedExpense(
      approvedExpense!['id'] as int,
      approvedExpense!['name'] as String,
      approvedExpense!['amount'] as int,
      approvedExpense!['category'] as String,
      approvedExpense!['type'] as String,
      approvedExpense!['date'] as String,
    );
    return true;
  }

  static void _syncCreatedExpense(
    int id,
    String name,
    int amount,
    String category,
    String type,
    String date,
  ) {
    unawaited(Throw.createExpense(id, name, amount, category, type, date));
  }

  /* Update Logic
  Get new name, new amount, new category, new type;
  New Date = Old Date;
  New Id = Old ID
  Database Update Query (ID = Old id)
  Insert(newName, newAmount, new Category, new Type)

*/
  static Future<void> updateTs(
    int? id,
    String name,
    int amount,
    String category,
    String type,
    String date,
  ) async {
    final db = await initDB();

    final Map<String, dynamic> values = {
      'name': name,
      'amount': amount,
      'category': category,
      'type': type,
      'date': date,
    };

    await db.update(
      'my_table',
      values,
      where: 'id = ? AND ownerId = ?',
      whereArgs: [id, AuthService.currentUser?.uid],
    );

    await db.update(
      'my_table',
      {'synced': 0},
      where: 'id = ? AND ownerId = ?',
      whereArgs: [id, AuthService.currentUser?.uid],
    );

    unawaited(
      Throw.updateUserByLocalId(
        id,
        name,
        amount,
        category,
        type,
        date,
      ).catchError((error, stackTrace) {
        captureAppError(error, stackTrace, 'Background expense update sync');
        print('Background update sync failed: $error');
        return false;
      }),
    );
  }

  static Future<void> updateMongoId(int localId, String mongoId) async {
    final db = await initDB();
    await db.update(
      'my_table',
      {'mongoId': mongoId, 'synced': 1},
      where: 'id = ? AND ownerId = ?',
      whereArgs: [localId, AuthService.currentUser?.uid],
    );
  }

  // TODO: Add conflict algorithm
  static Future<List<Map<String, dynamic>>> getData() async {
    final db = await initDB();
    return await db.query(
      'my_table',
      where: 'ownerId = ?',
      whereArgs: [AuthService.currentUser?.uid],
    );
  }

  static Future<int> importMissingExpenses(
    List<Map<String, dynamic>> onlineExpenses,
  ) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return 0;

    final db = await initDB();
    final localRows = await db.query(
      'my_table',
      columns: ['mongoId'],
      where: 'ownerId = ? AND mongoId IS NOT NULL',
      whereArgs: [userId],
    );
    final localMongoIds = localRows
        .map((row) => row['mongoId']?.toString())
        .whereType<String>()
        .toSet();

    var imported = 0;
    for (final onlineExpense in onlineExpenses) {
      final mongoId = onlineExpense['_id']?.toString();
      if (mongoId == null || localMongoIds.contains(mongoId)) continue;

      await db.insert('my_table', {
        'mongoId': mongoId,
        'ownerId': userId,
        'name': onlineExpense['name']?.toString() ?? 'Unknown',
        'amount': onlineExpense['amount'] is num
            ? (onlineExpense['amount'] as num).toInt()
            : int.tryParse(onlineExpense['amount']?.toString() ?? '0') ?? 0,
        'date': onlineExpense['date']?.toString() ?? '',
        'category': onlineExpense['category']?.toString() ?? 'general',
        'type': onlineExpense['type']?.toString() ?? 'expected',
        'synced': 1,
      });
      localMongoIds.add(mongoId);
      imported++;
    }
    return imported;
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    final db = await initDB();
    return await db.query(
      'my_table',
      where: 'synced = ? AND ownerId = ?',
      whereArgs: [0, AuthService.currentUser?.uid],
    );
  }

  static Future<void> deleteTs(int? id) async {
    final db = await initDB();
    try {
      db.delete(
        'my_table',
        where: 'id = ? AND ownerId = ?',
        whereArgs: [id, AuthService.currentUser?.uid],
      );
      print("Yo, that shit was a bussin move");
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Delete local expense');
      print('Yo, that deletion shit wasnt a success');
    }
    try {
      Throw.deleteUserByLocalId(id!);
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Delete online expense');
      print('No connection dawg');
    }
  }

  static Future<void> deleteAllForCurrentUser() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return;

    // Bulk-delete on the backend first; only wipe local data once the
    // server confirms success so nothing local is lost on failure.
    await Throw.deleteAllExpenses();

    final db = await initDB();
    await db.delete('my_table', where: 'ownerId = ?', whereArgs: [userId]);
    await db.delete(
      _pendingNotificationsTable,
      where: 'ownerId = ?',
      whereArgs: [userId],
    );
  }
}
