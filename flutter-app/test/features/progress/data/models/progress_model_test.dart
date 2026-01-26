import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/progress/data/models/progress_model.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';

void main() {
  group('UserProgressSummaryModel', () {
    final tJson = {
      'total_xp': 150,
      'courses_enrolled': 3,
      'courses_completed': 1,
      'lessons_completed': 15,
      'current_streak': 5,
      'longest_streak': 10,
      'achievements_unlocked': 3,
    };

    final tModel = UserProgressSummaryModel(
      totalXp: 150,
      coursesEnrolled: 3,
      coursesCompleted: 1,
      lessonsCompleted: 15,
      currentStreak: 5,
      longestStreak: 10,
      achievementsUnlocked: 3,
    );

    test('should be a subclass of UserProgressSummary entity', () {
      expect(tModel, isA<UserProgressSummary>());
    });

    test('should return a valid model from JSON', () {
      final result = UserProgressSummaryModel.fromJson(tJson);

      expect(result, equals(tModel));
    });

    test('should return a JSON map containing proper data', () {
      final result = tModel.toJson();

      expect(result, equals(tJson));
    });

    test('should handle null/missing values with defaults', () {
      final jsonWithMissing = <String, dynamic>{};
      
      final result = UserProgressSummaryModel.fromJson(jsonWithMissing);

      expect(result.totalXp, 0);
      expect(result.coursesEnrolled, 0);
      expect(result.lessonsCompleted, 0);
    });
  });

  group('CourseProgressDetailModel', () {
    final tJson = {
      'course_id': 'course-123',
      'course_title': 'English for Beginners',
      'progress_percentage': 65.5,
      'lessons_completed': 13,
      'total_lessons': 20,
      'total_xp_earned': 260,
      'started_at': '2024-01-15T10:00:00Z',
      'last_activity_at': '2024-01-20T15:30:00Z',
      'estimated_completion_days': 7,
    };

    final tModel = CourseProgressDetailModel(
      courseId: 'course-123',
      courseTitle: 'English for Beginners',
      progressPercentage: 65.5,
      lessonsCompleted: 13,
      totalLessons: 20,
      totalXpEarned: 260,
      startedAt: DateTime.parse('2024-01-15T10:00:00Z'),
      lastActivityAt: DateTime.parse('2024-01-20T15:30:00Z'),
      estimatedCompletionDays: 7,
    );

    test('should be a subclass of CourseProgressDetail entity', () {
      expect(tModel, isA<CourseProgressDetail>());
    });

    test('should return a valid model from JSON', () {
      final result = CourseProgressDetailModel.fromJson(tJson);

      expect(result.courseId, tModel.courseId);
      expect(result.courseTitle, tModel.courseTitle);
      expect(result.progressPercentage, tModel.progressPercentage);
      expect(result.lessonsCompleted, tModel.lessonsCompleted);
      expect(result.totalLessons, tModel.totalLessons);
      expect(result.totalXpEarned, tModel.totalXpEarned);
      expect(result.estimatedCompletionDays, tModel.estimatedCompletionDays);
    });

    test('should return a JSON map containing proper data', () {
      final result = tModel.toJson();

      expect(result['course_id'], 'course-123');
      expect(result['progress_percentage'], 65.5);
      expect(result['total_xp_earned'], 260);
    });
  });

  group('LessonCompletionResultModel', () {
    final tJson = {
      'lesson_id': 'lesson-456',
      'is_passed': true,
      'score': 85.0,
      'best_score': 90.0,
      'xp_earned': 20,
      'total_xp': 120,
      'course_progress': 45.0,
      'message': 'Great job!',
    };

    final tModel = LessonCompletionResultModel(
      lessonId: 'lesson-456',
      isPassed: true,
      score: 85.0,
      bestScore: 90.0,
      xpEarned: 20,
      totalXp: 120,
      courseProgress: 45.0,
      message: 'Great job!',
    );

    test('should be a subclass of LessonCompletionResult entity', () {
      expect(tModel, isA<LessonCompletionResult>());
    });

    test('should return a valid model from JSON', () {
      final result = LessonCompletionResultModel.fromJson(tJson);

      expect(result, equals(tModel));
    });

    test('should return a JSON map containing proper data', () {
      final result = tModel.toJson();

      expect(result, equals(tJson));
    });

    test('should handle failed completion', () {
      final failedJson = {
        'lesson_id': 'lesson-789',
        'is_passed': false,
        'score': 65.0,
        'best_score': 65.0,
        'xp_earned': 0,
        'total_xp': 100,
        'course_progress': 40.0,
        'message': 'Try again',
      };

      final result = LessonCompletionResultModel.fromJson(failedJson);

      expect(result.isPassed, false);
      expect(result.xpEarned, 0);
      expect(result.message, 'Try again');
    });
  });

  group('UnitProgressModel', () {
    final tJson = {
      'unit_id': 'unit-001',
      'unit_title': 'Greetings',
      'total_lessons': 10,
      'completed_lessons': 7,
      'progress_percentage': 70.0,
    };

    final tModel = UnitProgressModel(
      unitId: 'unit-001',
      unitTitle: 'Greetings',
      totalLessons: 10,
      completedLessons: 7,
      progressPercentage: 70.0,
    );

    test('should be a subclass of UnitProgressEntity', () {
      expect(tModel, isA<UnitProgressEntity>());
    });

    test('should return a valid model from JSON', () {
      final result = UnitProgressModel.fromJson(tJson);

      expect(result, equals(tModel));
    });

    test('should return a JSON map containing proper data', () {
      final result = tModel.toJson();

      expect(result, equals(tJson));
    });
  });

  group('ProgressStatsModel', () {
    final tSummary = UserProgressSummaryModel(
      totalXp: 200,
      coursesEnrolled: 2,
      coursesCompleted: 0,
      lessonsCompleted: 10,
      currentStreak: 3,
      longestStreak: 5,
      achievementsUnlocked: 2,
    );

    final tCourseProgress = CourseProgressDetailModel(
      courseId: 'course-1',
      courseTitle: 'English A1',
      progressPercentage: 50.0,
      lessonsCompleted: 10,
      totalLessons: 20,
      totalXpEarned: 200,
      startedAt: DateTime.parse('2024-01-10T00:00:00Z'),
      lastActivityAt: DateTime.parse('2024-01-20T00:00:00Z'),
    );

    final tJson = {
      'summary': {
        'total_xp': 200,
        'courses_enrolled': 2,
        'courses_completed': 0,
        'lessons_completed': 10,
        'current_streak': 3,
        'longest_streak': 5,
        'achievements_unlocked': 2,
      },
      'course_progress': [
        {
          'course_id': 'course-1',
          'course_title': 'English A1',
          'progress_percentage': 50.0,
          'lessons_completed': 10,
          'total_lessons': 20,
          'total_xp_earned': 200,
          'started_at': '2024-01-10T00:00:00Z',
          'last_activity_at': '2024-01-20T00:00:00Z',
        },
      ],
    };

    final tModel = ProgressStatsModel(
      summary: tSummary,
      courseProgress: [tCourseProgress],
    );

    test('should be a subclass of ProgressStatsEntity', () {
      expect(tModel, isA<ProgressStatsEntity>());
    });

    test('should return a valid model from JSON', () {
      final result = ProgressStatsModel.fromJson(tJson);

      expect(result.summary.totalXp, 200);
      expect(result.courseProgress.length, 1);
      expect(result.courseProgress[0].courseId, 'course-1');
    });

    test('should return a JSON map containing proper data', () {
      final result = tModel.toJson();

      expect(result['summary']['total_xp'], 200);
      expect(result['course_progress'].length, 1);
    });

    test('should handle empty course progress list', () {
      final emptyJson = {
        'summary': {
          'total_xp': 0,
          'courses_enrolled': 0,
          'courses_completed': 0,
          'lessons_completed': 0,
          'current_streak': 0,
          'longest_streak': 0,
          'achievements_unlocked': 0,
        },
        'course_progress': [],
      };

      final result = ProgressStatsModel.fromJson(emptyJson);

      expect(result.courseProgress, isEmpty);
    });
  });

  group('CourseProgressWithUnitsModel', () {
    final tCourse = CourseProgressDetailModel(
      courseId: 'course-1',
      courseTitle: 'English A1',
      progressPercentage: 60.0,
      lessonsCompleted: 12,
      totalLessons: 20,
      totalXpEarned: 240,
      startedAt: DateTime.parse('2024-01-10T00:00:00Z'),
      lastActivityAt: DateTime.parse('2024-01-20T00:00:00Z'),
    );

    final tUnit = UnitProgressModel(
      unitId: 'unit-1',
      unitTitle: 'Unit 1',
      totalLessons: 10,
      completedLessons: 6,
      progressPercentage: 60.0,
    );

    final tJson = {
      'course': {
        'course_id': 'course-1',
        'course_title': 'English A1',
        'progress_percentage': 60.0,
        'lessons_completed': 12,
        'total_lessons': 20,
        'total_xp_earned': 240,
        'started_at': '2024-01-10T00:00:00Z',
        'last_activity_at': '2024-01-20T00:00:00Z',
      },
      'units_progress': [
        {
          'unit_id': 'unit-1',
          'unit_title': 'Unit 1',
          'total_lessons': 10,
          'completed_lessons': 6,
          'progress_percentage': 60.0,
        },
      ],
    };

    final tModel = CourseProgressWithUnitsModel(
      course: tCourse,
      unitsProgress: [tUnit],
    );

    test('should be a subclass of CourseProgressWithUnits entity', () {
      expect(tModel, isA<CourseProgressWithUnits>());
    });

    test('should return a valid model from JSON', () {
      final result = CourseProgressWithUnitsModel.fromJson(tJson);

      expect(result.course.courseId, 'course-1');
      expect(result.unitsProgress.length, 1);
      expect(result.unitsProgress[0].unitId, 'unit-1');
    });

    test('should return a JSON map containing proper data', () {
      final result = tModel.toJson();

      expect(result['course']['course_id'], 'course-1');
      expect(result['units_progress'].length, 1);
    });
  });
}
