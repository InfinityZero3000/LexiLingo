class Course {
  final int? id;
  final String title;
  final String description;
  final String level;
  final String? category;
  final String? imageUrl;
  final String? duration;
  final int lessonsCount;
  final bool isFeatured;
  final double rating;
  final int enrolledCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Course({
    this.id,
    required this.title,
    required this.description,
    required this.level,
    this.category,
    this.imageUrl,
    this.duration,
    this.lessonsCount = 0,
    this.isFeatured = false,
    this.rating = 0.0,
    this.enrolledCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  Course copyWith({
    int? id,
    String? title,
    String? description,
    String? level,
    String? category,
    String? imageUrl,
    String? duration,
    int? lessonsCount,
    bool? isFeatured,
    double? rating,
    int? enrolledCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Course(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      level: level ?? this.level,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      duration: duration ?? this.duration,
      lessonsCount: lessonsCount ?? this.lessonsCount,
      isFeatured: isFeatured ?? this.isFeatured,
      rating: rating ?? this.rating,
      enrolledCount: enrolledCount ?? this.enrolledCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

