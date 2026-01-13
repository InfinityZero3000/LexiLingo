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
      version: 3, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE courses ADD COLUMN imageUrl TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN category TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN duration TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN lessonsCount INTEGER DEFAULT 0');
    }
    
    if (oldVersion < 3) {
      await _createUsersTable(db);
      await _createSettingsTable(db);
      await _createDailyGoalsTable(db);
      await _createStreaksTable(db);
      await _createCourseEnrollmentsTable(db);
      
      // Update existing tables
      await db.execute('ALTER TABLE lessons ADD COLUMN status TEXT DEFAULT "locked"');
      await db.execute('ALTER TABLE chat_history ADD COLUMN sessionId TEXT');
      await db.execute('ALTER TABLE chat_history ADD COLUMN userId TEXT');
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const boolType = 'BOOLEAN NOT NULL';
    const intType = 'INTEGER NOT NULL';

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

    // Seed initial data
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
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const boolType = 'BOOLEAN NOT NULL';

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
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const boolType = 'BOOLEAN NOT NULL';

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
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';

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
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

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
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const intType = 'INTEGER NOT NULL';

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
    final timestamp = DateTime.now().toIso8601String();
    
    // Create demo user
    await db.insert('users', {
      'id': 'demo_user_001',
      'name': 'Demo User',
      'email': 'demo@lexilingo.com',
      'avatarUrl': 'https://ui-avatars.com/api/?name=Demo+User&background=6366f1&color=fff',
      'joinDate': timestamp,
      'lastLoginDate': timestamp,
      'totalXP': 150,
      'currentStreak': 3,
      'longestStreak': 7,
      'totalLessonsCompleted': 5,
      'totalWordsLearned': 25,
    });
    
    // Create settings for demo user
    await db.insert('settings', {
      'userId': 'demo_user_001',
      'notificationEnabled': 1,
      'notificationTime': '09:00',
      'theme': 'system',
      'language': 'en',
      'soundEnabled': 1,
      'dailyGoalXP': 50,
    });
    
    // Create today's goal for demo user
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await db.insert('daily_goals', {
      'userId': 'demo_user_001',
      'date': todayStr,
      'targetXP': 50,
      'earnedXP': 30,
      'lessonsCompleted': 2,
      'wordsLearned': 10,
      'minutesSpent': 15,
    });
    
    // Create streak records for last 3 days
    for (int i = 0; i < 3; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await db.insert('streaks', {
        'userId': 'demo_user_001',
        'date': dateStr,
        'completed': 1,
      });
    }
    
    // Seed courses (without progress field)
    final courses = [
      {
        'title': 'English for Beginners',
        'description': 'Start your English learning journey with fundamental vocabulary and grammar.',
        'level': 'A1',
        'category': 'Language Basics',
        'imageUrl': 'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=400',
        'duration': '4 weeks',
        'lessonsCount': 12,
        'isFeatured': 1,
        'rating': 4.5,
        'enrolledCount': 1250,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
      {
        'title': 'Conversational English',
        'description': 'Learn practical English for everyday conversations and real-life situations.',
        'level': 'B1',
        'category': 'Speaking',
        'imageUrl': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400',
        'duration': '6 weeks',
        'lessonsCount': 18,
        'isFeatured': 1,
        'rating': 4.7,
        'enrolledCount': 980,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
      {
        'title': 'Business English',
        'description': 'Master professional English for workplace communication and presentations.',
        'level': 'B2',
        'category': 'Business',
        'imageUrl': 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?w=400',
        'duration': '8 weeks',
        'lessonsCount': 24,
        'isFeatured': 0,
        'rating': 4.8,
        'enrolledCount': 756,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
      {
        'title': 'IELTS Preparation',
        'description': 'Comprehensive preparation for all sections of the IELTS examination.',
        'level': 'B2-C1',
        'category': 'Test Prep',
        'imageUrl': 'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=400',
        'duration': '12 weeks',
        'lessonsCount': 36,
        'isFeatured': 1,
        'rating': 4.9,
        'enrolledCount': 2100,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
      {
        'title': 'English Grammar Mastery',
        'description': 'Deep dive into English grammar rules with practical exercises.',
        'level': 'A2-B1',
        'category': 'Grammar',
        'imageUrl': 'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=400',
        'duration': '5 weeks',
        'lessonsCount': 15,
        'isFeatured': 0,
        'rating': 4.6,
        'enrolledCount': 890,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
      {
        'title': 'Travel English',
        'description': 'Essential English phrases and vocabulary for travelers.',
        'level': 'A2',
        'category': 'Travel',
        'imageUrl': 'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400',
        'duration': '3 weeks',
        'lessonsCount': 9,
        'isFeatured': 0,
        'rating': 4.4,
        'enrolledCount': 1450,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ];

    for (var course in courses) {
      await db.insert('courses', course);
    }
    
    // Enroll demo user in first two courses
    await db.insert('course_enrollments', {
      'userId': 'demo_user_001',
      'courseId': 1, // English for Beginners
      'enrolledAt': timestamp,
      'lastAccessedAt': timestamp,
      'currentProgress': 0.35,
    });
    
    await db.insert('course_enrollments', {
      'userId': 'demo_user_001',
      'courseId': 2, // Conversational English
      'enrolledAt': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      'lastAccessedAt': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      'currentProgress': 0.15,
    });

    // Seed some vocabulary for demo user
    final vocabs = [
      {
        'userId': 'demo_user_001',
        'word': 'hello',
        'definition': 'A greeting used to acknowledge someone\'s presence or to begin a conversation.',
        'example': 'Hello! How are you today?',
        'phonetic': '/həˈloʊ/',
        'partOfSpeech': 'interjection',
        'difficulty': 'beginner',
        'isLearned': 1,
        'isFavorite': 0,
        'createdAt': timestamp,
      },
      {
        'userId': 'demo_user_001',
        'word': 'beautiful',
        'definition': 'Pleasing the senses or mind aesthetically.',
        'example': 'What a beautiful sunset!',
        'phonetic': '/ˈbjuːtɪfʊl/',
        'partOfSpeech': 'adjective',
        'difficulty': 'beginner',
        'isLearned': 0,
        'isFavorite': 1,
        'createdAt': timestamp,
      },
    ];

    for (var vocab in vocabs) {
      await db.insert('vocabulary', vocab);
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

