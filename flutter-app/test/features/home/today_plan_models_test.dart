import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_models.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  group('buildTodayPlanSnapshot', () {
    test('builds the default daily learning sequence from available data', () {
      final snapshot = buildTodayPlanSnapshot(
        dueVocabularyCount: 4,
        enrolledCourses: [_course(progress: 0.35)],
        weakestSkills: [_skill(SkillType.listening, score: 42)],
        challenges: [_challenge(category: 'vocabulary', current: 1, target: 3)],
      );

      expect(snapshot.totalCount, 5);
      expect(snapshot.tasks.map((task) => task.type), [
        TodayPlanTaskType.vocabulary,
        TodayPlanTaskType.course,
        TodayPlanTaskType.skill,
        TodayPlanTaskType.challenge,
        TodayPlanTaskType.conversation,
      ]);
      expect(
        snapshot.tasks[0].destination,
        TodayPlanDestination.vocabularyReview,
      );
      expect(snapshot.tasks[2].destination, TodayPlanDestination.podcast);
      expect(
        snapshot.tasks[3].destination,
        TodayPlanDestination.vocabularyReview,
      );
      expect(snapshot.completedCount, 0);
    });

    test('falls back to starter tasks when learner data is empty', () {
      final snapshot = buildTodayPlanSnapshot(
        dueVocabularyCount: 0,
        enrolledCourses: const [],
        weakestSkills: const [],
        challenges: const [],
      );

      expect(snapshot.totalCount, 5);
      expect(snapshot.tasks[0].isCompleted, isTrue);
      expect(snapshot.tasks[1].destination, TodayPlanDestination.courseList);
      expect(snapshot.tasks[2].destination, TodayPlanDestination.voice);
      expect(snapshot.tasks[3].destination, TodayPlanDestination.games);
      expect(snapshot.tasks[4].destination, TodayPlanDestination.lexi);
      expect(snapshot.nextTask, snapshot.tasks[1]);
    });

    test(
      'shows a completed course as done instead of the "choose a course" '
      'fallback when every enrolled course is already finished',
      () {
        final snapshot = buildTodayPlanSnapshot(
          dueVocabularyCount: 0,
          enrolledCourses: [_course(progress: 1.0)],
          weakestSkills: const [],
          challenges: const [],
        );

        final courseTask = snapshot.tasks[1];
        expect(courseTask.title, 'A2 Daily English'); // not the fallback copy
        expect(courseTask.isCompleted, isTrue);
        expect(courseTask.progress, 1.0);
      },
    );

    test(
      'still falls back to "choose a course" when nothing is enrolled at all',
      () {
        final snapshot = buildTodayPlanSnapshot(
          dueVocabularyCount: 0,
          enrolledCourses: const [],
          weakestSkills: const [],
          challenges: const [],
        );

        final courseTask = snapshot.tasks[1];
        expect(courseTask.destination, TodayPlanDestination.courseList);
        expect(courseTask.isCompleted, isFalse);
      },
    );
  });

  group('TodayPlanSnapshot.visibleTasks', () {
    test('shows pending tasks first so a finished task never bumps a '
        'pending one out of the space-constrained home card', () {
      // Vocabulary (0), skill (2) and challenge (3) are already done; course
      // (1, no enrolled course -> "pick a course" fallback) and conversation
      // (4, never completes) are still pending. A fixed take(3) would show
      // vocab/course/skill and hide challenge/conversation even though two
      // of those three are already done and course/conversation are not.
      final snapshot = buildTodayPlanSnapshot(
        dueVocabularyCount: 0,
        enrolledCourses: const [],
        weakestSkills: [_skill(SkillType.listening, score: 95)],
        challenges: [_challenge(category: 'vocabulary', current: 3, target: 3)],
      );

      expect(snapshot.tasks[0].isCompleted, isTrue); // vocabulary
      expect(snapshot.tasks[1].isCompleted, isFalse); // course
      expect(snapshot.tasks[2].isCompleted, isTrue); // skill
      expect(snapshot.tasks[3].isCompleted, isTrue); // challenge
      expect(snapshot.tasks[4].isCompleted, isFalse); // conversation

      final visible = snapshot.visibleTasks();

      expect(visible.map((t) => t.type), [
        TodayPlanTaskType.course,
        TodayPlanTaskType.conversation,
        TodayPlanTaskType.vocabulary,
      ]);
    });

    test('keeps original order when nothing is completed yet', () {
      final snapshot = buildTodayPlanSnapshot(
        dueVocabularyCount: 4,
        enrolledCourses: const [],
        weakestSkills: const [],
        challenges: const [],
      );

      expect(snapshot.visibleTasks().map((t) => t.type), [
        TodayPlanTaskType.vocabulary,
        TodayPlanTaskType.course,
        TodayPlanTaskType.skill,
      ]);
    });
  });
}

CourseEntity _course({required double progress}) {
  final now = DateTime(2026, 6, 30);
  return CourseEntity(
    id: 'course-1',
    title: 'A2 Daily English',
    description: 'Everyday English practice',
    language: 'en',
    level: 'A2',
    tags: const ['daily'],
    totalXp: 120,
    estimatedDuration: 30,
    totalLessons: 8,
    isPublished: true,
    createdAt: now,
    updatedAt: now,
    isEnrolled: true,
    userProgress: progress,
  );
}

SkillScore _skill(SkillType skill, {required double score}) {
  return SkillScore(
    skill: skill,
    score: score,
    confidence: 0.8,
    estimatedLevel: 'A2',
    accuracy: 0.7,
    trend: 'stable',
    exercisesCompleted: 12,
  );
}

DailyChallengeEntity _challenge({
  required String category,
  required int current,
  required int target,
}) {
  return DailyChallengeEntity(
    id: 'challenge-1',
    title: 'Review words',
    description: 'Review 3 due words',
    icon: 'style',
    category: category,
    target: target,
    current: current,
    xpReward: 20,
    isCompleted: current >= target,
    expiresAt: DateTime(2026, 7, 1),
  );
}
