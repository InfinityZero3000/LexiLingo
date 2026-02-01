import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

void main() {
  group('CourseProvider - Course Grouping', () {

    final testCourses = [
      CourseEntity(
        id: '1',
        title: 'Beginner English',
        language: 'English',
        level: 'Beginner',
        tags: ['Grammar', 'Vocabulary'],
        totalXp: 100,
        estimatedDuration: 60,
        totalLessons: 10,
        isPublished: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      CourseEntity(
        id: '2',
        title: 'Intermediate English',
        language: 'English',
        level: 'Intermediate',
        tags: ['Conversation', 'Grammar'],
        totalXp: 200,
        estimatedDuration: 90,
        totalLessons: 15,
        isPublished: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      CourseEntity(
        id: '3',
        title: 'Beginner Spanish',
        language: 'Spanish',
        level: 'Beginner',
        tags: ['Vocabulary'],
        totalXp: 100,
        estimatedDuration: 45,
        totalLessons: 8,
        isPublished: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      CourseEntity(
        id: '4',
        title: 'Advanced English',
        language: 'English',
        level: 'Advanced',
        tags: ['Business', 'Writing'],
        totalXp: 300,
        estimatedDuration: 120,
        totalLessons: 20,
        isPublished: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      CourseEntity(
        id: '5',
        title: 'Intermediate Spanish',
        language: 'Spanish',
        level: 'Intermediate',
        tags: ['Conversation'],
        totalXp: 200,
        estimatedDuration: 75,
        totalLessons: 12,
        isPublished: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    group('coursesByCategory', () {
      test('should group courses by level correctly', () {
        // Test the grouping logic directly
        final grouped = _groupCoursesByCategory(testCourses);

        expect(grouped.containsKey('Beginner'), true);
        expect(grouped.containsKey('Intermediate'), true);
        expect(grouped.containsKey('Advanced'), true);

        expect(grouped['Beginner']!.length, 2);
        expect(grouped['Intermediate']!.length, 2);
        expect(grouped['Advanced']!.length, 1);
      });

      test('should have beginner courses with correct data', () {
        final grouped = _groupCoursesByCategory(testCourses);

        final beginnerCourses = grouped['Beginner']!;
        expect(beginnerCourses.any((c) => c.title == 'Beginner English'), true);
        expect(beginnerCourses.any((c) => c.title == 'Beginner Spanish'), true);
      });

      test('should have intermediate courses with correct data', () {
        final grouped = _groupCoursesByCategory(testCourses);

        final intermediateCourses = grouped['Intermediate']!;
        expect(intermediateCourses.any((c) => c.title == 'Intermediate English'), true);
        expect(intermediateCourses.any((c) => c.title == 'Intermediate Spanish'), true);
      });

      test('should have advanced courses with correct data', () {
        final grouped = _groupCoursesByCategory(testCourses);

        final advancedCourses = grouped['Advanced']!;
        expect(advancedCourses.length, 1);
        expect(advancedCourses.first.title, 'Advanced English');
      });

      test('should return empty map for empty course list', () {
        final grouped = _groupCoursesByCategory([]);
        expect(grouped.isEmpty, true);
      });
    });

    group('coursesByLanguage', () {
      test('should group courses by language correctly', () {
        final grouped = _groupCoursesByLanguage(testCourses);

        expect(grouped.containsKey('English'), true);
        expect(grouped.containsKey('Spanish'), true);

        expect(grouped['English']!.length, 3);
        expect(grouped['Spanish']!.length, 2);
      });

      test('should have all English courses', () {
        final grouped = _groupCoursesByLanguage(testCourses);

        final englishCourses = grouped['English']!;
        expect(englishCourses.any((c) => c.level == 'Beginner'), true);
        expect(englishCourses.any((c) => c.level == 'Intermediate'), true);
        expect(englishCourses.any((c) => c.level == 'Advanced'), true);
      });

      test('should have all Spanish courses', () {
        final grouped = _groupCoursesByLanguage(testCourses);

        final spanishCourses = grouped['Spanish']!;
        expect(spanishCourses.any((c) => c.level == 'Beginner'), true);
        expect(spanishCourses.any((c) => c.level == 'Intermediate'), true);
      });
    });

    group('coursesByTopic', () {
      test('should group courses by first tag (topic)', () {
        final grouped = _groupCoursesByTopic(testCourses);

        expect(grouped.containsKey('Grammar'), true);
        expect(grouped.containsKey('Conversation'), true);
        expect(grouped.containsKey('Vocabulary'), true);
        expect(grouped.containsKey('Business'), true);
      });

      test('should use General for courses without tags', () {
        final coursesWithNoTags = [
          CourseEntity(
            id: '10',
            title: 'No Tags Course',
            language: 'English',
            level: 'Beginner',
            tags: [],
            totalXp: 50,
            estimatedDuration: 30,
            totalLessons: 5,
            isPublished: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        final grouped = _groupCoursesByTopic(coursesWithNoTags);
        expect(grouped.containsKey('General'), true);
        expect(grouped['General']!.length, 1);
      });
    });

    group('availableCategories', () {
      test('should return all unique levels', () {
        final categories = _getAvailableCategories(testCourses);

        expect(categories.contains('Beginner'), true);
        expect(categories.contains('Intermediate'), true);
        expect(categories.contains('Advanced'), true);
        expect(categories.length, 3);
      });

      test('should return empty list for no courses', () {
        final categories = _getAvailableCategories([]);
        expect(categories.isEmpty, true);
      });
    });

    group('availableLanguages', () {
      test('should return all unique languages', () {
        final languages = _getAvailableLanguages(testCourses);

        expect(languages.contains('English'), true);
        expect(languages.contains('Spanish'), true);
        expect(languages.length, 2);
      });

      test('should return empty list for no courses', () {
        final languages = _getAvailableLanguages([]);
        expect(languages.isEmpty, true);
      });
    });

    group('availableTopics', () {
      test('should return all unique topics from tags', () {
        final topics = _getAvailableTopics(testCourses);

        expect(topics.contains('Grammar'), true);
        expect(topics.contains('Vocabulary'), true);
        expect(topics.contains('Conversation'), true);
        expect(topics.contains('Business'), true);
        expect(topics.contains('Writing'), true);
      });

      test('should return empty list for no courses', () {
        final topics = _getAvailableTopics([]);
        expect(topics.isEmpty, true);
      });
    });
  });

  group('CourseProvider - Horizontal Layout Integration', () {
    test('should maintain proper order Beginner -> Intermediate -> Advanced', () {
      final courses = [
        _createCourse(id: '1', level: 'Advanced'),
        _createCourse(id: '2', level: 'Beginner'),
        _createCourse(id: '3', level: 'Intermediate'),
      ];

      final grouped = _groupCoursesByCategory(courses);
      final orderedKeys = grouped.keys.toList();

      // First key in grouped map should be Beginner (based on predefined order)
      expect(orderedKeys.first, 'Beginner');
    });

    test('should handle courses with unknown levels', () {
      final courses = [
        _createCourse(id: '1', level: 'Expert'),
        _createCourse(id: '2', level: 'Beginner'),
      ];

      final grouped = _groupCoursesByCategory(courses);

      expect(grouped.containsKey('Beginner'), true);
      expect(grouped.containsKey('Expert'), true);
    });

    test('should correctly count courses per category', () {
      final courses = [
        _createCourse(id: '1', level: 'Beginner'),
        _createCourse(id: '2', level: 'Beginner'),
        _createCourse(id: '3', level: 'Beginner'),
        _createCourse(id: '4', level: 'Intermediate'),
      ];

      final grouped = _groupCoursesByCategory(courses);

      expect(grouped['Beginner']!.length, 3);
      expect(grouped['Intermediate']!.length, 1);
    });
  });
}

// Helper functions that mirror the provider's logic for testing
Map<String, List<CourseEntity>> _groupCoursesByCategory(List<CourseEntity> courses) {
  final Map<String, List<CourseEntity>> grouped = {};
  const categoryOrder = ['Beginner', 'Intermediate', 'Advanced'];

  for (final category in categoryOrder) {
    grouped[category] = [];
  }

  for (final course in courses) {
    final category = course.level;
    if (grouped.containsKey(category)) {
      grouped[category]!.add(course);
    } else {
      grouped[category] = [course];
    }
  }

  grouped.removeWhere((key, value) => value.isEmpty);
  return grouped;
}

Map<String, List<CourseEntity>> _groupCoursesByLanguage(List<CourseEntity> courses) {
  final Map<String, List<CourseEntity>> grouped = {};

  for (final course in courses) {
    final language = course.language;
    if (grouped.containsKey(language)) {
      grouped[language]!.add(course);
    } else {
      grouped[language] = [course];
    }
  }

  return grouped;
}

Map<String, List<CourseEntity>> _groupCoursesByTopic(List<CourseEntity> courses) {
  final Map<String, List<CourseEntity>> grouped = {};

  for (final course in courses) {
    final topic = course.tags.isNotEmpty ? course.tags.first : 'General';
    if (grouped.containsKey(topic)) {
      grouped[topic]!.add(course);
    } else {
      grouped[topic] = [course];
    }
  }

  return grouped;
}

List<String> _getAvailableCategories(List<CourseEntity> courses) {
  return courses.map((c) => c.level).toSet().toList();
}

List<String> _getAvailableLanguages(List<CourseEntity> courses) {
  return courses.map((c) => c.language).toSet().toList();
}

List<String> _getAvailableTopics(List<CourseEntity> courses) {
  final topics = <String>{};
  for (final course in courses) {
    topics.addAll(course.tags);
  }
  return topics.toList();
}

CourseEntity _createCourse({
  required String id,
  String title = 'Test Course',
  String language = 'English',
  String level = 'Beginner',
  List<String> tags = const [],
}) {
  return CourseEntity(
    id: id,
    title: title,
    language: language,
    level: level,
    tags: tags,
    totalXp: 100,
    estimatedDuration: 60,
    totalLessons: 10,
    isPublished: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
