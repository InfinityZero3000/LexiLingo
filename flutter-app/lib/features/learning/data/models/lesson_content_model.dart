import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';

/// Model for lesson content from API
/// Maps to LessonContentResponse from backend
class LessonContentModel {
  final String id;
  final String title;
  final String? description;
  final String lessonType;
  final int orderIndex;
  final int xpReward;
  final int passThreshold;
  final int estimatedMinutes;
  final int totalExercises;
  final List<ExerciseModel> exercises;

  LessonContentModel({
    required this.id,
    required this.title,
    this.description,
    required this.lessonType,
    required this.orderIndex,
    required this.xpReward,
    required this.passThreshold,
    required this.estimatedMinutes,
    required this.totalExercises,
    required this.exercises,
  });

  factory LessonContentModel.fromJson(Map<String, dynamic> json) {
    return LessonContentModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      lessonType: json['lesson_type'] as String? ?? 'lesson',
      orderIndex: json['order_index'] as int? ?? 0,
      xpReward: json['xp_reward'] as int? ?? 10,
      passThreshold: json['pass_threshold'] as int? ?? 80,
      estimatedMinutes: json['estimated_minutes'] as int? ?? 10,
      totalExercises: json['total_exercises'] as int? ?? 0,
      exercises: (json['exercises'] as List?)
              ?.map((e) => ExerciseModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Convert to LessonEntity for domain layer
  LessonEntity toEntity() {
    return LessonEntity(
      id: id,
      title: title,
      description: description,
      orderIndex: orderIndex,
      exercises: exercises.map((e) => e.toEntity()).toList(),
      estimatedMinutes: estimatedMinutes,
      xpReward: xpReward,
    );
  }
}

/// Exercise model from API
class ExerciseModel {
  final String id;
  final String type;
  final String question;
  final List<ExerciseOptionModel>? options;
  final String correctAnswer;
  final String? explanation;
  final String? hint;
  final String? audioUrl;
  final String? imageUrl;
  final int difficulty;
  final int points;

  ExerciseModel({
    required this.id,
    required this.type,
    required this.question,
    this.options,
    required this.correctAnswer,
    this.explanation,
    this.hint,
    this.audioUrl,
    this.imageUrl,
    this.difficulty = 1,
    this.points = 10,
  });

  factory ExerciseModel.fromJson(Map<String, dynamic> json) {
    return ExerciseModel(
      id: json['id']?.toString() ?? '',
      type: json['type'] as String? ?? 'multiple_choice',
      question: json['question'] as String? ?? '',
      options: (json['options'] as List?)
          ?.map((e) => ExerciseOptionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      correctAnswer: json['correct_answer']?.toString() ?? '',
      explanation: json['explanation'] as String?,
      hint: json['hint'] as String?,
      audioUrl: json['audio_url'] as String?,
      imageUrl: json['image_url'] as String?,
      difficulty: json['difficulty'] as int? ?? 1,
      points: json['points'] as int? ?? 10,
    );
  }

  /// Convert to Exercise entity
  Exercise toEntity() {
    return Exercise(
      id: id,
      type: _parseExerciseType(type),
      question: question,
      options: options?.map((o) => o.text).toList(),
      correctAnswer: correctAnswer,
      explanation: explanation,
      hint: hint,
      audioUrl: audioUrl,
      metadata: {
        'difficulty': difficulty,
        'points': points,
        if (imageUrl != null) 'image_url': imageUrl,
      },
    );
  }

  ExerciseType _parseExerciseType(String type) {
    switch (type.toLowerCase()) {
      case 'multiple_choice':
        return ExerciseType.multipleChoice;
      case 'true_false':
        return ExerciseType.trueFalse;
      case 'fill_blank':
      case 'fill_in_blank':
        return ExerciseType.fillInBlank;
      case 'translate':
        return ExerciseType.translate;
      case 'listening':
        return ExerciseType.listening;
      case 'speaking':
        return ExerciseType.speaking;
      default:
        return ExerciseType.multipleChoice;
    }
  }
}

/// Exercise option model
class ExerciseOptionModel {
  final String id;
  final String text;
  final bool isCorrect;

  ExerciseOptionModel({
    required this.id,
    required this.text,
    this.isCorrect = false,
  });

  factory ExerciseOptionModel.fromJson(Map<String, dynamic> json) {
    return ExerciseOptionModel(
      id: json['id']?.toString() ?? '',
      text: json['text'] as String? ?? '',
      isCorrect: json['is_correct'] as bool? ?? false,
    );
  }
}
