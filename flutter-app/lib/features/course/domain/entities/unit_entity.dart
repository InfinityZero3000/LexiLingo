import 'package:equatable/equatable.dart';

/// Unit entity representing a group of lessons within a course
/// Matches backend Unit model schema
class UnitEntity extends Equatable {
  final String id;
  final String courseId;
  final String title;
  final String? description;
  final int orderIndex;
  final String? backgroundColor;
  final String? iconUrl;
  final int totalLessons;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Nested lessons
  final List<LessonInUnitEntity> lessons;

  const UnitEntity({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    required this.orderIndex,
    this.backgroundColor,
    this.iconUrl,
    this.totalLessons = 0,
    required this.createdAt,
    required this.updatedAt,
    this.lessons = const [],
  });

  @override
  List<Object?> get props => [
        id,
        courseId,
        title,
        description,
        orderIndex,
        backgroundColor,
        iconUrl,
        totalLessons,
        createdAt,
        updatedAt,
        lessons,
      ];
}

/// Lightweight lesson info within a unit (for roadmap display)
class LessonInUnitEntity extends Equatable {
  final String id;
  final String title;
  final int orderIndex;
  final String lessonType; // lesson, practice, review, test
  final int xpReward;
  final bool? isLocked;
  final bool? isCompleted;

  const LessonInUnitEntity({
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
