import 'package:lexilingo_app/features/course/domain/entities/unit_entity.dart';

/// Lesson In Unit Model for JSON serialization
class LessonInUnitModel extends LessonInUnitEntity {
  const LessonInUnitModel({
    required super.id,
    required super.title,
    required super.orderIndex,
    required super.lessonType,
    super.xpReward,
    super.isLocked,
    super.isCompleted,
  });

  factory LessonInUnitModel.fromJson(Map<String, dynamic> json) {
    return LessonInUnitModel(
      id: json['id'] as String,
      title: json['title'] as String,
      orderIndex: json['order_index'] as int,
      lessonType: json['lesson_type'] as String,
      xpReward: json['xp_reward'] as int? ?? 10,
      isLocked: json['is_locked'] as bool?,
      isCompleted: json['is_completed'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'order_index': orderIndex,
      'lesson_type': lessonType,
      'xp_reward': xpReward,
      'is_locked': isLocked,
      'is_completed': isCompleted,
    };
  }
}

/// Unit Model for JSON serialization
class UnitModel extends UnitEntity {
  const UnitModel({
    required super.id,
    required super.courseId,
    required super.title,
    super.description,
    required super.orderIndex,
    super.backgroundColor,
    super.iconUrl,
    super.totalLessons,
    required super.createdAt,
    required super.updatedAt,
    super.lessons,
  });

  factory UnitModel.fromJson(Map<String, dynamic> json) {
    return UnitModel(
      id: json['id'] as String,
      courseId: json['course_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      orderIndex: json['order_index'] as int,
      backgroundColor: json['background_color'] as String?,
      iconUrl: json['icon_url'] as String?,
      totalLessons: json['total_lessons'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lessons: (json['lessons'] as List<dynamic>?)
              ?.map((e) => LessonInUnitModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'course_id': courseId,
      'title': title,
      'description': description,
      'order_index': orderIndex,
      'background_color': backgroundColor,
      'icon_url': iconUrl,
      'total_lessons': totalLessons,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'lessons': lessons
          .map((l) => LessonInUnitModel(
                id: l.id,
                title: l.title,
                orderIndex: l.orderIndex,
                lessonType: l.lessonType,
                xpReward: l.xpReward,
                isLocked: l.isLocked,
                isCompleted: l.isCompleted,
              ).toJson())
          .toList(),
    };
  }

  factory UnitModel.fromEntity(UnitEntity entity) {
    return UnitModel(
      id: entity.id,
      courseId: entity.courseId,
      title: entity.title,
      description: entity.description,
      orderIndex: entity.orderIndex,
      backgroundColor: entity.backgroundColor,
      iconUrl: entity.iconUrl,
      totalLessons: entity.totalLessons,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      lessons: entity.lessons
          .map((l) => LessonInUnitModel(
                id: l.id,
                title: l.title,
                orderIndex: l.orderIndex,
                lessonType: l.lessonType,
                xpReward: l.xpReward,
                isLocked: l.isLocked,
                isCompleted: l.isCompleted,
              ))
          .toList(),
    );
  }
}
