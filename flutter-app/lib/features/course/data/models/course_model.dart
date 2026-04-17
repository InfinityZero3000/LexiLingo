import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

/// Course Model
/// Maps JSON from backend API to CourseEntity
class CourseModel extends CourseEntity {
  const CourseModel({
    required super.id,
    required super.title,
    super.description,
    required super.language,
    required super.level,
    required super.tags,
    super.thumbnailUrl,
    required super.totalXp,
    required super.estimatedDuration,
    required super.totalLessons,
    required super.isPublished,
    required super.createdAt,
    required super.updatedAt,
    super.isEnrolled,
    super.userProgress,
  });

  /// Convert from JSON to Model
  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      language: json['language'] as String,
      level: json['level'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      totalXp: (json['total_xp'] as int?) ?? 0,
      estimatedDuration: (json['estimated_duration'] as int?) ?? 0,
      totalLessons: (json['total_lessons'] as int?) ?? 0,
      isPublished: (json['is_published'] as bool?) ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      isEnrolled: json['is_enrolled'] as bool?,
      userProgress: (json['user_progress'] as num?)?.toDouble(),
    );
  }

  /// Convert from Model to JSON
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
    };
  }

  /// Convert from Entity to Model
  factory CourseModel.fromEntity(CourseEntity entity) {
    return CourseModel(
      id: entity.id,
      title: entity.title,
      description: entity.description,
      language: entity.language,
      level: entity.level,
      tags: entity.tags,
      thumbnailUrl: entity.thumbnailUrl,
      totalXp: entity.totalXp,
      estimatedDuration: entity.estimatedDuration,
      totalLessons: entity.totalLessons,
      isPublished: entity.isPublished,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      isEnrolled: entity.isEnrolled,
      userProgress: entity.userProgress,
    );
  }
}
