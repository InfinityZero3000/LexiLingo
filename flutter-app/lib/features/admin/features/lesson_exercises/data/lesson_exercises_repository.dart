import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';

class ExerciseOption {
  final String id;
  final String text;
  final bool isCorrect;

  const ExerciseOption({
    required this.id,
    required this.text,
    required this.isCorrect,
  });

  factory ExerciseOption.fromJson(Map<String, dynamic> json) => ExerciseOption(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        isCorrect: json['is_correct'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'is_correct': isCorrect,
      };
}

class Exercise {
  final String id;
  final String type;
  final String uiType;
  final String question;
  final List<ExerciseOption>? options;
  final String correctAnswer;
  final String? explanation;
  final String? hint;
  final String? audioUrl;
  final String? imageUrl;
  final int difficulty;
  final int points;

  const Exercise({
    required this.id,
    required this.type,
    required this.uiType,
    required this.question,
    this.options,
    required this.correctAnswer,
    this.explanation,
    this.hint,
    this.audioUrl,
    this.imageUrl,
    required this.difficulty,
    required this.points,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'multiple_choice',
        uiType: json['ui_type']?.toString() ?? 'multiple_choice',
        question: json['question']?.toString() ?? '',
        options: json['options'] is List
            ? (json['options'] as List)
                .map((item) => ExerciseOption.fromJson(
                    Map<String, dynamic>.from(item as Map)))
                .toList()
            : null,
        correctAnswer: json['correct_answer']?.toString() ?? '',
        explanation: json['explanation']?.toString(),
        hint: json['hint']?.toString(),
        audioUrl: json['audio_url']?.toString(),
        imageUrl: json['image_url']?.toString(),
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
        points: (json['points'] as num?)?.toInt() ?? 10,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'ui_type': uiType,
        'question': question,
        'options': options?.map((option) => option.toJson()).toList(),
        'correct_answer': correctAnswer,
        'explanation': explanation,
        'hint': hint,
        'audio_url': audioUrl,
        'image_url': imageUrl,
        'difficulty': difficulty,
        'points': points,
      };
}

class LessonExercisesRepository {
  final _api = ApiClient.instance;

  Future<List<Exercise>> getLessonContent(String lessonId) async {
    final response = await _api.get('${ApiEndpoints.adminLessons}/$lessonId');
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final content = data['content'] as Map<String, dynamic>?;
    return ((content?['exercises'] as List?) ?? [])
        .map((item) => Exercise.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> saveLessonContent(
    String lessonId,
    List<Exercise> exercises,
  ) =>
      _api.put(
        '${ApiEndpoints.adminLessons}/$lessonId/content',
        data: {
          'content': {
            'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
          },
          'total_exercises': exercises.length,
        },
      );
}
