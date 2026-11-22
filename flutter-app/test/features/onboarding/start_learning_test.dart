import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/onboarding/data/datasources/start_learning_remote_datasource.dart';
import 'package:lexilingo_app/features/onboarding/data/repositories/start_learning_repository_impl.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';
import 'package:lexilingo_app/features/onboarding/domain/repositories/start_learning_repository.dart';
import 'package:lexilingo_app/features/onboarding/domain/usecases/start_learning_usecase.dart';
import 'package:lexilingo_app/features/onboarding/presentation/pages/start_learning_page.dart';
import 'package:lexilingo_app/features/onboarding/presentation/providers/start_learning_provider.dart';
import 'package:lexilingo_app/features/onboarding/presentation/start_learning_launcher.dart';
import 'package:provider/provider.dart';

const _target = StartLearningTarget(
  courseId: 'c1',
  courseTitle: 'Starter',
  firstLessonId: 'l1',
  alreadyEnrolled: false,
);

class _Repo implements StartLearningRepository {
  _Repo(this.results);

  final List<Either<Failure, StartLearningTarget>> results;
  final calls = <String?>[];

  @override
  Future<Either<Failure, StartLearningTarget>> startLearning({
    String? courseId,
  }) async {
    calls.add(courseId);
    return results.length > 1 ? results.removeAt(0) : results.first;
  }
}

StartLearningProvider _provider(_Repo repo) =>
    StartLearningProvider(startLearningUseCase: StartLearningUseCase(repo));

class _Api extends ApiClient {
  _Api(this.response) : super(baseUrl: 'http://test.local');

  final Map<String, dynamic> response;
  String? path;
  Object? body;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    this.path = path;
    this.body = body;
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => EasyLocalization.logger.enableLevels = []);

  group('data layer', () {
    test('posts to start-learning and reads the enveloped target', () async {
      final api = _Api({
        'data': {
          'course_id': 'c1',
          'course_title': 'Starter',
          'first_lesson_id': 'l1',
          'already_enrolled': true,
        },
      });
      final repo = StartLearningRepositoryImpl(
        remoteDataSource: StartLearningRemoteDataSourceImpl(apiClient: api),
      );

      final result = await repo.startLearning(courseId: 'c9');

      expect(api.path, '/users/me/start-learning');
      expect(api.body, {'course_id': 'c9'});
      final target = result.getOrElse(() => throw StateError('failed'));
      expect(target.firstLessonId, 'l1');
      expect(target.alreadyEnrolled, isTrue);
    });

    test('reads the target ApiClient hands back, which is already unwrapped', () async {
      // The real ApiClient strips {data, meta} before returning; a fake that
      // keeps the envelope hid this once and the first lesson never opened.
      final repo = StartLearningRepositoryImpl(
        remoteDataSource: StartLearningRemoteDataSourceImpl(
          apiClient: _Api({
            'course_id': 'c1',
            'course_title': 'Starter',
            'first_lesson_id': 'l1',
            'already_enrolled': false,
          }),
        ),
      );

      final result = await repo.startLearning(courseId: 'c1');

      final target = result.getOrElse(() => throw StateError('failed'));
      expect(target.firstLessonId, 'l1');
      expect(target.alreadyEnrolled, isFalse);
    });

    test('a response without a lesson is a failure, not a crash', () async {
      final repo = StartLearningRepositoryImpl(
        remoteDataSource: StartLearningRemoteDataSourceImpl(
          apiClient: _Api({
            'data': {'course_id': 'c1'},
          }),
        ),
      );

      expect((await repo.startLearning()).isLeft(), isTrue);
    });
  });

  group('provider', () {
    test('success keeps the target; failure keeps the message', () async {
      final repo = _Repo([
        const Left(ServerFailure('boom')),
        const Right(_target),
      ]);
      final provider = _provider(repo);

      expect(await provider.start(), isNull);
      expect(provider.status, StartLearningStatus.failed);
      expect(provider.errorMessage, 'boom');

      expect(await provider.start(courseId: 'c1'), _target);
      expect(provider.status, StartLearningStatus.ready);
      expect(repo.calls, [null, 'c1']);
    });
  });

  group('StartLearningPage', () {
    Future<void> pump(
      WidgetTester tester,
      _Repo repo, {
      required ValueChanged<StartLearningTarget> onStarted,
      VoidCallback? onSkip,
    }) => tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => _provider(repo),
          child: StartLearningPage(
            onStarted: onStarted,
            onSkip: onSkip ?? () {},
          ),
        ),
      ),
    );

    testWidgets('calls start-learning once and hands over the lesson', (
      tester,
    ) async {
      final repo = _Repo([const Right(_target)]);
      StartLearningTarget? started;

      await pump(tester, repo, onStarted: (t) => started = t);
      await tester.pump();

      expect(repo.calls, [null]);
      expect(started, _target);
    });

    testWidgets('a failure offers retry and a way home; retry recovers', (
      tester,
    ) async {
      final repo = _Repo([
        const Left(NetworkFailure('offline')),
        const Right(_target),
      ]);
      StartLearningTarget? started;
      var skipped = false;

      await pump(
        tester,
        repo,
        onStarted: (t) => started = t,
        onSkip: () => skipped = true,
      );
      await tester.pump();

      expect(started, isNull);
      expect(find.text('onboarding.startFailedTitle'), findsOneWidget);
      final home = find.text('onboarding.goHome');
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(home);
      expect(skipped, isTrue);

      await tester.tap(find.text('common.retry'));
      await tester.pump();

      expect(repo.calls.length, 2);
      expect(started, _target);
    });
  });

  testWidgets('the launcher replaces itself with the first lesson', (
    tester,
  ) async {
    final repo = _Repo([const Right(_target)]);
    late BuildContext origin;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            origin = context;
            return const Text('home');
          },
        ),
      ),
    );

    StartLearningLauncher.open(
      origin,
      courseId: 'c1',
      providerFactory: () => _provider(repo),
      sessionBuilder: (t) => Text('session:${t.firstLessonId}'),
    );
    await tester.pumpAndSettle();

    expect(repo.calls, ['c1']);
    expect(find.text('session:l1'), findsOneWidget);
    Navigator.of(origin).pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
