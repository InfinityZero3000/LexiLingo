class CourseEnrollment {
  final int id;
  final String userId;
  final int courseId;
  final DateTime enrolledAt;
  final DateTime? lastAccessedAt;
  final DateTime? completedAt;
  final double currentProgress; // 0.0 - 1.0

  const CourseEnrollment({
    required this.id,
    required this.userId,
    required this.courseId,
    required this.enrolledAt,
    this.lastAccessedAt,
    this.completedAt,
    this.currentProgress = 0.0,
  });

  bool get isCompleted => completedAt != null;
  
  int get progressPercentage => (currentProgress * 100).round();

  CourseEnrollment copyWith({
    int? id,
    String? userId,
    int? courseId,
    DateTime? enrolledAt,
    DateTime? lastAccessedAt,
    DateTime? completedAt,
    double? currentProgress,
  }) {
    return CourseEnrollment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      courseId: courseId ?? this.courseId,
      enrolledAt: enrolledAt ?? this.enrolledAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      completedAt: completedAt ?? this.completedAt,
      currentProgress: currentProgress ?? this.currentProgress,
    );
  }
}
