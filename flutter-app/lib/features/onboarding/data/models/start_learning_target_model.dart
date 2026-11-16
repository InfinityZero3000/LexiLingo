import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';

class StartLearningTargetModel extends StartLearningTarget {
  const StartLearningTargetModel({
    required super.courseId,
    required super.courseTitle,
    required super.firstLessonId,
    required super.alreadyEnrolled,
  });

  factory StartLearningTargetModel.fromJson(Map<String, dynamic> json) {
    final courseId = json['course_id'] as String?;
    final lessonId = json['first_lesson_id'] as String?;
    if (courseId == null || lessonId == null) {
      throw const FormatException('start-learning response lacks a lesson');
    }
    return StartLearningTargetModel(
      courseId: courseId,
      courseTitle: json['course_title'] as String? ?? '',
      firstLessonId: lessonId,
      alreadyEnrolled: json['already_enrolled'] as bool? ?? false,
    );
  }
}
