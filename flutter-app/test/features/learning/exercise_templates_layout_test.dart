import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/learning/domain/entities/answer_response.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_attempt.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_complete.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_course_roadmap_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_lesson_content_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/start_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/submit_answer_usecase.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:provider/provider.dart';

const _long =
    'Although the committee had considered several alternative proposals for the redevelopment of the harbour district, it ultimately rejected every one of them';

Exercise _ex(
  String id,
  String uiType,
  String question,
  String answer, {
  List<String>? options,
  ExerciseType type = ExerciseType.multipleChoice,
}) => Exercise(
  id: id,
  type: type,
  uiType: uiType,
  phase: 'pre_task',
  question: question,
  options: options,
  correctAnswer: answer,
  explanation: 'Because the passage says so.',
);

List<Exercise> _exercises({required bool worst}) {
  final q = worst ? _long : 'Choose the best answer';
  final opt = worst
      ? ['$_long (A)', '$_long (B)', '$_long (C)', '$_long (D)']
      : ['alpha', 'beta', 'gamma', 'delta'];
  final pairs = worst ? 6 : 4;
  final keys = [
    for (var i = 0; i < pairs; i++) worst ? 'word number $i' : 'w$i',
  ];
  final vals = [
    for (var i = 0; i < pairs; i++)
      worst ? 'nghĩa rất dài của từ số $i trong tiếng Việt' : 'n$i',
  ];
  final pairOptions = [...keys, ...vals];
  final pairAnswer = [
    for (var i = 0; i < pairs; i++) '${keys[i]}:${vals[i]}',
  ].join(', ');
  final bank = worst
      ? _long.split(' ')
      : ['I', 'like', 'green', 'tea', 'very', 'much'];
  final tag = worst ? 'w' : 'n';
  return [
    _ex(
      '$tag-match',
      'match_word_to_meaning',
      q,
      pairAnswer,
      options: pairOptions,
      type: ExerciseType.matching,
    ),
    _ex(
      '$tag-cat',
      'categorization',
      q,
      pairAnswer,
      options: pairOptions,
      type: ExerciseType.matching,
    ),
    _ex(
      '$tag-cog',
      'cognitive_fluidity',
      q,
      pairAnswer,
      options: pairOptions,
      type: ExerciseType.matching,
    ),
    _ex(
      '$tag-arr',
      'arrange_the_sentence',
      q,
      bank.join(' '),
      options: bank,
      type: ExerciseType.fillInBlank,
    ),
    _ex('$tag-mc', 'multiple_choice', q, opt.first, options: opt),
    _ex(
      '$tag-tf',
      'true_or_false',
      q,
      'True',
      options: const ['True', 'False'],
      type: ExerciseType.trueFalse,
    ),
    _ex(
      '$tag-fb',
      'fill_in_the_blank',
      '$q: She ___ to school.',
      'goes',
      type: ExerciseType.fillInBlank,
    ),
    _ex(
      '$tag-dic',
      'dictation',
      'Listen and type',
      'first sentence',
      type: ExerciseType.fillInBlank,
    ),
    _ex(
      '$tag-gc',
      'grammar_correction',
      "Correct the error: 'She go to school every day'",
      'goes',
      type: ExerciseType.fillInBlank,
    ),
    _ex('$tag-lc', 'listen_and_choose', q, opt.first, options: opt),
    _ex(
      '$tag-sr',
      'speaking_repeat',
      worst ? _long : 'Nice to meet you',
      'Nice to meet you',
      type: ExerciseType.fillInBlank,
    ),
    _ex(
      '$tag-pp',
      'pronunciation_practice',
      worst ? _long : 'thought',
      'thought',
      type: ExerciseType.fillInBlank,
    ),
    _ex(
      '$tag-rc',
      'reading_comprehension',
      '$_long. $_long. $q',
      opt.first,
      options: opt,
    ),
    _ex(
      '$tag-sw',
      'short_writing_answer',
      '$q: describe your day',
      'x',
      type: ExerciseType.fillInBlank,
    ),
    _ex(
      '$tag-tc',
      'translation_choice',
      "Translate: '$q'",
      opt.first,
      options: opt,
    ),
    _ex(
      '$tag-col',
      'collocation_choice',
      "Which word goes with 'make'? $q",
      opt.first,
      options: opt,
    ),
    _ex(
      '$tag-dlg',
      'dialogue_completion',
      'A: How are you?\nB: ___',
      'Fine',
      options: opt..[0] = 'Fine',
    ),
    _ex(
      '$tag-vf',
      'vocabulary_flashcard',
      "Learn the word: 'resilient'",
      'resilient',
      type: ExerciseType.fillInBlank,
    ),
  ];
}

