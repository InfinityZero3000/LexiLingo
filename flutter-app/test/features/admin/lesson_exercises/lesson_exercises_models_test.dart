import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/lesson_exercises/data/lesson_exercises_repository.dart';

void main() {
  test('Exercise parses and serializes the complete choice payload', () {
    final exercise = Exercise.fromJson({
      'id': 42,
      'type': 'multiple_choice',
      'ui_type': 'listen_and_choose',
      'question': 'What did you hear?',
      'options': [
        {'id': 1, 'text': 'Hello', 'is_correct': true},
        {'id': '2', 'text': 'Goodbye', 'is_correct': false},
      ],
      'correct_answer': 'Hello',
      'explanation': 'The speaker says hello.',
      'hint': 'Listen to the first word.',
      'audio_url': 'https://example.com/audio.mp3',
      'image_url': 'https://example.com/image.png',
      'difficulty': 3.0,
      'points': 20,
    });

    expect(exercise.id, '42');
    expect(exercise.uiType, 'listen_and_choose');
    expect(exercise.options, hasLength(2));
    expect(exercise.options!.first.toJson(), {
      'id': '1',
      'text': 'Hello',
      'is_correct': true,
    });
    expect(exercise.toJson(), {
      'id': '42',
      'type': 'multiple_choice',
      'ui_type': 'listen_and_choose',
      'question': 'What did you hear?',
      'options': [
        {'id': '1', 'text': 'Hello', 'is_correct': true},
        {'id': '2', 'text': 'Goodbye', 'is_correct': false},
      ],
      'correct_answer': 'Hello',
      'explanation': 'The speaker says hello.',
      'hint': 'Listen to the first word.',
      'audio_url': 'https://example.com/audio.mp3',
      'image_url': 'https://example.com/image.png',
      'difficulty': 3,
      'points': 20,
    });
  });

  test('Exercise preserves null optional fields for non-choice exercises', () {
    final exercise = Exercise.fromJson({
      'id': 'fill-1',
      'type': 'fill_blank',
      'ui_type': 'fill_in_the_blank',
      'question': 'I ___ happy.',
      'options': null,
      'correct_answer': 'am',
      'difficulty': 1,
      'points': 10,
    });

    expect(exercise.options, isNull);
    expect(exercise.explanation, isNull);
    expect(exercise.hint, isNull);
    expect(exercise.audioUrl, isNull);
    expect(exercise.imageUrl, isNull);
    expect(exercise.toJson()['options'], isNull);
  });

  test('Exercise applies safe defaults to a sparse API payload', () {
    final exercise = Exercise.fromJson(<String, dynamic>{});

    expect(exercise.id, '');
    expect(exercise.type, 'multiple_choice');
    expect(exercise.uiType, 'multiple_choice');
    expect(exercise.question, '');
    expect(exercise.correctAnswer, '');
    expect(exercise.options, isNull);
    expect(exercise.difficulty, 1);
    expect(exercise.points, 10);
  });
}
