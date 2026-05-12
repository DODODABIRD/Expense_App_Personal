import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'ApiService.dart';
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
      version: 1,
      onCreate: (db , version) async {
        await db.execute('''
              CREATE TABLE my_table (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT,
                amount TEXT,
                date TEXT,
                category TEXT,
                type TEXT
              )
          ''');
      },

    );

    return _db!;
  }

  static Future<int> insertData(String name, String amount, String date, String category, String type) async{
    final db = await initDB();
    final listShit = {
       'name' : name,
       'amount' : amount,
       'date' : date,
       'category' : category,
       'type' : type
      };
    
    final int insertId =  await db.insert(
      'my_table', listShit,
      conflictAlgorithm: ConflictAlgorithm.replace
    );
    try{
      Throw.createExpense(insertId, name, amount, category, type, date);
    }catch(e){
      print('No Connection Bitch');
    }

    // try{
    //   sendExpenseToNeon(id:insertId, name: name, amount: amount, category: category, type: type, createdAt: date);
    // }catch(e){
    //   print('the Upload aint working');
    // }

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
        String amount,
        String category,
        String type,
    ) async{
    final db = await initDB();
    final Map<String,dynamic> _values = {
      'name':name,
      'amount':amount,
      'category':category,
      'type':type,
    };
    db.update('my_table', _values, where: 'id = ?', whereArgs: [id]);

    try{
      Throw.updateUserByLocalId(id, name, amount, category, type);
    }catch(e){
      print('Nigga this shit aint updated');
    }
  }

  static Future<List<Map<String, dynamic>>> getData() async {
    final db = await initDB();
    return await db.query('my_table');
  }

  static Future<void> deleteTs(int? id) async{
    final db = await initDB();
    try{
      db.delete('my_table',where:'id = ?', whereArgs: [id]);
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

