import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/state/reset_epoch.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_in_course_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_categories_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_course_detail_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_by_category_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/games/data/repositories/games_repository.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_course_roadmap_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_lesson_content_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/start_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/submit_answer_usecase.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/youtube/data/repositories/youtube_repository.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';

class _Subject with ResetEpoch {}

class _Games extends Fake implements GamesRepository {
  final gate = Completer<XPProfile>();
  @override
  Future<XPProfile> getXPProfile() => gate.future;
}

class _Notifications extends Fake implements NotificationRepository {
  final gate = Completer<List<NotificationEntity>>();
  @override
  Stream<List<NotificationEntity>> get notificationsStream =>
      const Stream.empty();
  @override
  Stream<int> get unreadCountStream => const Stream.empty();
  @override
  Future<List<NotificationGroup>> getGroupedNotifications() async => [];
  @override
  Future<List<NotificationEntity>> getNotifications() => gate.future;
  @override
  Future<int> getUnreadCount() async => 5;
}

class _Books extends Fake implements BookRepository {
  final gate = Completer<List<Book>>();
  @override
  Future<List<Book>> getRecommendedBooks({String? cefrLevel}) => gate.future;
}

class _Social extends Fake implements SocialRepository {
  final gate =
      Completer<({List<ActivityFeedItemEntity> activities, bool hasMore})>();
  @override
  Future<({List<ActivityFeedItemEntity> activities, bool hasMore})>
  getActivityFeed({int limit = 20, int offset = 0}) => gate.future;
}

class _Podcasts extends Fake implements PodcastRepository {
  final gate = Completer<List<PodcastCategory>>();
  @override
  Future<List<PodcastCategory>> getCuratedPodcasts() => gate.future;
}

class _Videos extends Fake implements YouTubeRepository {
  final gate = Completer<YouTubeSearchResult>();
  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    int maxResults = 10,
    String? channelId,
    String? pageToken,
  }) => gate.future;
}

class _Enrolled extends Fake implements GetEnrolledCoursesUseCase {
  final gate = Completer<Either<Failure, (List<CourseEntity>, int)>>();
  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> call({
    int page = 1,
    int pageSize = 20,
  }) => gate.future;
}

class _Roadmap extends Fake implements GetCourseRoadmapUseCase {
  final gate = Completer<Either<Failure, CourseRoadmap>>();
  @override
  Future<Either<Failure, CourseRoadmap>> call(GetCourseRoadmapParams params) =>
      gate.future;
}

class _NoCourses extends Fake implements GetCoursesUseCase {}

class _NoDetail extends Fake implements GetCourseDetailUseCase {}

class _NoEnroll extends Fake implements EnrollInCourseUseCase {}

class _NoCategories extends Fake implements GetCategoriesUseCase {}

class _NoByCategory extends Fake implements GetCoursesByCategoryUseCase {}

class _NoStart extends Fake implements StartLessonUseCase {}

class _NoSubmit extends Fake implements SubmitAnswerUseCase {}

class _NoComplete extends Fake implements CompleteLessonUseCase {}

class _NoContent extends Fake implements GetLessonContentUseCase {}

