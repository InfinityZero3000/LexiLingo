import 'package:equatable/equatable.dart';

/// Course detail with nested units and lessons (roadmap view)
class CourseDetailEntity extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String language;
  final String level;
  final List<String> tags;
  final String? thumbnailUrl;
  final int totalXp;
  final int estimatedDuration;
  final int totalLessons;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // User-specific
  final bool? isEnrolled;
  final double? userProgress;
  
  // Nested units with lessons
  final List<UnitWithLessonsEntity> units;

  const CourseDetailEntity({
    required this.id,
    required this.title,
    this.description,
    required this.language,
    required this.level,
    this.tags = const [],
    this.thumbnailUrl,
    this.totalXp = 0,
    this.estimatedDuration = 0,
    this.totalLessons = 0,
    this.isPublished = false,
    required this.createdAt,
    required this.updatedAt,
    this.isEnrolled,
    this.userProgress,
    this.units = const [],
  });

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        language,
        level,
        tags,
        thumbnailUrl,
        totalXp,
        estimatedDuration,
        totalLessons,
        isPublished,
        createdAt,
        updatedAt,
        isEnrolled,
        userProgress,
        units,
      ];
}

/// Unit with its lessons for roadmap display
class UnitWithLessonsEntity extends Equatable {
  final String id;
  final String title;
  final String? description;
  final int orderIndex;
  final String? backgroundColor;
  final String? iconUrl;
  final List<LessonInRoadmapEntity> lessons;

  const UnitWithLessonsEntity({
    required this.id,
    required this.title,
    this.description,
    required this.orderIndex,
    this.backgroundColor,
    this.iconUrl,
    this.lessons = const [],
  });

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        orderIndex,
        backgroundColor,
        iconUrl,
        lessons,
      ];
}

/// Lesson info for roadmap display
class LessonInRoadmapEntity extends Equatable {
  final String id;
  final String title;
  final int orderIndex;
  final String lessonType;
  final int xpReward;
  final bool? isLocked;
  final bool? isCompleted;

  const LessonInRoadmapEntity({
    required this.id,
    required this.title,
    required this.orderIndex,
    required this.lessonType,
    this.xpReward = 10,
    this.isLocked,
    this.isCompleted,
  });

  @override
  List<Object?> get props => [
        id,
        title,
        orderIndex,
        lessonType,
        xpReward,
        isLocked,
        isCompleted,
      ];
}
