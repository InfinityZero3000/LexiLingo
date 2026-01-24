import '../../domain/entities/course_enrollment.dart';

class CourseEnrollmentModel extends CourseEnrollment {
  const CourseEnrollmentModel({
    required super.id,
    required super.userId,
    required super.courseId,
    required super.enrolledAt,
    super.lastAccessedAt,
    super.completedAt,
    super.currentProgress,
  });

  factory CourseEnrollmentModel.fromJson(Map<String, dynamic> json) {
    return CourseEnrollmentModel(
      id: json['id'] as int,
      userId: json['userId'] as String,
      courseId: json['courseId'] as int,
      enrolledAt: DateTime.parse(json['enrolledAt'] as String),
      lastAccessedAt: json['lastAccessedAt'] != null
          ? DateTime.parse(json['lastAccessedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      currentProgress: (json['currentProgress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'courseId': courseId,
      'enrolledAt': enrolledAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'currentProgress': currentProgress,
    };
  }

  factory CourseEnrollmentModel.fromEntity(CourseEnrollment enrollment) {
    return CourseEnrollmentModel(
      id: enrollment.id,
      userId: enrollment.userId,
      courseId: enrollment.courseId,
      enrolledAt: enrollment.enrolledAt,
      lastAccessedAt: enrollment.lastAccessedAt,
      completedAt: enrollment.completedAt,
      currentProgress: enrollment.currentProgress,
    );
  }
}