void main() {
  test('ResetEpoch: a captured epoch is stale only after a bump', () {
    final subject = _Subject();
    final before = subject.resetEpoch;
    expect(subject.isStale(before), isFalse);

    subject.bumpResetEpoch();

    expect(subject.isStale(before), isTrue);
    expect(subject.isStale(subject.resetEpoch), isFalse);
  });

  test('games: an XP profile that arrives after reset is dropped', () async {
    final repo = _Games();
    final provider = GamesProvider(repository: repo);
    final loading = provider.loadXPProfile();
    provider.reset();
    repo.gate.complete(
      const XPProfile(userId: 'a', totalXp: 900, numericLevel: 9),
    );
    await loading;

    expect(provider.xpProfile, isNull);
    expect(provider.totalXp, 0);
    expect(provider.isLoading, isFalse);
  });

  test('notifications: a list that arrives after reset is dropped', () async {
    final repo = _Notifications();
    final provider = NotificationProvider(
      repository: repo,
      listenToForegroundFcm: false,
    );
    final loading = provider.loadNotifications();
    provider.reset();
    repo.gate.complete([
      NotificationEntity(
        id: 'n',
        type: NotificationType.general,
        title: 'A only',
        body: '',
        timestamp: DateTime(2026, 1, 1),
        isRead: false,
      ),
    ]);
    await loading;

    expect(provider.notifications, isEmpty);
    expect(provider.unreadCount, 0);
    provider.dispose();
  });

  test(
    'books: recommended books that arrive after reset are dropped',
    () async {
      final repo = _Books();
      final provider = BookProvider(repository: repo);
      final loading = provider.loadRecommendedBooks();
      provider.reset();
      repo.gate.complete([
        Book(
          id: 'b',
          title: 'T',
          author: 'A',
          coverUrl: '',
          cefrLevel: 'B1',
          topic: 'x',
          chapterCount: 1,
          wordCount: 1,
        ),
      ]);
      await loading;

      expect(provider.recommendedBooks, isEmpty);
      provider.dispose();
    },
  );

  test(
    'social: a feed error after reset is not shown to the next learner',
    () async {
      final repo = _Social();
      final provider = SocialProvider(repository: repo);
      final loading = provider.loadActivityFeed();
      provider.reset();
      repo.gate.completeError(Exception('A only'));
      await loading;

      expect(provider.feedError, isNull);
      expect(provider.isLoadingFeed, isFalse);
    },
  );

  test('podcast: a curated-shelf error after reset leaves no error', () async {
    final repo = _Podcasts();
    final provider = PodcastProvider(repository: repo);
    final loading = provider.loadCuratedPodcasts();
    provider.reset();
    repo.gate.completeError(Exception('A only'));
    await loading;

    expect(provider.error, isNull);
    expect(provider.isLoading, isFalse);
    provider.dispose();
  });

  test(
    'youtube: recommendations that arrive after reset are dropped',
    () async {
      final repo = _Videos();
      final provider = YouTubeProvider(repository: repo);
      final loading = provider.loadRecommendations();
      provider.reset();
      repo.gate.complete(
        YouTubeSearchResult(
          totalResults: 1,
          videos: [
            YouTubeVideo(
              videoId: 'v',
              title: 'A only',
              description: '',
              channelTitle: 'c',
              channelId: 'c',
              publishedAt: '',
              thumbnailUrl: '',
            ),
          ],
        ),
      );
      await loading;

      expect(provider.recommendedVideos, isEmpty);
      provider.dispose();
    },
  );

  test('course: an enrolled-list error after reset leaves no error', () async {
    final enrolled = _Enrolled();
    final provider = CourseProvider(
      getCoursesUseCase: _NoCourses(),
      getCourseDetailUseCase: _NoDetail(),
      enrollInCourseUseCase: _NoEnroll(),
      getCategoriesUseCase: _NoCategories(),
      getCoursesByCategoryUseCase: _NoByCategory(),
      getEnrolledCoursesUseCase: enrolled,
    );
    final loading = provider.loadEnrolledCourses();
    provider.reset();
    enrolled.gate.complete(const Left(ServerFailure('A only')));
    await loading;

    expect(provider.enrolledError, isNull);
    expect(provider.isLoadingEnrolled, isFalse);
  });

  test('learning: a roadmap error after reset leaves no error', () async {
    final roadmap = _Roadmap();
    final provider = LearningProvider(
      startLessonUseCase: _NoStart(),
      submitAnswerUseCase: _NoSubmit(),
      completeLessonUseCase: _NoComplete(),
      getCourseRoadmapUseCase: roadmap,
      getLessonContentUseCase: _NoContent(),
    );
    final loading = provider.loadRoadmap('course-a');
    provider.reset();
    roadmap.gate.complete(const Left(ServerFailure('A only')));
    await loading;

    expect(provider.roadmapError, isNull);
    expect(provider.isLoadingRoadmap, isFalse);
  });
}
