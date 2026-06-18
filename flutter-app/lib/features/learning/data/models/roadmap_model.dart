import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';

/// Course Roadmap Model
/// Represents response from GET /learning/courses/{id}/roadmap
class CourseRoadmapModel extends CourseRoadmap {
  const CourseRoadmapModel({
    required super.courseId,
    required super.courseTitle,
    required super.level,
    required super.totalUnits,
    required super.completedUnits,
    required super.totalLessons,
    required super.completedLessons,
    required super.completionPercentage,
    required super.totalXpEarned,
    required super.currentStreak,
    required super.units,
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
      completionPercentage:
          (json['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      totalXpEarned: json['total_xp_earned'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      units:
          (json['units'] as List<dynamic>?)
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
      // invariant: units is always List<UnitRoadmapModel> when built via fromJson
      'units': units.map((e) => (e as UnitRoadmapModel).toJson()).toList(),
    };
  }
}

/// Unit Roadmap Model
class UnitRoadmapModel extends UnitRoadmap {
  const UnitRoadmapModel({
    required super.unitId,
    required super.unitNumber,
    required super.title,
    super.description,
    required super.totalLessons,
    required super.completedLessons,
    required super.completionPercentage,
    required super.isCurrent,
    required super.lessons,
    super.iconUrl,
    required super.backgroundColor,
  });

  factory UnitRoadmapModel.fromJson(Map<String, dynamic> json) {
    return UnitRoadmapModel(
      unitId: json['unit_id'] as String,
      unitNumber: json['unit_number'] as int? ?? 1,
      title: json['title'] as String,
      description: json['description'] as String?,
      totalLessons: json['total_lessons'] as int? ?? 0,
      completedLessons: json['completed_lessons'] as int? ?? 0,
      completionPercentage:
          (json['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      isCurrent: json['is_current'] as bool? ?? false,
      lessons:
          (json['lessons'] as List<dynamic>?)
              ?.map(
                (e) => LessonProgressModel.fromJson(e as Map<String, dynamic>),
              )
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
      // invariant: lessons is always List<LessonProgressModel> when built via fromJson
      'lessons': lessons.map((e) => (e as LessonProgressModel).toJson()).toList(),
      'icon_url': iconUrl,
      'background_color': backgroundColor,
    };
  }
}

/// Lesson Progress Model (for roadmap display)
class LessonProgressModel extends LessonProgress {
  const LessonProgressModel({
    required super.lessonId,
    required super.lessonNumber,
    required super.title,
    super.description,
    required super.isLocked,
    required super.isCurrent,
    required super.isCompleted,
    super.bestScore,
    required super.starsEarned,
    required super.attemptsCount,
    required super.completionPercentage,
    super.iconUrl,
    required super.backgroundColor,
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
      completionPercentage:
          (json['completion_percentage'] as num?)?.toDouble() ?? 0.0,
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