/// Every exercise template, rendered through the real session screen at three
/// screen sizes, with typical and worst-case content. A template that cannot
/// scroll or wrap shows up as a RenderFlex overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontDir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/usr/local/share/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final hasFont = File('$fontDir/Roboto-Regular.ttf').existsSync();

  setUpAll(() async {
    // flutter_test's default font (Ahem) makes every glyph a full em wide, which
    // reports overflows no real device has. Measure with a real font instead.
    if (!hasFont) return;
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Bold']) {
      final bytes = File('$fontDir/Roboto-$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });
  setUp(() => EasyLocalization.logger.enableLevels = []);

  final sizes = <String, Size>{
    'phone-320x568': const Size(320, 568),
    'phone-390x844': const Size(390, 844),
    'desktop-1280x800': const Size(1280, 800),
  };

  for (final entry in sizes.entries) {
    for (final worst in [false, true]) {
      testWidgets(
        'no template overflows: ${entry.key}, ${worst ? 'long text and many options' : 'typical content'}',
        skip: !hasFont,
        (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final exercises = _exercises(worst: worst);
          final lesson = LessonEntity(
            id: 'lesson',
            title: 'Audit',
            outcome: 'Can do it',
            orderIndex: 0,
            estimatedMinutes: 5,
            xpReward: 10,
            exercises: exercises,
          );
          final repository = _FakeRepo(lesson);
          final provider = LearningProvider(
            startLessonUseCase: StartLessonUseCase(repository: repository),
            submitAnswerUseCase: SubmitAnswerUseCase(repository: repository),
            completeLessonUseCase: CompleteLessonUseCase(
              repository: repository,
            ),
            getCourseRoadmapUseCase: GetCourseRoadmapUseCase(
              repository: repository,
            ),
            getLessonContentUseCase: GetLessonContentUseCase(
              repository: repository,
            ),
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: provider),
                ChangeNotifierProvider(create: (_) => TtsSettingsProvider()),
              ],
              child: MaterialApp(
                theme: ThemeData(fontFamily: 'Roboto'),
                home: const LearningSessionScreen(
                  lessonId: 'lesson',
                  courseId: 'course',
                ),
              ),
            ),
          );

          final problems = <String>[];
          var current = exercises.first.uiType ?? '?';
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final full = details.toString();
            final msg = details.exceptionAsString().split('\n').first;
            if (msg.contains('PushPermissionProvider')) return;
            final where = RegExp(r'([a-z_]+\.dart):(\d+)').firstMatch(
              full.substring(
                full.indexOf('relevant error-causing widget') < 0
                    ? 0
                    : full.indexOf('relevant error-causing widget'),
              ),
            );
            final line = '$current: $msg @ ${where?.group(0) ?? '?'}';
            if (!problems.contains(line)) problems.add(line);
          };
          addTearDown(() => FlutterError.onError = previous);
          for (var i = 0; i < exercises.length; i++) {
            await tester.pump(const Duration(milliseconds: 400));
            tester.takeException();
            if (i == exercises.length - 1) break;
            current = exercises[i + 1].uiType ?? '?';
            provider.nextExercise();
            await tester.pump();
          }
          FlutterError.onError = previous;
          expect(problems, isEmpty, reason: problems.join('\n'));
        },
      );
    }
  }
}

class _FakeRepo implements LearningRepository {
  final LessonEntity lesson;
  _FakeRepo(this.lesson);

  @override
  Future<Either<Failure, LessonAttempt>> startLesson(String lessonId) async =>
      Right(
        LessonAttempt(
          attemptId: 'attempt',
          lessonId: lessonId,
          startedAt: DateTime(2026),
          totalQuestions: lesson.exercises.length,
          livesRemaining: 3,
          hintsAvailable: 3,
        ),
      );

  @override
  Future<Either<Failure, LessonEntity>> getLessonContent(
    String lessonId,
  ) async => Right(lesson);

  @override
  Future<Either<Failure, AnswerResponse>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed = false,
    double? confidenceScore,
  }) => throw UnsupportedError('unused');

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(String attemptId) =>
      throw UnsupportedError('unused');

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String courseId) =>
      throw UnsupportedError('unused');
}
