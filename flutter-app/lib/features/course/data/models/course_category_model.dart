import '../../domain/entities/course_category_entity.dart';

/// Course Category Model
/// 
/// Data model for course categories with JSON serialization
class CourseCategoryModel extends CourseCategoryEntity {
  const CourseCategoryModel({
    required super.id,
    required super.name,
    required super.slug,
    super.description,
    super.icon,
    super.color,
    required super.courseCount,
  });

  /// Create from JSON
  factory CourseCategoryModel.fromJson(Map<String, dynamic> json) {
    return CourseCategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      courseCount: json['course_count'] as int? ?? 0,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'icon': icon,
      'color': color,
      'course_count': courseCount,
    };
  }

  /// Create from entity
  factory CourseCategoryModel.fromEntity(CourseCategoryEntity entity) {
    return CourseCategoryModel(
      id: entity.id,
      name: entity.name,
      slug: entity.slug,
      description: entity.description,
      icon: entity.icon,
      color: entity.color,
      courseCount: entity.courseCount,
    );
  }

  /// Convert to entity
  CourseCategoryEntity toEntity() {
    return CourseCategoryEntity(
      id: id,
      name: name,
      slug: slug,
      description: description,
      icon: icon,
      color: color,
      courseCount: courseCount,
    );
  }
}
