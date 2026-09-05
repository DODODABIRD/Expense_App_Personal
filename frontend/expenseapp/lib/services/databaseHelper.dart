import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'ApiService.dart';
import 'auth_service.dart';
// import 'mongoServices.dart';
// import 'NeonDBHelper.dart';



class DatabaseHelp{
  static Database? _db;

  DatabaseHelp._privateConstructor();
  static final DatabaseHelp instance = DatabaseHelp._privateConstructor();
  //Inisialisasi Database
  static Future<Database> initDB() async {
    if (_db != null) return _db!; // Kalau database udah ada langsung return database
    String path = join(await getDatabasesPath(), 'my_db.db'); // Basically, join itu menggabungkan dua string jadi satu. kayak naro di ujung gitu kayak print gitu
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db , version) async {
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE my_table ADD COLUMN mongoId TEXT');
          await db.execute('ALTER TABLE my_table ADD COLUMN synced INTEGER DEFAULT 0');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE my_table ADD COLUMN ownerId TEXT');
        }
      },
    );

    return _db!;
  }

  static Future<void> assignLegacyExpensesToCurrentUser() async {
    final userId = AuthService.currentUser?.uid;
    if (userId == null) return;

    final db = await initDB();
    await db.update(
      'my_table',
      {'ownerId': userId},
      where: 'ownerId IS NULL',
    );
  }

  static Future<int> insertData(
    String name,
    int amount,
    String date,
    String category,
    String type,
  ) async {
    final db = await initDB();

    final int insertId = await db.insert(
      'my_table',
      {
        'ownerId': AuthService.currentUser?.uid,
        'name': name,
        'amount': amount,
        'date': date,
        'category': category,
        'type': type,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    unawaited(Throw.createExpense(insertId, name, amount, category, type, date));

    return insertId;
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
      Throw.updateUserByLocalId(id, name, amount, category, type, date)
          .catchError((error) {
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

  static Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    final db = await initDB();
    return await db.query(
      'my_table',
      where: 'synced = ? AND ownerId = ?',
      whereArgs: [0, AuthService.currentUser?.uid],
    );
  }

  static Future<void> deleteTs(int? id) async{
    final db = await initDB();
    try{
      db.delete(
        'my_table',
        where: 'id = ? AND ownerId = ?',
        whereArgs: [id, AuthService.currentUser?.uid],
      );
      print("Yo, that shit was a bussin move");
    }catch(e){
      print('Yo, that deletion shit wasnt a success');
    }
    try{
      Throw.deleteUserByLocalId(id!);
    }catch(e){
      print('No connection dawg');
    }
  }
  
}

