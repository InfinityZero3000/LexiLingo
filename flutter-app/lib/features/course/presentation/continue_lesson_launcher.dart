import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:provider/provider.dart';

/// Opens the learner's next open lesson in a course, or the course page when
/// there is none (finished, or the detail could not be loaded).
abstract final class ContinueLessonLauncher {
  static Future<void> open(BuildContext context, String courseId) async {
    final provider = context.read<CourseProvider>();
    await provider.loadCourseDetail(courseId);
    if (!context.mounted) return;
    final detail = provider.courseDetail;
    final next = detail?.id == courseId ? detail?.nextOpenLesson : null;
    await LearnerRoute.push<void>(
      context,
      (_) => next == null
          ? CourseDetailScreen(courseId: courseId)
          : LearningSessionScreen(lessonId: next.id, courseId: courseId),
    );
  }
}
