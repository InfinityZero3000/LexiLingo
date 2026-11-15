import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_exam_provider.dart';

ApiErrorException _refusal(Map<String, dynamic> details) => ApiErrorException(
  ErrorResponseEnvelope.fromJson({
    'error': {
      'code': 'AUTH_FORBIDDEN',
      'message': 'Level exam unavailable',
      'details': details,
    },
    'meta': {'request_id': 'r', 'timestamp': '2026-11-15T00:00:00Z'},
  }),
);

class _Source extends ProficiencyDataSource {
  _Source() : super(apiClient: ApiClient(enableLogging: false));

  Map<String, dynamic> eligibility = {
    'available': true,
    'reason': 'ready',
    'target_level': 'A2',
  };
  Object? startError;
  Map<String, String>? submitted;

  @override
  Future<Map<String, dynamic>> getLevelExamEligibility() async => eligibility;

  @override
  Future<Map<String, dynamic>> startLevelExam() async {
    if (startError != null) throw startError!;
    return {
      'attempt_id': 'att-1',
      'expires_at': '2026-11-15T10:00:00Z',
      'answers': {'q1': 'right'},
      'sections': [
        {
          'level': 'A2',
          'questions': [
            {
              'id': 'q1',
              'prompt': 'p1',
              'options': ['right', 'wrong'],
            },
            {
              'id': 'q2',
              'prompt': 'p2',
              'options': ['right', 'wrong'],
            },
          ],
        },
        {
          'level': 'B1',
          'questions': [
            {
              'id': 'q3',
              'prompt': 'p3',
              'options': ['right', 'wrong'],
            },
          ],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> submitLevelExam(
    String attemptId,
    Map<String, String> answers,
  ) async {
    submitted = answers;
    return {
      'passed': true,
      'result_level': 'B1',
      'certified_level': 'B1',
      'sections': [],
    };
  }
}

void main() {
  test('a refused gate is read from error.details, not the message', () async {
    final source = _Source()
      ..startError = _refusal({
        'reason': 'cooldown',
        'retry_at': '2026-11-16T10:00:00Z',
      });
    final exam = LevelExamProvider(dataSource: source);

    await exam.start();

    expect(exam.blockedReason, 'cooldown');
    expect(exam.gate['retry_at'], '2026-11-16T10:00:00Z');
    expect(exam.sitting, isFalse);
  });

  test('eligibility that is not available names its reason', () async {
    final source = _Source()
      ..eligibility = {
        'available': false,
        'reason': 'not_ready',
        'progress': 40,
      };
    final exam = LevelExamProvider(dataSource: source);

    await exam.loadEligibility();

    expect(exam.ready, isFalse);
    expect(exam.blockedReason, 'not_ready');
  });

  test(
    'a sitting flattens the sections, resumes saved answers and submits them',
    () async {
      final source = _Source();
      final exam = LevelExamProvider(dataSource: source);

      await exam.loadEligibility();
      expect(exam.ready, isTrue);
      await exam.start();

      expect(exam.questions.map((q) => '${q.level}:${q.id}'), [
        'A2:q1',
        'A2:q2',
        'B1:q3',
      ]);
      expect(exam.answers, {'q1': 'right'});
      expect(exam.allAnswered, isFalse);

      exam.goTo(1);
      exam.answer('wrong');
      exam.goTo(2);
      exam.answer('right');
      expect(exam.allAnswered, isTrue);

      final promoted = await exam.submit();
      expect(promoted, isTrue);
      expect(source.submitted, {'q1': 'right', 'q2': 'wrong', 'q3': 'right'});
      expect(exam.sitting, isFalse);
      expect(exam.result?['certified_level'], 'B1');
    },
  );
}
