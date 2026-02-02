import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/complete_lesson_usecase.dart';

@GenerateMocks([ProgressRepository])
import 'complete_lesson_usecase_test.mocks.dart';

void main() {
  late CompleteLessonUseCase usecase;
  late MockProgressRepository mockRepository;

  setUp(() {
    mockRepository = MockProgressRepository();
    usecase = CompleteLessonUseCase(mockRepository);
  });

  const tLessonId = 'lesson-123';
  const tScore = 85.0;
  const tParams = CompleteLessonParams(
    lessonId: tLessonId,
    score: tScore,
  );

  final tCompletionResult = LessonCompletionResult(
    lessonId: tLessonId,
    isPassed: true,
    score: tScore,
    bestScore: tScore,
    xpEarned: 20,
    totalXp: 120,
    courseProgress: 45.0,
    message: 'Congratulations! You passed the lesson.',
  );

  test('should complete lesson with passing score', () async {
    // arrange
    when(mockRepository.completeLesson(
      lessonId: anyNamed('lessonId'),
      score: anyNamed('score'),
    )).thenAnswer((_) async => Right(tCompletionResult));

    // act
    final result = await usecase(tParams);

    // assert
    expect(result, Right(tCompletionResult));
    verify(mockRepository.completeLesson(
      lessonId: tLessonId,
      score: tScore,
    ));
    verifyNoMoreInteractions(mockRepository);
  });

  test('should complete lesson with failing score', () async {
    // arrange
    const failingScore = 65.0;
    const failingParams = CompleteLessonParams(
      lessonId: tLessonId,
      score: failingScore,
    );
    
    final failedResult = LessonCompletionResult(
      lessonId: tLessonId,
      isPassed: false,
      score: failingScore,
      bestScore: failingScore,
      xpEarned: 0,
      totalXp: 100,
      courseProgress: 40.0,
      message: 'Keep practicing! Score must be 80% or higher to pass.',
    );

    when(mockRepository.completeLesson(
      lessonId: anyNamed('lessonId'),
      score: anyNamed('score'),
    )).thenAnswer((_) async => Right(failedResult));

    // act
    final result = await usecase(failingParams);

    // assert
    expect(result, Right(failedResult));
    final completionResult = result.getOrElse(() => throw Exception());
    expect(completionResult.isPassed, false);
    expect(completionResult.xpEarned, 0);
  });

  test('should return ServerFailure when repository call fails', () async {
    // arrange
    final failure = ServerFailure('Server error');
    when(mockRepository.completeLesson(
      lessonId: anyNamed('lessonId'),
      score: anyNamed('score'),
    )).thenAnswer((_) async => Left(failure));

    // act
    final result = await usecase(tParams);

    // assert
    expect(result.isLeft(), true);
    result.fold(
      (l) => expect(l, isA<ServerFailure>()),
      (r) => fail('Should be Left'),
    );
    verify(mockRepository.completeLesson(
      lessonId: tLessonId,
      score: tScore,
    ));
  });

  test('should return UnauthorizedFailure when not enrolled', () async {
    // arrange
    final failure = UnauthorizedFailure('Not enrolled in course');
    when(mockRepository.completeLesson(
      lessonId: anyNamed('lessonId'),
      score: anyNamed('score'),
    )).thenAnswer((_) async => Left(failure));

    // act
    final result = await usecase(tParams);

    // assert
    expect(result.isLeft(), true);
    result.fold(
      (l) => expect(l, isA<UnauthorizedFailure>()),
      (r) => fail('Should be Left'),
    );
  });

  group('CompleteLessonParams', () {
    test('should have correct props', () {
      const params1 = CompleteLessonParams(
        lessonId: 'lesson-1',
        score: 90.0,
      );
      const params2 = CompleteLessonParams(
        lessonId: 'lesson-1',
        score: 90.0,
      );
      const params3 = CompleteLessonParams(
        lessonId: 'lesson-2',
        score: 90.0,
      );

      expect(params1, equals(params2));
      expect(params1, isNot(equals(params3)));
    });
  });
}
