import 'database_helper.dart';
import '../../features/course/data/models/course_model.dart';

/// Service for importing and managing course data
/// This is like an admin tool to seed real courses into the database
class CourseImportService {
  final DatabaseHelper _databaseHelper;

  CourseImportService(this._databaseHelper);

  /// Import a single course to database
  Future<int> importCourse(CourseModel course) async {
    try {
      final db = await _databaseHelper.database;
      
      // Check if course already exists
      final existing = await db.query(
        'courses',
        where: 'title = ?',
        whereArgs: [course.title],
      );

      if (existing.isNotEmpty) {
        print('Course "${course.title}" already exists, skipping...');
        return 0;
      }

      final id = await db.insert('courses', {
        'title': course.title,
        'description': course.description,
        'level': course.level,
        'category': course.category,
        'imageUrl': course.imageUrl,
        'duration': course.duration,
        'lessonsCount': course.lessonsCount,
        'isFeatured': course.isFeatured ? 1 : 0,
        'rating': course.rating,
        'enrolledCount': course.enrolledCount,
        'createdAt': course.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      print('Imported course: ${course.title} (ID: $id)');
      return id;
    } catch (e) {
      print('Error importing course ${course.title}: $e');
      return -1;
    }
  }

  /// Import multiple courses at once
  Future<List<int>> importCourses(List<CourseModel> courses) async {
    final ids = <int>[];
    for (final course in courses) {
      final id = await importCourse(course);
      if (id > 0) ids.add(id);
    }
    return ids;
  }

  /// Seed the database with 10 real English learning courses
  Future<void> seedRealCourses() async {
    print('📚 Starting to seed real courses...');
    
    final courses = [
      // Beginner Level Courses
      CourseModel(
        id: 1,
        title: 'English Basics for Beginners',
        description: 'Start your English learning journey with fundamental grammar, vocabulary, and everyday conversations. Perfect for absolute beginners.',
        level: 'Beginner',
        category: 'General English',
        imageUrl: 'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=400',
        duration: '4 weeks',
        lessonsCount: 30,
        isFeatured: true,
        rating: 4.8,
        enrolledCount: 12450,
        createdAt: DateTime.now().subtract(const Duration(days: 90)),
      ),
      
      CourseModel(
        id: 2,
        title: 'Everyday English Conversations',
        description: 'Learn practical English for daily situations like shopping, ordering food, asking directions, and making small talk.',
        level: 'Beginner',
        category: 'Conversation',
        imageUrl: 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=400',
        duration: '3 weeks',
        lessonsCount: 25,
        isFeatured: true,
        rating: 4.7,
        enrolledCount: 9820,
        createdAt: DateTime.now().subtract(const Duration(days: 75)),
      ),
      
      CourseModel(
        id: 3,
        title: 'English Pronunciation Essentials',
        description: 'Master English sounds, stress patterns, and intonation. Improve your accent and speaking confidence with guided practice.',
        level: 'Beginner',
        category: 'Pronunciation',
        imageUrl: 'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=400',
        duration: '2 weeks',
        lessonsCount: 20,
        isFeatured: false,
        rating: 4.6,
        enrolledCount: 7350,
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
      ),
      
      // Intermediate Level Courses
      CourseModel(
        id: 4,
        title: 'Business English Essentials',
        description: 'Professional English for workplace communication, emails, presentations, meetings, and negotiations.',
        level: 'Intermediate',
        category: 'Business English',
        imageUrl: 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?w=400',
        duration: '6 weeks',
        lessonsCount: 40,
        isFeatured: true,
        rating: 4.9,
        enrolledCount: 15620,
        createdAt: DateTime.now().subtract(const Duration(days: 50)),
      ),
      
      CourseModel(
        id: 5,
        title: 'IELTS Preparation Course',
        description: 'Comprehensive preparation for all four IELTS sections: Listening, Reading, Writing, and Speaking. Achieve your target band score.',
        level: 'Intermediate',
        category: 'Test Preparation',
        imageUrl: 'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=400',
        duration: '8 weeks',
        lessonsCount: 50,
        isFeatured: true,
        rating: 4.9,
        enrolledCount: 18900,
        createdAt: DateTime.now().subtract(const Duration(days: 40)),
      ),
      
      CourseModel(
        id: 6,
        title: 'English Grammar Mastery',
        description: 'Deep dive into English grammar rules, tenses, conditionals, and complex sentence structures. Build a solid foundation.',
        level: 'Intermediate',
        category: 'Grammar',
        imageUrl: 'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=400',
        duration: '5 weeks',
        lessonsCount: 35,
        isFeatured: false,
        rating: 4.7,
        enrolledCount: 11200,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      
      // Advanced Level Courses
      CourseModel(
        id: 7,
        title: 'Advanced English for Tech Professionals',
        description: 'Technical English vocabulary, IT communication, coding discussions, and tech industry jargon for software engineers and tech workers.',
        level: 'Advanced',
        category: 'Industry-Specific',
        imageUrl: 'https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=400',
        duration: '6 weeks',
        lessonsCount: 42,
        isFeatured: true,
        rating: 4.8,
        enrolledCount: 8900,
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
      
      CourseModel(
        id: 8,
        title: 'Academic English for University',
        description: 'Essay writing, research papers, academic presentations, and critical thinking skills for university students and researchers.',
        level: 'Advanced',
        category: 'Academic English',
        imageUrl: 'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?w=400',
        duration: '7 weeks',
        lessonsCount: 45,
        isFeatured: false,
        rating: 4.7,
        enrolledCount: 6450,
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
      
      // Specialized Courses
      CourseModel(
        id: 9,
        title: 'Travel English for Explorers',
        description: 'Essential English phrases for traveling abroad: booking hotels, airport conversations, asking for help, and cultural communication.',
        level: 'Intermediate',
        category: 'Travel & Tourism',
        imageUrl: 'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400',
        duration: '3 weeks',
        lessonsCount: 24,
        isFeatured: false,
        rating: 4.6,
        enrolledCount: 5320,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
      
      CourseModel(
        id: 10,
        title: 'English Idioms & Phrasal Verbs',
        description: 'Master common English idioms, phrasal verbs, and expressions to sound more natural and fluent like a native speaker.',
        level: 'Intermediate',
        category: 'Vocabulary',
        imageUrl: 'https://images.unsplash.com/photo-1513542789411-b6a5d4f31634?w=400',
        duration: '4 weeks',
        lessonsCount: 32,
        isFeatured: false,
        rating: 4.8,
        enrolledCount: 9870,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];

    await importCourses(courses);
    
    final stats = await getCourseStats();
    print('Seeding complete! Database now has:');
    print('   • Total courses: ${stats['total']}');
    print('   • Featured courses: ${stats['featured']}');
    print('   • Beginner: ${stats['beginner']}, Intermediate: ${stats['intermediate']}, Advanced: ${stats['advanced']}');
  }

  /// Get course statistics from database
  Future<Map<String, int>> getCourseStats() async {
    final db = await _databaseHelper.database;
    
    final total = await db.rawQuery('SELECT COUNT(*) as count FROM courses');
    final featured = await db.rawQuery('SELECT COUNT(*) as count FROM courses WHERE isFeatured = 1');
    final beginner = await db.rawQuery('SELECT COUNT(*) as count FROM courses WHERE level = ?', ['Beginner']);
    final intermediate = await db.rawQuery('SELECT COUNT(*) as count FROM courses WHERE level = ?', ['Intermediate']);
    final advanced = await db.rawQuery('SELECT COUNT(*) as count FROM courses WHERE level = ?', ['Advanced']);

    return {
      'total': total.first['count'] as int,
      'featured': featured.first['count'] as int,
      'beginner': beginner.first['count'] as int,
      'intermediate': intermediate.first['count'] as int,
      'advanced': advanced.first['count'] as int,
    };
  }

  /// Clear all courses from database (use with caution!)
  Future<void> clearAllCourses() async {
    final db = await _databaseHelper.database;
    await db.delete('courses');
    print('🗑️ All courses cleared from database');
  }
}
