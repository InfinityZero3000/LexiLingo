import 'package:equatable/equatable.dart';

/// Course Entity
/// Domain model for Course
class CourseEntity extends Equatable {
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
  final bool? isEnrolled;
  final double? userProgress;

  const CourseEntity({
    required this.id,
    required this.title,
    this.description,
    required this.language,
    required this.level,
    required this.tags,
    this.thumbnailUrl,
    required this.totalXp,
    required this.estimatedDuration,
    required this.totalLessons,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
    this.isEnrolled,
    this.userProgress,
  });

  CourseEntity copyWith({
    String? id,
    String? title,
    String? description,
    String? language,
    String? level,
    List<String>? tags,
    String? thumbnailUrl,
    int? totalXp,
    int? estimatedDuration,
    int? totalLessons,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isEnrolled,
    double? userProgress,
  }) {
    return CourseEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      language: language ?? this.language,
      level: level ?? this.level,
      tags: tags ?? this.tags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      totalXp: totalXp ?? this.totalXp,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      totalLessons: totalLessons ?? this.totalLessons,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEnrolled: isEnrolled ?? this.isEnrolled,
      userProgress: userProgress ?? this.userProgress,
    );
  }

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
      ];
}
