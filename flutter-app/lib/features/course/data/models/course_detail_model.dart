import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';

/// Lesson In Roadmap Model
class LessonInRoadmapModel extends LessonInRoadmapEntity {
  const LessonInRoadmapModel({
    required super.id,
    required super.title,
    required super.orderIndex,
    required super.lessonType,
    super.xpReward,
    super.isLocked,
    super.isCompleted,
  });

  factory LessonInRoadmapModel.fromJson(Map<String, dynamic> json) {
    return LessonInRoadmapModel(
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

/// Unit With Lessons Model
class UnitWithLessonsModel extends UnitWithLessonsEntity {
  const UnitWithLessonsModel({
    required super.id,
    required super.title,
    super.description,
    required super.orderIndex,
    super.backgroundColor,
    super.iconUrl,
    super.lessons,
  });

  factory UnitWithLessonsModel.fromJson(Map<String, dynamic> json) {
    return UnitWithLessonsModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      orderIndex: json['order_index'] as int,
      backgroundColor: json['background_color'] as String?,
      iconUrl: json['icon_url'] as String?,
      lessons: (json['lessons'] as List<dynamic>?)
              ?.map((e) => LessonInRoadmapModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'order_index': orderIndex,
      'background_color': backgroundColor,
      'icon_url': iconUrl,
      'lessons': lessons
          .map((l) => LessonInRoadmapModel(
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

  static LessonInRoadmapModel fromEntity(LessonInRoadmapEntity entity) {
    return LessonInRoadmapModel(
      id: entity.id,
      title: entity.title,
      orderIndex: entity.orderIndex,
      lessonType: entity.lessonType,
      xpReward: entity.xpReward,
      isLocked: entity.isLocked,
      isCompleted: entity.isCompleted,
    );
  }
}

/// Course Detail Model
class CourseDetailModel extends CourseDetailEntity {
  const CourseDetailModel({
    required super.id,
    required super.title,
    super.description,
    required super.language,
    required super.level,
    super.tags,
    super.thumbnailUrl,
    super.totalXp,
    super.estimatedDuration,
    super.totalLessons,
    super.isPublished,
    required super.createdAt,
    required super.updatedAt,
    super.isEnrolled,
    super.userProgress,
    super.units,
  });

  factory CourseDetailModel.fromJson(Map<String, dynamic> json) {
    return CourseDetailModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      language: json['language'] as String,
      level: json['level'] as String,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      totalXp: json['total_xp'] as int? ?? 0,
      estimatedDuration: json['estimated_duration'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      isPublished: json['is_published'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isEnrolled: json['is_enrolled'] as bool?,
      userProgress: (json['user_progress'] as num?)?.toDouble(),
      units: (json['units'] as List<dynamic>?)
              ?.map((e) => UnitWithLessonsModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'language': language,
      'level': level,
      'tags': tags,
      'thumbnail_url': thumbnailUrl,
      'total_xp': totalXp,
      'estimated_duration': estimatedDuration,
      'total_lessons': totalLessons,
      'is_published': isPublished,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_enrolled': isEnrolled,
      'user_progress': userProgress,
      'units': units
          .map((u) => UnitWithLessonsModel(
                id: u.id,
                title: u.title,
                description: u.description,
                orderIndex: u.orderIndex,
                backgroundColor: u.backgroundColor,
                iconUrl: u.iconUrl,
                lessons: u.lessons
                    .map((l) => LessonInRoadmapModel(
                          id: l.id,
                          title: l.title,
                          orderIndex: l.orderIndex,
                          lessonType: l.lessonType,
                          xpReward: l.xpReward,
                          isLocked: l.isLocked,
                          isCompleted: l.isCompleted,
                        ))
                    .toList(),
              ).toJson())
          .toList(),
    };
  }

  static UnitWithLessonsModel fromEntity(UnitWithLessonsEntity entity) {
    return UnitWithLessonsModel(
      id: entity.id,
      title: entity.title,
      description: entity.description,
      orderIndex: entity.orderIndex,
      backgroundColor: entity.backgroundColor,
      iconUrl: entity.iconUrl,
      lessons: entity.lessons,
    );
  }
}
