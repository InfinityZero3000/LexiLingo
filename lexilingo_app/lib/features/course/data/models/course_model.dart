import 'package:lexilingo_app/features/course/domain/entities/course.dart';

class CourseModel extends Course {
  CourseModel({
    int? id,
    required String title,
    required String description,
    required String level,
    double progress = 0.0,
  }) : super(
          id: id,
          title: title,
          description: description,
          level: level,
          progress: progress,
        );

  // Convert from JSON to Model
  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['id'] as int?,
      title: json['title'] as String,
      description: json['description'] as String,
      level: json['level'] as String,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // Convert from Model to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'level': level,
      'progress': progress,
    };
  }

  // Convert from Entity to Model
  factory CourseModel.fromEntity(Course entity) {
    return CourseModel(
      id: entity.id,
      title: entity.title,
      description: entity.description,
      level: entity.level,
      progress: entity.progress,
    );
  }
}
