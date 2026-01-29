/// Course Roadmap Model
/// Represents response from GET /learning/courses/{id}/roadmap
class CourseRoadmapModel {
  final String courseId;
  final String courseTitle;
  final String level;
  final int totalUnits;
  final int completedUnits;
  final int totalLessons;
  final int completedLessons;
  final double completionPercentage;
  final int totalXpEarned;
  final int currentStreak;
  final List<UnitRoadmapModel> units;

  CourseRoadmapModel({
    required this.courseId,
    required this.courseTitle,
    required this.level,
    required this.totalUnits,
    required this.completedUnits,
    required this.totalLessons,
    required this.completedLessons,
    required this.completionPercentage,
    required this.totalXpEarned,
    required this.currentStreak,
    required this.units,
  });

  factory CourseRoadmapModel.fromJson(Map<String, dynamic> json) {
    return CourseRoadmapModel(
      courseId: json['course_id'] as String,
      courseTitle: json['course_title'] as String,
      level: json['level'] as String? ?? 'beginner',
      totalUnits: json['total_units'] as int? ?? 0,
      completedUnits: json['completed_units'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      completedLessons: json['completed_lessons'] as int? ?? 0,
      completionPercentage: (json['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      totalXpEarned: json['total_xp_earned'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      units: (json['units'] as List<dynamic>?)
              ?.map((e) => UnitRoadmapModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_id': courseId,
      'course_title': courseTitle,
      'level': level,
      'total_units': totalUnits,
      'completed_units': completedUnits,
      'total_lessons': totalLessons,
      'completed_lessons': completedLessons,
      'completion_percentage': completionPercentage,
      'total_xp_earned': totalXpEarned,
      'current_streak': currentStreak,
      'units': units.map((e) => e.toJson()).toList(),
    };
  }
}

/// Unit Roadmap Model
class UnitRoadmapModel {
  final String unitId;
  final int unitNumber;
  final String title;
  final String? description;
  final int totalLessons;
  final int completedLessons;
  final double completionPercentage;
  final bool isCurrent;
  final List<LessonProgressModel> lessons;
  final String? iconUrl;
  final String backgroundColor;

  UnitRoadmapModel({
    required this.unitId,
    required this.unitNumber,
    required this.title,
    this.description,
    required this.totalLessons,
    required this.completedLessons,
    required this.completionPercentage,
    required this.isCurrent,
    required this.lessons,
    this.iconUrl,
    required this.backgroundColor,
  });

  factory UnitRoadmapModel.fromJson(Map<String, dynamic> json) {
    return UnitRoadmapModel(
      unitId: json['unit_id'] as String,
      unitNumber: json['unit_number'] as int? ?? 1,
      title: json['title'] as String,
      description: json['description'] as String?,
      totalLessons: json['total_lessons'] as int? ?? 0,
      completedLessons: json['completed_lessons'] as int? ?? 0,
      completionPercentage: (json['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      isCurrent: json['is_current'] as bool? ?? false,
      lessons: (json['lessons'] as List<dynamic>?)
              ?.map((e) => LessonProgressModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      iconUrl: json['icon_url'] as String?,
      backgroundColor: json['background_color'] as String? ?? '#2196F3',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unit_id': unitId,
      'unit_number': unitNumber,
      'title': title,
      'description': description,
      'total_lessons': totalLessons,
      'completed_lessons': completedLessons,
      'completion_percentage': completionPercentage,
      'is_current': isCurrent,
      'lessons': lessons.map((e) => e.toJson()).toList(),
      'icon_url': iconUrl,
      'background_color': backgroundColor,
    };
  }
}

/// Lesson Progress Model (for roadmap display)
class LessonProgressModel {
  final String lessonId;
  final int lessonNumber;
  final String title;
  final String? description;
  final bool isLocked;
  final bool isCurrent;
  final bool isCompleted;
  final double? bestScore;
  final int starsEarned;
  final int attemptsCount;
  final double completionPercentage;
  final String? iconUrl;
  final String backgroundColor;

  LessonProgressModel({
    required this.lessonId,
    required this.lessonNumber,
    required this.title,
    this.description,
    required this.isLocked,
    required this.isCurrent,
    required this.isCompleted,
    this.bestScore,
    required this.starsEarned,
    required this.attemptsCount,
    required this.completionPercentage,
    this.iconUrl,
    required this.backgroundColor,
  });

  factory LessonProgressModel.fromJson(Map<String, dynamic> json) {
    return LessonProgressModel(
      lessonId: json['lesson_id'] as String,
      lessonNumber: json['lesson_number'] as int? ?? 1,
      title: json['title'] as String,
      description: json['description'] as String?,
      isLocked: json['is_locked'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
      isCompleted: json['is_completed'] as bool? ?? false,
      bestScore: (json['best_score'] as num?)?.toDouble(),
      starsEarned: json['stars_earned'] as int? ?? 0,
      attemptsCount: json['attempts_count'] as int? ?? 0,
      completionPercentage: (json['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      iconUrl: json['icon_url'] as String?,
      backgroundColor: json['background_color'] as String? ?? '#4CAF50',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lesson_id': lessonId,
      'lesson_number': lessonNumber,
      'title': title,
      'description': description,
      'is_locked': isLocked,
      'is_current': isCurrent,
      'is_completed': isCompleted,
      'best_score': bestScore,
      'stars_earned': starsEarned,
      'attempts_count': attemptsCount,
      'completion_percentage': completionPercentage,
      'icon_url': iconUrl,
      'background_color': backgroundColor,
    };
  }
}
