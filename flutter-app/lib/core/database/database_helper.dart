import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Database helper for managing SQLite database
/// Handles table creation, migrations, and database initialization
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  factory DatabaseHelper() => instance;

  /// Get database instance (lazy initialization)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'lexilingo_chat.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create tables on first database creation
  Future<void> _onCreate(Database db, int version) async {
    await _createChatSessionsTable(db);
    await _createChatMessagesTable(db);
    await _createAIAnalysisResultsTable(db);
    await _createIndexes(db);
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here in the future
    if (oldVersion < 2) {
      // Example: add new column or table
    }
  }

  /// Create chat_sessions table
  Future<void> _createChatSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE chat_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_message_at INTEGER,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');
  }

  /// Create chat_messages table
  Future<void> _createChatMessagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        content TEXT NOT NULL,
        role TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        error TEXT,
        FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Create ai_analysis_results table
  Future<void> _createAIAnalysisResultsTable(Database db) async {
    await db.execute('''
      CREATE TABLE ai_analysis_results (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        fluency_score REAL,
        fluency_level TEXT,
        vocabulary_level TEXT,
        vocabulary_confidence REAL,
        corrected_text TEXT,
        analysis_data TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Create indexes for better query performance
  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX idx_messages_session 
      ON chat_messages(session_id, timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_sessions_user 
      ON chat_sessions(user_id, last_message_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_analysis_message 
      ON ai_analysis_results(message_id)
    ''');
  }

  /// Close database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Delete database (for testing/reset purposes)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'lexilingo_chat.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

  /// Clear all data but keep tables (for testing)
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('ai_analysis_results');
      await txn.delete('chat_messages');
      await txn.delete('chat_sessions');
    });
  }
}
