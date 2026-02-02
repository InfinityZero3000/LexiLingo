import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/data/datasources/progress_remote_datasource.dart';
import 'package:lexilingo_app/features/progress/data/models/progress_model.dart';
import 'package:lexilingo_app/features/progress/data/repositories/progress_repository_impl.dart';

@GenerateMocks([ProgressRemoteDataSource])
import 'progress_repository_impl_test.mocks.dart';

void main() {
  late ProgressRepositoryImpl repository;
  late MockProgressRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockProgressRemoteDataSource();
    repository = ProgressRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  group('getMyProgress', () {
    final tSummary = UserProgressSummaryModel(
      totalXp: 200,
      coursesEnrolled: 2,
      coursesCompleted: 1,
      lessonsCompleted: 20,
      currentStreak: 7,
      longestStreak: 15,
      achievementsUnlocked: 5,
    );

    final tProgressStats = ProgressStatsModel(
      summary: tSummary,
      courseProgress: [],
    );

    test('should return progress stats when call to remote data source is successful',
        () async {
      // arrange
      when(mockRemoteDataSource.getMyProgress())
          .thenAnswer((_) async => tProgressStats);

      // act
      final result = await repository.getMyProgress();

      // assert
      verify(mockRemoteDataSource.getMyProgress());
      expect(result, Right(tProgressStats));
    });

    test('should return ServerFailure when remote data source throws ServerException',
        () async {
      // arrange
      when(mockRemoteDataSource.getMyProgress())
          .thenThrow(ServerException('Server error'));

      // act
      final result = await repository.getMyProgress();

      // assert
      verify(mockRemoteDataSource.getMyProgress());
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('should return NetworkFailure when remote data source throws NetworkException',
        () async {
      // arrange
      when(mockRemoteDataSource.getMyProgress())
          .thenThrow(NetworkException('No internet'));

      // act
      final result = await repository.getMyProgress();

      // assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<NetworkFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('should return UnauthorizedFailure when remote data source throws UnauthorizedException',
        () async {
      // arrange
      when(mockRemoteDataSource.getMyProgress())
          .thenThrow(UnauthorizedException('Token expired'));

      // act
      final result = await repository.getMyProgress();

      // assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<UnauthorizedFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });
  });

  group('completeLesson', () {
    const tLessonId = 'lesson-123';
    const tScore = 85.0;

    final tCompletionResult = LessonCompletionResultModel(
      lessonId: tLessonId,
      isPassed: true,
      score: tScore,
      bestScore: tScore,
      xpEarned: 20,
      totalXp: 140,
      courseProgress: 50.0,
      message: 'Great job!',
    );

    test('should return completion result when call is successful', () async {
      // arrange
      when(mockRemoteDataSource.completeLesson(
        lessonId: anyNamed('lessonId'),
        score: anyNamed('score'),
      )).thenAnswer((_) async => tCompletionResult);

      // act
      final result = await repository.completeLesson(
        lessonId: tLessonId,
        score: tScore,
      );

      // assert
      verify(mockRemoteDataSource.completeLesson(
        lessonId: tLessonId,
        score: tScore,
      ));
      expect(result, Right(tCompletionResult));
    });

    test('should return ServerFailure when server error occurs', () async {
      // arrange
      when(mockRemoteDataSource.completeLesson(
        lessonId: anyNamed('lessonId'),
        score: anyNamed('score'),
      )).thenThrow(ServerException('Failed to complete lesson'));

      // act
      final result = await repository.completeLesson(
        lessonId: tLessonId,
        score: tScore,
      );

      // assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('should return UnauthorizedFailure when not enrolled', () async {
      // arrange
      when(mockRemoteDataSource.completeLesson(
        lessonId: anyNamed('lessonId'),
        score: anyNamed('score'),
      )).thenThrow(UnauthorizedException('Not enrolled in course'));

      // act
      final result = await repository.completeLesson(
        lessonId: tLessonId,
        score: tScore,
      );

      // assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<UnauthorizedFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });
  });

  group('getCourseProgress', () {
    const tCourseId = 'course-123';

    final tCourse = CourseProgressDetailModel(
      courseId: tCourseId,
      courseTitle: 'English A1',
      progressPercentage: 65.0,
      lessonsCompleted: 13,
      totalLessons: 20,
      totalXpEarned: 260,
      startedAt: DateTime.parse('2024-01-10T00:00:00Z'),
      lastActivityAt: DateTime.parse('2024-01-20T00:00:00Z'),
    );

    final tCourseProgress = CourseProgressWithUnitsModel(
      course: tCourse,
      unitsProgress: [],
    );

    test('should return course progress when call is successful', () async {
      // arrange
      when(mockRemoteDataSource.getCourseProgress(any))
          .thenAnswer((_) async => tCourseProgress);

      // act
      final result = await repository.getCourseProgress(tCourseId);

      // assert
      verify(mockRemoteDataSource.getCourseProgress(tCourseId));
      expect(result, Right(tCourseProgress));
    });

    test('should return ServerFailure when course not found', () async {
      // arrange
      when(mockRemoteDataSource.getCourseProgress(any))
          .thenThrow(ServerException('Course not found'));

      // act
      final result = await repository.getCourseProgress(tCourseId);

      // assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });
  });

  group('getTotalXp', () {
    const tTotalXp = 350;

    test('should return total XP when call is successful', () async {
      // arrange
      when(mockRemoteDataSource.getTotalXp())
          .thenAnswer((_) async => tTotalXp);

      // act
      final result = await repository.getTotalXp();

      // assert
      verify(mockRemoteDataSource.getTotalXp());
      expect(result, const Right(tTotalXp));
    });

    test('should return ServerFailure when error occurs', () async {
      // arrange
      when(mockRemoteDataSource.getTotalXp())
          .thenThrow(ServerException('Failed to fetch XP'));

      // act
      final result = await repository.getTotalXp();

      // assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left but got Right'),
      );
    });
  });
}
