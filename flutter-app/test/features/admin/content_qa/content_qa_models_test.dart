import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/content_qa/data/content_qa_repository.dart';

void main() {
  test('ContentQaJob.fromJson parses fields and derives a title from config', () {
    final job = ContentQaJob.fromJson({
      'id': 7,
      'status': 'preview_ready',
      'config': {'title_focus': 'Travel vocabulary'},
      'warnings': ['low confidence'],
      'blocking_errors': [],
      'created_entity_ids': {'lesson_id': 'l-1'},
      'updated_at': '2026-08-06T08:30:00Z',
      'completed_at': null,
    });

    expect(job.id, '7');
    expect(job.status, 'preview_ready');
    expect(job.warnings, ['low confidence']);
    expect(job.blockingErrors, isEmpty);
    expect(job.createdEntityIds, {'lesson_id': 'l-1'});
    expect(job.errorMessage, isNull);
    expect(job.updatedAt, isNotNull);
    expect(job.completedAt, isNull);
    expect(job.title, 'Travel vocabulary');
  });

  test('ContentQaJob.title falls back to levels then a generic label', () {
    final withLevels = ContentQaJob.fromJson({'id': '1', 'status': 'failed', 'config': {'levels': ['A1', 'A2']}});
    expect(withLevels.title, 'A1, A2');

    final withNothing = ContentQaJob.fromJson({'id': '2', 'status': 'failed', 'config': {}});
    expect(withNothing.title, 'Content job');
  });

  test('ContentQaLesson.fromJson parses nested exercises', () {
    final lesson = ContentQaLesson.fromJson({
      'title': 'Ordering food',
      'outcome': 'Order a meal in English',
      'exercises': [
        {
          'id': 'ex-1',
          'ui_type': 'multiple_choice',
          'question': 'Pick the right phrase',
          'correct_answer': 'Can I have...',
          'options': ['Can I have...', 'Give me'],
        },
      ],
    });

    expect(lesson.title, 'Ordering food');
    expect(lesson.outcome, 'Order a meal in English');
    expect(lesson.exercises, hasLength(1));
    expect(lesson.exercises.single.uiType, 'multiple_choice');
    expect(lesson.exercises.single.correctAnswer, 'Can I have...');
  });
}
