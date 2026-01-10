import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('lexilingo.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 1, 
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const boolType = 'BOOLEAN NOT NULL';

    await db.execute('''
CREATE TABLE vocabulary (
  id $idType,
  word $textType,
  definition $textType,
  example TEXT,
  isLearned $boolType
)
''');

    await db.execute('''
CREATE TABLE chat_history (
  id $idType,
  message $textType,
  isUser $boolType,
  timestamp $textType
)
''');

    // Seed courses data
    await db.execute('''
CREATE TABLE courses (
  id $idType,
  title $textType,
  description $textType,
  level $textType,
  progress REAL
)
''');
    
    await db.insert('courses', {'title': 'Beginner English', 'description': 'Start your journey here.', 'level': 'A1', 'progress': 0.0});
    await db.insert('courses', {'title': 'Intermediate Conversation', 'description': 'Speak with confidence.', 'level': 'B1', 'progress': 0.0});
  }
}
