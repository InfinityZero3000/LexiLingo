import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/categories/data/categories_repository.dart';
import 'package:lexilingo_app/features/admin/features/categories/presentation/categories_screen.dart';
import 'package:lexilingo_app/features/admin/features/content_lab/data/content_lab_repository.dart';
import 'package:lexilingo_app/features/admin/features/content_lab/presentation/content_lab_screen.dart';
import 'package:lexilingo_app/features/admin/features/curriculum/data/curriculum_repository.dart';
import 'package:lexilingo_app/features/admin/features/curriculum/presentation/curriculum_screen.dart';
import 'package:lexilingo_app/features/admin/features/ielts/data/ielts_repository.dart';
import 'package:lexilingo_app/features/admin/features/ielts/presentation/ielts_screen.dart';
import 'package:lexilingo_app/features/admin/features/topics/data/topics_repository.dart';
import 'package:lexilingo_app/features/admin/features/topics/presentation/topics_screen.dart';
import 'package:lexilingo_app/features/admin/features/vocabulary/data/vocabulary_repository.dart';
import 'package:lexilingo_app/features/admin/features/vocabulary/presentation/vocabulary_screen.dart';
import 'package:provider/provider.dart';

class _Vocab implements VocabularyRepository {
  _Vocab(this.result);
  final Future<PageResult<VocabularyWord>> Function() result;
  @override
  Future<PageResult<VocabularyWord>> list(PageRequest request) => result();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Courses implements CurriculumRepository {
  _Courses(this.result);
  final Future<PageResult<Course>> Function(Map<String, Object?>) result;
  final filters = <Map<String, Object?>>[];
  @override
  Future<PageResult<Course>> listCourses(
    PageRequest request,
    Map<String, Object?> f,
  ) {
    filters.add(Map.of(f));
    return result(f);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Categories implements CategoriesRepository {
  _Categories(this.result);
  final Future<PageResult<CourseCategory>> Function() result;
  @override
  Future<PageResult<CourseCategory>> list() => result();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Topics implements TopicsRepository {
  @override
  Future<PageResult<TopicItem>> list() async => const PageResult(
    items: [
      TopicItem(
        storyId: 's',
        titleEn: 'Airport',
        titleVi: 'Sân bay',
        difficulty: 'A2',
        category: 'travel',
        minutes: 10,
      ),
    ],
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ielts implements IeltsRepository {
  @override
  Future<PageResult<IeltsTest>> listTests(PageRequest request) async =>
      const PageResult(
        items: [
          IeltsTest(
            id: 't',
            title: 'Mock 1',
            testType: 'academic',
            skillScope: 'full',
            questionCount: 40,
          ),
        ],
      );
  @override
  Future<PageResult<IeltsAttempt>> listAttempts({String? testId}) async =>
      const PageResult(items: []);
  @override
  Future<IeltsValidation> validate(String testId) async =>
      const IeltsValidation(
        publishable: false,
        problems: ['Test has no sections'],
        counts: {'reading': 0},
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lab implements ContentLabRepository {
  @override
  Future<PageResult<QuestionItem>> listQuestions(PageRequest request) async =>
      const PageResult(
        items: [
          QuestionItem(
            id: 'q',
            prompt: 'Pick the verb',
            questionType: 'mcq',
            difficultyLevel: 'A1',
            options: [],
            tags: [],
            isActive: true,
          ),
        ],
      );
  @override
  Future<PageResult<TestExam>> listTestExams(PageRequest request) async =>
      const PageResult(items: []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  response: Response(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: code,
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<String> slugs = const [],
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final perms = AdminPermissions()
      ..apply({'all': false, 'permissions': slugs});
    await tester.pumpWidget(
      ChangeNotifierProvider<AdminPermissions>.value(
        value: perms,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, __) => screen)],
          ),
        ),
      ),
    );
  }

  group('vocabulary', () {
    testWidgets('loading, then the words', (tester) async {
      await pump(
        tester,
        VocabularyScreen(
          repository: _Vocab(
            () async => const PageResult(
              items: [
                VocabularyWord(
                  id: '1',
                  word: 'cat',
                  definition: 'an animal',
                  translation: 'mèo',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('cat'), findsOneWidget);
      expect(find.text('an animal · mèo'), findsOneWidget);
    });

    testWidgets('an empty list says so', (tester) async {
      await pump(
        tester,
        VocabularyScreen(
          repository: _Vocab(() async => const PageResult(items: [])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('admin.vocabulary.empty'), findsOneWidget);
    });

    testWidgets('403 is the no-access state, not an error', (tester) async {
      await pump(
        tester,
        VocabularyScreen(repository: _Vocab(() async => throw _status(403))),
      );
      await tester.pumpAndSettle();
      expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
    });

    testWidgets('a server error offers a retry that reloads', (tester) async {
      var calls = 0;
      await pump(
        tester,
        VocabularyScreen(
          repository: _Vocab(() async {
            calls++;
            if (calls == 1) throw _status(500);
            return const PageResult(
              items: [VocabularyWord(id: '1', word: 'ok', definition: 'd')],
            );
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ok'), findsNothing);
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();
      expect(find.text('ok'), findsOneWidget);
    });

    testWidgets('create needs content:create', (tester) async {
      final repo = _Vocab(() async => const PageResult(items: []));
      await pump(tester, VocabularyScreen(repository: repo));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      await pump(
        tester,
        VocabularyScreen(repository: repo),
        slugs: ['content:create'],
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('courses', () {
    Course course(String title, {bool published = false}) =>
        Course(id: title, title: title, level: 'B1', isPublished: published);

    testWidgets('lists courses and filters by level on the server', (
      tester,
    ) async {
      final repo = _Courses(
        (f) async => PageResult(items: [course('Intro')], total: 1),
      );
      await pump(tester, CurriculumScreen(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('Intro'), findsOneWidget);
      expect(repo.filters.last, isEmpty);

      await tester.tap(find.widgetWithText(ChoiceChip, 'B1'));
      await tester.pumpAndSettle();
      expect(repo.filters.last, {'level': 'B1'});
    });

    testWidgets('a course row only offers its menu to who may update', (
      tester,
    ) async {
      final repo = _Courses((_) async => PageResult(items: [course('Intro')]));
      await pump(tester, CurriculumScreen(repository: repo));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsNothing);

      await pump(
        tester,
        CurriculumScreen(repository: repo),
        slugs: ['courses:update'],
      );
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('never offers a delete action', (tester) async {
      final repo = _Courses((_) async => PageResult(items: [course('Intro')]));
      await pump(
        tester,
        CurriculumScreen(repository: repo),
        slugs: ['courses:manage'],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.textContaining('elete'), findsNothing);
      expect(find.text('common.delete'), findsNothing);
    });
  });

  testWidgets('categories: 503 reads as a switched-off feature', (
    tester,
  ) async {
    await pump(
      tester,
      CategoriesScreen(repository: _Categories(() async => throw _status(503))),
    );
    await tester.pumpAndSettle();
    expect(find.text('admin.access.featureOffTitle'), findsOneWidget);
  });

  testWidgets('topics: lists the proxied topics, create is gated', (
    tester,
  ) async {
    await pump(tester, TopicsScreen(repository: _Topics()));
    await tester.pumpAndSettle();
    expect(find.text('Airport'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('ielts: validating a paper shows what blocks it', (tester) async {
    await pump(
      tester,
      IeltsScreen(repository: _Ielts()),
      slugs: ['ielts:create'],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mock 1'));
    await tester.pumpAndSettle();
    expect(find.text('admin.ielts.blocked'), findsOneWidget);
    expect(find.text('• Test has no sections'), findsOneWidget);
  });

  testWidgets('content lab: questions tab, then the exams tab', (tester) async {
    await pump(tester, ContentLabScreen(repository: _Lab()));
    await tester.pumpAndSettle();
    expect(find.text('Pick the verb'), findsOneWidget);

    await tester.tap(find.text('admin.contentLab.exams'));
    await tester.pumpAndSettle();
    expect(find.text('admin.contentLab.noExams'), findsOneWidget);
  });
}
