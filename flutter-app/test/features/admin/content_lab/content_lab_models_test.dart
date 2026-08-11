import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/content_lab/data/content_lab_repository.dart';

void main() {
  test('QuestionItem.fromJson parses API fields and defaults optional values', () {
    final question = QuestionItem.fromJson({
      'id': 12,
      'prompt': 'Choose the correct answer',
      'question_type': 'multiple_choice',
      'options': ['is', 'are'],
      'answer': 'is',
      'tags': ['grammar', 1],
    });

    expect(question.id, '12');
    expect(question.prompt, 'Choose the correct answer');
    expect(question.questionType, 'multiple_choice');
    expect(question.options, ['is', 'are']);
    expect(question.answer, 'is');
    expect(question.explanation, isNull);
    expect(question.difficultyLevel, 'A1');
    expect(question.tags, ['grammar', '1']);
    expect(question.grammarId, isNull);
    expect(question.isActive, isTrue);
  });

  test('TestExam.fromJson parses numeric fields and question identifiers', () {
    final exam = TestExam.fromJson({
      'id': 'exam-1',
      'title': 'A2 checkpoint',
      'description': 'End-of-level test',
      'level': 'A2',
      'duration_minutes': 45.0,
      'passing_score': 80,
      'question_ids': [1, 'q-2'],
      'is_published': true,
    });

    expect(exam.id, 'exam-1');
    expect(exam.title, 'A2 checkpoint');
    expect(exam.description, 'End-of-level test');
    expect(exam.level, 'A2');
    expect(exam.durationMinutes, 45);
    expect(exam.passingScore, 80);
    expect(exam.questionIds, ['1', 'q-2']);
    expect(exam.isPublished, isTrue);
  });
}
