import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'background_sync_queue_service.dart';
import 'encrypted_local_cache_service.dart';
import 'local_cache_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  // Database type constants
  static const String idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
  static const String textType = 'TEXT NOT NULL';
  static const String textNullable = 'TEXT';
  static const String boolType = 'BOOLEAN NOT NULL';
  static const String intType = 'INTEGER NOT NULL';

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
      version: 6,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE courses ADD COLUMN imageUrl TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN category TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN duration TEXT');
      await db.execute(
        'ALTER TABLE courses ADD COLUMN lessonsCount INTEGER DEFAULT 0',
      );
    }

    if (oldVersion < 3) {
      await _createUsersTable(db);
      await _createSettingsTable(db);
      await _createDailyGoalsTable(db);
      await _createStreaksTable(db);
      await _createCourseEnrollmentsTable(db);

      // Update existing tables
      await db.execute(
        'ALTER TABLE lessons ADD COLUMN status TEXT DEFAULT "locked"',
      );
      await db.execute('ALTER TABLE chat_history ADD COLUMN sessionId TEXT');
      await db.execute('ALTER TABLE chat_history ADD COLUMN userId TEXT');
    }

    if (oldVersion < 4) {
      // Align courses table with data source expectations
      await db.execute(
        'ALTER TABLE courses ADD COLUMN isEnrolled INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE courses ADD COLUMN progress REAL DEFAULT 0.0',
      );
    }

    if (oldVersion < 5) {
      // Phase 0: API cache table for offline-first content features
      await LocalCacheService.createTable(db);
    }

    if (oldVersion < 6) {
      // Phase 2: Encrypted cache + persistent sync queue
      await EncryptedLocalCacheService.createTable(db);
      await BackgroundSyncQueueService.createTable(db);
    }
  }

  Future _createDB(Database db, int version) async {
    // Create all tables
    await _createUsersTable(db);
    await _createSettingsTable(db);
    await _createDailyGoalsTable(db);
    await _createStreaksTable(db);
    await _createVocabularyTable(db);
    await _createChatHistoryTable(db);
    await _createCoursesTable(db);
    await _createLessonsTable(db);
    await _createUserProgressTable(db);
    await _createCourseEnrollmentsTable(db);

    // Phase 0: API cache table
    await LocalCacheService.createTable(db);

    // Phase 2: Encrypted cache and background sync queue
    await EncryptedLocalCacheService.createTable(db);
    await BackgroundSyncQueueService.createTable(db);

    // Seed rich local learning data for mobile-first experience.
    await _seedInitialData(db);
  }

  // Users table
  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  avatarUrl TEXT,
  joinDate TEXT NOT NULL,
  lastLoginDate TEXT,
  totalXP INTEGER DEFAULT 0,
  currentStreak INTEGER DEFAULT 0,
  longestStreak INTEGER DEFAULT 0,
  totalLessonsCompleted INTEGER DEFAULT 0,
  totalWordsLearned INTEGER DEFAULT 0
)
''');
  }

  // Settings table
  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
CREATE TABLE settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId TEXT NOT NULL,
  notificationEnabled BOOLEAN DEFAULT 1,
  notificationTime TEXT DEFAULT "09:00",
  theme TEXT DEFAULT "system",
  language TEXT DEFAULT "en",
  soundEnabled BOOLEAN DEFAULT 1,
  dailyGoalXP INTEGER DEFAULT 50,
  FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
)
''');
  }

  // Daily Goals table
  Future<void> _createDailyGoalsTable(Database db) async {
    await db.execute('''
CREATE TABLE daily_goals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId TEXT NOT NULL,
  date TEXT NOT NULL,
  targetXP INTEGER DEFAULT 50,
  earnedXP INTEGER DEFAULT 0,
  lessonsCompleted INTEGER DEFAULT 0,
  wordsLearned INTEGER DEFAULT 0,
  minutesSpent INTEGER DEFAULT 0,
  FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(userId, date)
)
''');
  }

  // Streaks table
  Future<void> _createStreaksTable(Database db) async {
    await db.execute('''
CREATE TABLE streaks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId TEXT NOT NULL,
  date TEXT NOT NULL,
  completed BOOLEAN DEFAULT 0,
  FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(userId, date)
)
''');
  }

  // Course Enrollments table
  Future<void> _createCourseEnrollmentsTable(Database db) async {
    await db.execute('''
CREATE TABLE course_enrollments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId TEXT NOT NULL,
  courseId INTEGER NOT NULL,
  enrolledAt TEXT NOT NULL,
  lastAccessedAt TEXT,
  completedAt TEXT,
  currentProgress REAL DEFAULT 0.0,
  FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (courseId) REFERENCES courses(id) ON DELETE CASCADE,
  UNIQUE(userId, courseId)
)
''');
  }

  // Vocabulary table
  Future<void> _createVocabularyTable(Database db) async {
    await db.execute('''
CREATE TABLE vocabulary (
  id $idType,
  userId TEXT,
  word $textType,
  definition $textType,
  example TEXT,
  phonetic TEXT,
  audioUrl TEXT,
  partOfSpeech TEXT,
  difficulty TEXT,
  isLearned $boolType,
  isFavorite BOOLEAN DEFAULT 0,
  createdAt TEXT,
  lastReviewedAt TEXT,
  FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
)
''');
  }

  // Chat History table
  Future<void> _createChatHistoryTable(Database db) async {
    await db.execute('''
CREATE TABLE chat_history (
  id $idType,
  userId TEXT,
  sessionId TEXT,
  message $textType,
  isUser $boolType,
  timestamp $textType,
  FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
)
''');
  }

  // Courses table
  Future<void> _createCoursesTable(Database db) async {
    await db.execute('''
CREATE TABLE courses (
  id $idType,
  title $textType,
  description $textType,
  level $textType,
  category $textNullable,
  imageUrl $textNullable,
  duration $textNullable,
  lessonsCount INTEGER DEFAULT 0,
  isEnrolled INTEGER DEFAULT 0,
  progress REAL DEFAULT 0.0,
  isFeatured BOOLEAN DEFAULT 0,
  rating REAL DEFAULT 0.0,
  enrolledCount INTEGER DEFAULT 0,
  createdAt TEXT,
  updatedAt TEXT
)
''');
  }

  // Lessons table
  Future<void> _createLessonsTable(Database db) async {
    await db.execute('''
CREATE TABLE lessons (
  id $idType,
  courseId $intType,
  title $textType,
  description $textNullable,
  orderIndex INTEGER DEFAULT 0,
  duration $textNullable,
  status TEXT DEFAULT "locked",
  contentUrl $textNullable,
  FOREIGN KEY (courseId) REFERENCES courses (id) ON DELETE CASCADE
)
''');
  }

  // User Progress table
  Future<void> _createUserProgressTable(Database db) async {
    await db.execute('''
CREATE TABLE user_progress (
  id $idType,
  userId TEXT NOT NULL,
  courseId $intType,
  lessonId $intType,
  progress REAL DEFAULT 0.0,
  lastAccessedAt TEXT,
  completedAt $textNullable,
  FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
  FOREIGN KEY (courseId) REFERENCES courses (id) ON DELETE CASCADE,
  FOREIGN KEY (lessonId) REFERENCES lessons (id) ON DELETE CASCADE,
  UNIQUE(userId, lessonId)
)
''');
  }

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    const users = [
      {
        'id': 'demo_user_001',
        'name': 'Alex Nguyen',
        'email': 'alex.nguyen@lexilingo.app',
        'avatarUrl': 'https://ui-avatars.com/api/?name=Alex+Nguyen&background=6366f1&color=fff',
        'totalXP': 1240,
        'currentStreak': 8,
        'longestStreak': 21,
        'totalLessonsCompleted': 42,
        'totalWordsLearned': 320,
      },
      {
        'id': 'demo_user_002',
        'name': 'Minh Tran',
        'email': 'minh.tran@lexilingo.app',
        'avatarUrl': 'https://ui-avatars.com/api/?name=Minh+Tran&background=14b8a6&color=fff',
        'totalXP': 860,
        'currentStreak': 5,
        'longestStreak': 13,
        'totalLessonsCompleted': 28,
        'totalWordsLearned': 210,
      },
      {
        'id': 'demo_user_003',
        'name': 'Linh Pham',
        'email': 'linh.pham@lexilingo.app',
        'avatarUrl': 'https://ui-avatars.com/api/?name=Linh+Pham&background=f97316&color=fff',
        'totalXP': 430,
        'currentStreak': 2,
        'longestStreak': 7,
        'totalLessonsCompleted': 14,
        'totalWordsLearned': 98,
      },
    ];

    for (final user in users) {
      await db.insert('users', {
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
        'avatarUrl': user['avatarUrl'],
        'joinDate': now.subtract(const Duration(days: 60)).toIso8601String(),
        'lastLoginDate': timestamp,
        'totalXP': user['totalXP'],
        'currentStreak': user['currentStreak'],
        'longestStreak': user['longestStreak'],
        'totalLessonsCompleted': user['totalLessonsCompleted'],
        'totalWordsLearned': user['totalWordsLearned'],
      });

      await db.insert('settings', {
        'userId': user['id'],
        'notificationEnabled': 1,
        'notificationTime': '08:30',
        'theme': 'system',
        'language': 'en',
        'soundEnabled': 1,
        'dailyGoalXP': 80,
      });

      await db.insert('daily_goals', {
        'userId': user['id'],
        'date': todayStr,
        'targetXP': 80,
        'earnedXP': user['id'] == 'demo_user_001' ? 55 : 35,
        'lessonsCompleted': user['id'] == 'demo_user_001' ? 3 : 2,
        'wordsLearned': user['id'] == 'demo_user_001' ? 18 : 11,
        'minutesSpent': user['id'] == 'demo_user_001' ? 42 : 27,
      });
    }

    for (int i = 0; i < 14; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await db.insert('streaks', {
        'userId': 'demo_user_001',
        'date': dateStr,
        'completed': i < 8 ? 1 : 0,
      });
    }

    final courseSeed = [
      ['English Foundations A1', 'A1', 'Grammar', 14, 4.7, 2100],
      ['Daily Conversation A1', 'A1', 'Conversation', 12, 4.6, 1980],
      ['Grammar Booster A2', 'A2', 'Grammar', 18, 4.8, 1670],
      ['Travel English A2', 'A2', 'Travel', 15, 4.5, 1440],
      ['Listening Sprint A2', 'A2', 'Listening', 16, 4.4, 1210],
      ['Speaking Lab B1', 'B1', 'Speaking', 20, 4.8, 1890],
      ['Business Email B1', 'B1', 'Business', 17, 4.7, 1340],
      ['Workplace English B1', 'B1', 'Business', 19, 4.6, 1120],
      ['Academic Writing B2', 'B2', 'Writing', 22, 4.9, 980],
      ['IELTS Skills B2', 'B2', 'Test Prep', 24, 4.8, 1760],
      ['TOEIC Accelerator B2', 'B2', 'Test Prep', 21, 4.6, 1530],
      ['Advanced Discussion C1', 'C1', 'Conversation', 20, 4.7, 820],
      ['Pronunciation Mastery B2', 'B2', 'Pronunciation', 18, 4.8, 1320],
      ['News Reading B2', 'B2', 'Reading', 16, 4.5, 1010],
      ['Storytelling English B1', 'B1', 'Speaking', 14, 4.6, 970],
      ['Grammar Precision C1', 'C1', 'Grammar', 23, 4.9, 760],
      ['Vocabulary Builder A2', 'A2', 'Vocabulary', 18, 4.7, 1740],
      ['Idioms in Context B2', 'B2', 'Vocabulary', 15, 4.6, 920],
      ['Interview English B2', 'B2', 'Business', 13, 4.7, 1110],
      ['Presentation Skills C1', 'C1', 'Business', 14, 4.8, 690],
    ];

    final insertedCourseIds = <int>[];
    for (int i = 0; i < courseSeed.length; i++) {
      final item = courseSeed[i];
      final id = await db.insert('courses', {
        'title': item[0],
        'description':
            'A practical, structured course to improve ${item[2]} for ${item[1]} learners with speaking, listening, and review checkpoints.',
        'level': item[1],
        'category': item[2],
        'imageUrl': 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=1200&auto=format&fit=crop&q=80',
        'duration': '${4 + (i % 7)} weeks',
        'lessonsCount': item[3],
        'isEnrolled': i < 6 ? 1 : 0,
        'progress': i == 0 ? 0.62 : (i < 6 ? 0.22 : 0.0),
        'isFeatured': i % 4 == 0 ? 1 : 0,
        'rating': item[4],
        'enrolledCount': item[5],
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
      insertedCourseIds.add(id);
    }

    for (final courseId in insertedCourseIds) {
      final courseRow = await db.query(
        'courses',
        columns: ['lessonsCount'],
        where: 'id = ?',
        whereArgs: [courseId],
        limit: 1,
      );
      final lessonsCount = (courseRow.first['lessonsCount'] as int?) ?? 12;
      for (int order = 1; order <= lessonsCount; order++) {
        await db.insert('lessons', {
          'courseId': courseId,
          'title': 'Lesson $order',
          'description': 'Core practice for lesson $order',
          'orderIndex': order,
          'duration': '${8 + (order % 10)} min',
          'status': order <= 3 ? 'completed' : (order <= 5 ? 'unlocked' : 'locked'),
          'contentUrl': '/local/courses/$courseId/lessons/$order',
        });
      }
    }

    for (int i = 0; i < 6 && i < insertedCourseIds.length; i++) {
      final enrolledAt = now.subtract(Duration(days: 10 - i)).toIso8601String();
      await db.insert('course_enrollments', {
        'userId': 'demo_user_001',
        'courseId': insertedCourseIds[i],
        'enrolledAt': enrolledAt,
        'lastAccessedAt': timestamp,
        'currentProgress': i == 0 ? 0.62 : 0.18 + (i * 0.05),
      });
    }

    final seededLessons = await db.query(
      'lessons',
      columns: ['id', 'courseId', 'orderIndex'],
      where: 'courseId IN (?, ?, ?)',
      whereArgs: [insertedCourseIds[0], insertedCourseIds[1], insertedCourseIds[2]],
      orderBy: 'courseId ASC, orderIndex ASC',
    );
    for (final lesson in seededLessons) {
      final order = (lesson['orderIndex'] as int?) ?? 1;
      await db.insert('user_progress', {
        'userId': 'demo_user_001',
        'courseId': lesson['courseId'],
        'lessonId': lesson['id'],
        'progress': order <= 3 ? 1.0 : (order <= 5 ? 0.55 : 0.0),
        'lastAccessedAt': timestamp,
        'completedAt': order <= 3 ? now.subtract(Duration(days: 2)).toIso8601String() : null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    final vocabSeed = [
      ['analyze', 'to examine carefully and in detail', 'We analyze the text before writing.'],
      ['collaborate', 'to work jointly with others', 'Students collaborate on the speaking task.'],
      ['achievement', 'something accomplished successfully', 'Finishing the course is a big achievement.'],
      ['improve', 'to become better', 'Daily practice helps improve fluency.'],
      ['confident', 'feeling sure about your abilities', 'She feels confident speaking English now.'],
      ['context', 'the situation that helps explain meaning', 'Use words in context to remember better.'],
      ['pronunciation', 'the way words are spoken', 'Clear pronunciation improves communication.'],
      ['strategy', 'a plan for achieving a goal', 'Use a strategy to learn vocabulary faster.'],
      ['persist', 'to continue despite difficulty', 'Persist with study even on busy days.'],
      ['insight', 'a deep understanding', 'The article gave me insight into grammar.'],
      ['efficient', 'achieving maximum productivity', 'Spaced repetition is an efficient method.'],
      ['practical', 'useful in real situations', 'This lesson gives practical phrases.'],
    ];

    for (int i = 0; i < vocabSeed.length; i++) {
      final item = vocabSeed[i];
      await db.insert('vocabulary', {
        'userId': 'demo_user_001',
        'word': item[0],
        'definition': item[1],
        'example': item[2],
        'phonetic': '/${item[0]}/',
        'partOfSpeech': i % 3 == 0 ? 'verb' : (i % 3 == 1 ? 'noun' : 'adjective'),
        'difficulty': i < 4 ? 'beginner' : (i < 8 ? 'intermediate' : 'advanced'),
        'isLearned': i < 7 ? 1 : 0,
        'isFavorite': i % 4 == 0 ? 1 : 0,
        'createdAt': timestamp,
      });
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }

  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'lexilingo.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}
