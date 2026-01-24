import 'package:lexilingo_app/features/course/domain/entities/course.dart';

class CourseModel extends Course {
  CourseModel({
    int? id,
    required String title,
    required String description,
    required String level,
    String? category,
    String? imageUrl,
    String? duration,
    int lessonsCount = 0,
    bool isFeatured = false,
    double rating = 0.0,
    int enrolledCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : super(
          id: id,
          title: title,
          description: description,
          level: level,
          category: category,
          imageUrl: imageUrl,
          duration: duration,
          lessonsCount: lessonsCount,
          isFeatured: isFeatured,
          rating: rating,
          enrolledCount: enrolledCount,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

  // Convert from JSON/Database to Model
  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['id'] as int?,
      title: json['title'] as String,
      description: json['description'] as String,
      level: json['level'] as String,
      category: json['category'] as String?,
      imageUrl: json['imageUrl'] as String?,
      duration: json['duration'] as String?,
      lessonsCount: (json['lessonsCount'] as int?) ?? 0,
      isFeatured: (json['isFeatured'] as int?) == 1,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      enrolledCount: (json['enrolledCount'] as int?) ?? 0,
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null 
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  // Convert from Model to JSON/Database
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'level': level,
      'category': category,
      'imageUrl': imageUrl,
      'duration': duration,
      'lessonsCount': lessonsCount,
      'isFeatured': isFeatured ? 1 : 0,
      'rating': rating,
      'enrolledCount': enrolledCount,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // Convert from Entity to Model
  factory CourseModel.fromEntity(Course entity) {
    return CourseModel(
      id: entity.id,
      title: entity.title,
      description: entity.description,
      level: entity.level,
      category: entity.category,
      imageUrl: entity.imageUrl,
      duration: entity.duration,
      lessonsCount: entity.lessonsCount,
      isFeatured: entity.isFeatured,
      rating: entity.rating,
      enrolledCount: entity.enrolledCount,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}


