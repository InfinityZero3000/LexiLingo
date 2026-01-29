/// Lesson Entity
/// Represents a lesson with its exercises
class LessonEntity {
  final String id;
  final String title;
  final String? description;
  final int orderIndex;
  final List<Exercise> exercises;
  final int estimatedMinutes;
  final int xpReward;

  LessonEntity({
    required this.id,
    required this.title,
    this.description,
    required this.orderIndex,
    required this.exercises,
    required this.estimatedMinutes,
    required this.xpReward,
  });

  factory LessonEntity.fromJson(Map<String, dynamic> json) {
    return LessonEntity(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      orderIndex: json['order_index'] as int,
      exercises: (json['exercises'] as List?)
              ?.map((e) => Exercise.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      estimatedMinutes: json['estimated_minutes'] as int? ?? 10,
      xpReward: json['xp_reward'] as int? ?? 50,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'order_index': orderIndex,
      'exercises': exercises.map((e) => e.toJson()).toList(),
      'estimated_minutes': estimatedMinutes,
      'xp_reward': xpReward,
    };
  }
}

/// Exercise Types
enum ExerciseType {
  multipleChoice,
  trueFalse,
  fillInBlank,
  translate,
  listening,
  speaking,
}

/// Exercise Entity
/// Represents an individual exercise within a lesson
class Exercise {
  final String id;
  final ExerciseType type;
  final String question;
  final List<String>? options;  // For multiple choice
  final String correctAnswer;
  final String? explanation;
  final String? hint;
  final String? audioUrl;  // For listening exercises
  final Map<String, dynamic>? metadata;

  Exercise({
    required this.id,
    required this.type,
    required this.question,
    this.options,
    required this.correctAnswer,
    this.explanation,
    this.hint,
    this.audioUrl,
    this.metadata,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      type: _parseExerciseType(json['type'] as String),
      question: json['question'] as String,
      options: (json['options'] as List?)?.map((e) => e as String).toList(),
      correctAnswer: json['correct_answer'] as String,
      explanation: json['explanation'] as String?,
      hint: json['hint'] as String?,
      audioUrl: json['audio_url'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'question': question,
      'options': options,
      'correct_answer': correctAnswer,
      'explanation': explanation,
      'hint': hint,
      'audio_url': audioUrl,
      'metadata': metadata,
    };
  }

  static ExerciseType _parseExerciseType(String type) {
    switch (type.toLowerCase()) {
      case 'multiple_choice':
      case 'multiplechoice':
        return ExerciseType.multipleChoice;
      case 'true_false':
      case 'truefalse':
        return ExerciseType.trueFalse;
      case 'fill_in_blank':
      case 'fillinblank':
        return ExerciseType.fillInBlank;
      case 'translate':
      case 'translation':
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
