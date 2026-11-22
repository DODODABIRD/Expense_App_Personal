import 'dart:async';
import 'dart:math';
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
      return _db!;
    }
    String path = join(
      await getDatabasesPath(),
      'my_db.db',
    ); // Basically, join itu menggabungkan dua string jadi satu. kayak naro di ujung gitu kayak print gitu
    _db = await openDatabase(
      path,
      version: 7,
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
        if (oldVersion < 7) {
          for (final column in const [
            'rawTitle TEXT',
            'rawText TEXT',
            'notificationKey TEXT',
            "status TEXT NOT NULL DEFAULT 'ready'",
            "aiStatus TEXT NOT NULL DEFAULT 'done'",
            'aiAttempts INTEGER NOT NULL DEFAULT 0',
            'aiNextRetryAt INTEGER NOT NULL DEFAULT 0',
            'userEdited INTEGER NOT NULL DEFAULT 0',
          ]) {
            await db.execute(
              'ALTER TABLE $_pendingNotificationsTable ADD COLUMN $column',
            );
          }
          await _createPendingNotificationIndex(db);
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
        receivedAt TEXT NOT NULL,
        rawTitle TEXT,
        rawText TEXT,
        notificationKey TEXT,
        status TEXT NOT NULL DEFAULT 'ready',
        aiStatus TEXT NOT NULL DEFAULT 'done',
        aiAttempts INTEGER NOT NULL DEFAULT 0,
        aiNextRetryAt INTEGER NOT NULL DEFAULT 0,
        userEdited INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createPendingNotificationIndex(db);
  }

  // Persistent de-duplication: the native queue may redeliver a notification
  // after a crash, and the same key must never create a second draft.
  static Future<void> _createPendingNotificationIndex(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_notification_key
      ON $_pendingNotificationsTable (ownerId, notificationKey)
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

  /// Stable per-install identifier used by the admin panel to show the last
  /// sync time of each device.
  static Future<String> getOrCreateDeviceId() async {
    final existing = await getSetting('device_id');
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final id =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$random';
    await setSetting('device_id', id);
    return id;
  }

  static Future<int> getLocalExpenseCount() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return 0;

    final db = await initDB();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM my_table WHERE ownerId = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
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
    String? rawTitle,
    String? rawText,
    String? notificationKey,
    String status = 'ready',
    String aiStatus = 'done',
  }) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) throw StateError('You must be signed in');
    final needsInput = status == 'needs_input';
    if (name.trim().isEmpty || (amount <= 0 && !needsInput)) {
      throw ArgumentError('A pending expense requires a name and amount');
    }

    final db = await initDB();
    // Returns 0 when this notificationKey already has a draft.
    return db.insert(_pendingNotificationsTable, {
      'ownerId': userId,
      'name': name.trim(),
      'amount': amount < 0 ? 0 : amount,
      'date': date,
      'category': category,
      'type': type,
      'sourceApp': sourceApp,
      'receivedAt': receivedAt.toIso8601String(),
      'rawTitle': rawTitle,
      'rawText': rawText,
      'notificationKey': notificationKey,
      'status': status,
      'aiStatus': aiStatus,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Drafts still waiting for AI enrichment whose retry time has come.
  static Future<List<Map<String, dynamic>>> getPendingAiEnrichment(
    int nowMs,
  ) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return [];

    final db = await initDB();
    return db.query(
      _pendingNotificationsTable,
      where: "ownerId = ? AND aiStatus = 'pending' AND aiNextRetryAt <= ?",
      whereArgs: [userId, nowMs],
      orderBy: 'id ASC',
    );
  }

  /// Applies an AI result to a draft. Never touches a draft the user edited,
  /// and only fills the amount while the draft still needs input.
  static Future<bool> applyAiEnrichment({
    required int id,
    required String name,
    required int amount,
    required String category,
    required String type,
  }) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return false;

    final db = await initDB();
    final updated = await db.rawUpdate(
      '''
      UPDATE $_pendingNotificationsTable SET
        name = ?,
        category = ?,
        type = ?,
        amount = CASE WHEN status = 'needs_input' THEN ? ELSE amount END,
        status = 'ready',
        aiStatus = 'done'
      WHERE id = ? AND ownerId = ? AND userEdited = 0
      ''',
      [name, category, type, amount, id, userId],
    );
    if (updated == 0) {
      // Edited by the user (or discarded): stop asking the AI.
      await db.update(
        _pendingNotificationsTable,
        {'aiStatus': 'done'},
        where: 'id = ? AND ownerId = ?',
        whereArgs: [id, userId],
      );
    }
    return updated > 0;
  }

  static Future<void> markPendingAiAttemptFailed({
    required int id,
    required int attempts,
    required int nextRetryAtMs,
    required bool giveUp,
  }) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return;

    final db = await initDB();
    await db.update(
      _pendingNotificationsTable,
      {
        'aiAttempts': attempts,
        'aiNextRetryAt': nextRetryAtMs,
        'aiStatus': giveUp ? 'failed' : 'pending',
      },
      where: 'id = ? AND ownerId = ?',
      whereArgs: [id, userId],
    );
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
        'status': 'ready',
        'userEdited': 1,
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
      if (amount <= 0) return;
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

  static Future<void> markSynced(int localId) async {
    final db = await initDB();
    await db.update(
      'my_table',
      {'synced': 1},
      where: 'id = ? AND ownerId = ?',
      whereArgs: [localId, AuthService.currentUser?.uid],
    );
  }

  static Future<void> markManySynced(Iterable<int> localIds) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return;
    final ids = localIds.toSet().toList();
    if (ids.isEmpty) return;

    final db = await initDB();
    await db.transaction((txn) async {
      const batchSize = 900;
      for (var i = 0; i < ids.length; i += batchSize) {
        final chunk = ids.sublist(
          i,
          i + batchSize > ids.length ? ids.length : i + batchSize,
        );
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await txn.rawUpdate(
          'UPDATE my_table SET synced = 1 WHERE ownerId = ? AND id IN ($placeholders)',
          [userId, ...chunk],
        );
      }
    });
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
      columns: ['id'],
      where: 'ownerId = ?',
      whereArgs: [userId],
    );
    final localIds = localRows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();

    var imported = 0;
    for (final onlineExpense in onlineExpenses) {
      final localId = onlineExpense['localId']?.toString();
      if (localId == null || localIds.contains(localId)) continue;

      final parsedId = int.tryParse(localId);
      await db.insert(
        'my_table',
        {
          'id': ?parsedId,
          'ownerId': userId,
          'name': onlineExpense['name']?.toString() ?? 'Unknown',
          'amount': onlineExpense['amount'] is num
              ? (onlineExpense['amount'] as num).toInt()
              : int.tryParse(onlineExpense['amount']?.toString() ?? '0') ?? 0,
          'date': onlineExpense['date']?.toString() ?? '',
          'category': onlineExpense['category']?.toString() ?? 'general',
          'type': onlineExpense['type']?.toString() ?? 'expected',
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      localIds.add(localId);
      imported++;
    }
    return imported;
  }

  /// Returns the subset of [expenses] that does not already exist locally for
  /// the current user (exact match on name, amount, date, category and type).
  static Future<List<Map<String, dynamic>>> filterNewExpenses(
    List<Map<String, dynamic>> expenses,
  ) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return [];

    final db = await initDB();
    final existing = await db.query(
      'my_table',
      where: 'ownerId = ?',
      whereArgs: [userId],
    );
    final seen = existing.map(_expenseIdentity).toSet();

    final fresh = <Map<String, dynamic>>[];
    for (final expense in expenses) {
      if (seen.add(_expenseIdentity(expense))) fresh.add(expense);
    }
    return fresh;
  }

  /// Inserts expenses restored from a PDF backup and pushes them to the
  /// server. Rows stay marked as unsynced until the push succeeds, so the
  /// regular pending-sync retries pick them up when offline.
  static Future<void> insertRestoredExpenses(
    List<Map<String, dynamic>> expenses,
  ) async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return;

    final db = await initDB();
    final batch = db.batch();
    for (final expense in expenses) {
      batch.insert('my_table', {
        'ownerId': userId,
        'name': expense['name']?.toString() ?? 'Unknown',
        'amount': expense['amount'] is int
            ? expense['amount'] as int
            : int.tryParse(expense['amount']?.toString() ?? '0') ?? 0,
        'date': expense['date']?.toString() ?? '',
        'category': expense['category']?.toString() ?? 'general',
        'type': expense['type']?.toString() ?? 'others',
        'synced': 0,
      });
    }
    await batch.commit(noResult: true);
    unawaited(Throw.syncPendingExpenses());
  }

  static String _expenseIdentity(Map<String, dynamic> expense) {
    return [
      expense['name']?.toString().trim(),
      expense['amount']?.toString(),
      expense['date']?.toString().trim(),
      expense['category']?.toString().trim().toLowerCase(),
      expense['type']?.toString().trim().toLowerCase(),
    ].join('|');
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    final db = await initDB();
    return await db.query(
      'my_table',
      where: 'synced = ? AND ownerId = ?',
      whereArgs: [0, AuthService.currentUser?.uid],
    );
  }

  static Future<int> getUnsyncedCount() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return 0;

    final db = await initDB();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM my_table WHERE synced = 0 AND ownerId = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Marks every expense of the current user as needing a server push.
  static Future<void> markAllUnsyncedForCurrentUser() async {
    final db = await initDB();
    await db.update(
      'my_table',
      {'synced': 0},
      where: 'ownerId = ?',
      whereArgs: [AuthService.currentUser?.uid],
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
