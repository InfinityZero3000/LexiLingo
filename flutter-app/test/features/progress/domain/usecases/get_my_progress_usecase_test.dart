import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_my_progress_usecase.dart';

@GenerateMocks([ProgressRepository])
import 'get_my_progress_usecase_test.mocks.dart';

void main() {
  late GetMyProgressUseCase usecase;
  late MockProgressRepository mockRepository;

  setUp(() {
    mockRepository = MockProgressRepository();
    usecase = GetMyProgressUseCase(mockRepository);
  });

  final tSummary = UserProgressSummary(
    totalXp: 150,
    coursesEnrolled: 2,
    coursesCompleted: 1,
    lessonsCompleted: 15,
    currentStreak: 5,
    longestStreak: 10,
    achievementsUnlocked: 3,
  );

  final tCourseProgress = CourseProgressDetail(
    courseId: 'course-1',
    courseTitle: 'English A1',
    progressPercentage: 75.0,
    lessonsCompleted: 15,
    totalLessons: 20,
    totalXpEarned: 150,
    startedAt: DateTime.parse('2024-01-10T00:00:00Z'),
    lastActivityAt: DateTime.parse('2024-01-20T00:00:00Z'),
  );

  final tProgressStats = ProgressStatsEntity(
    summary: tSummary,
    courseProgress: [tCourseProgress],
  );

  test('should get progress stats from repository', () async {
    // arrange
    when(mockRepository.getMyProgress())
        .thenAnswer((_) async => Right(tProgressStats));

    // act
    final result = await usecase(NoParams());

    // assert
    expect(result, Right(tProgressStats));
    verify(mockRepository.getMyProgress());
    verifyNoMoreInteractions(mockRepository);
  });

  test('should return ServerFailure when repository call fails', () async {
    // arrange
    final failure = ServerFailure('Server error');
    when(mockRepository.getMyProgress())
        .thenAnswer((_) async => Left(failure));

    // act
    final result = await usecase(NoParams());

    // assert
    expect(result.isLeft(), true);
    result.fold(
      (l) => expect(l, isA<ServerFailure>()),
      (r) => fail('Should be Left'),
    );
    verify(mockRepository.getMyProgress());
    verifyNoMoreInteractions(mockRepository);
  });

  test('should return NetworkFailure when network error occurs', () async {
    // arrange
    final failure = NetworkFailure('No internet');
    when(mockRepository.getMyProgress())
        .thenAnswer((_) async => Left(failure));

    // act
    final result = await usecase(NoParams());

    // assert
    expect(result.isLeft(), true);
    result.fold(
      (l) => expect(l, isA<NetworkFailure>()),
      (r) => fail('Should be Left'),
    );
    verify(mockRepository.getMyProgress());
  });
}
