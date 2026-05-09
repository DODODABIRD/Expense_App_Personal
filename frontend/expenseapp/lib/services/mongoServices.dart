//mongodb+srv://orlando:<db_password>@do2d.ypoboeu.mongodb.net/?appName=Do2d

import 'package:mongo_dart/mongo_dart.dart';

class Mongo{
  static Future<void> insertShit(Map<String,dynamic> tshit) async{
    final _db = await Db.create('mongodb+srv://flutterapp:flutterapp@do2d.ypoboeu.mongodb.net/expense?appName=Do2d');
    await _db.open();

    final _collection = _db.collection('user0');
    _collection.insert(tshit);
    print('Nigga berhasil');
  }
}