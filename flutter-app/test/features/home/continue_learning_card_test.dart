import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/circle_icon.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/continue_learning_card.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

CourseEntity _course(String id, double? progress) => CourseEntity(
  id: id,
  title: 'Course $id',
  level: 'A1',
  language: 'en',
  tags: const [],
  totalXp: 100,
  estimatedDuration: 60,
  totalLessons: 10,
  isPublished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  userProgress: progress,
);

class _CourseRepositoryStub implements CourseRepository {
  _CourseRepositoryStub(this.enrolledCourses);

  final List<CourseEntity> enrolledCourses;

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  }) async => const Right(([], 1));

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  }) async => Right((enrolledCourses, 1));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpCard(
  WidgetTester tester,
  List<CourseEntity> enrolledCourses, {
  Duration rotationInterval = const Duration(seconds: 6),
  bool reduceMotion = false,
  double textScale = 1,
}) async {
  final repository = _CourseRepositoryStub(enrolledCourses);
  final provider = HomeProvider(
    getCoursesUseCase: GetCoursesUseCase(repository),
    getEnrolledCoursesUseCase: GetEnrolledCoursesUseCase(repository),
  );
  await provider.loadEnrolledCourses();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: ContinueLearningCard(rotationInterval: rotationInterval),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder shown(String text) => find.descendant(
  of: find.byType(AnimatedSwitcher),
  matching: find.text(text),
);

void main() {
  test('picks the first started unfinished course', () {
    final picked = ContinueLearningCard.pick([
      _course('done', 100),
      _course('new', 0),
      _course('mid', 42),
    ]);
    expect(picked?.id, 'mid');
  });

  test('does not offer continue learning for 0% or completed courses', () {
    final picked = ContinueLearningCard.pick([
      _course('new', 0),
      _course('a', 100),
      _course('b', 100),
    ]);
    expect(picked, isNull);
  });

  test('picks a null or 0% course as unstarted', () {
    expect(
      ContinueLearningCard.pickUnstarted([
        _course('done', 100),
        _course('null-progress', null),
        _course('zero-progress', 0),
      ])?.id,
      'null-progress',
    );
  });

  test('nothing to continue when not enrolled anywhere', () {
    expect(ContinueLearningCard.pick(const []), isNull);
  });

  testWidgets('0% course shows a start prompt instead of continue learning', (
    tester,
  ) async {
    await _pumpCard(tester, [_course('new', 0)]);

    expect(find.text('home.startLesson'), findsOneWidget);
    expect(find.text('Course new'), findsOneWidget);
    expect(find.text('home.continueLearningSection'), findsNothing);
  });

  testWidgets('started course rotates from continue learning to reminder', (
    tester,
  ) async {
    await _pumpCard(tester, [
      _course('mid', 42),
    ], rotationInterval: const Duration(seconds: 1));

    expect(shown('home.continueLearningSection'), findsOneWidget);
    expect(shown('42%'), findsOneWidget);
    expect(shown('home.completeLessonToday'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(shown('home.continueLearningSection'), findsNothing);
    expect(shown('home.keepGoing'), findsOneWidget);
    expect(shown('home.completeLessonToday'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion keeps the course card still', (tester) async {
    await _pumpCard(
      tester,
      [_course('mid', 42)],
      rotationInterval: const Duration(seconds: 1),
      reduceMotion: true,
    );

    expect(shown('home.continueLearningSection'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(shown('home.continueLearningSection'), findsOneWidget);
    expect(shown('home.keepGoing'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('200% text: both faces of the card fit on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpCard(
      tester,
      [_course('mid', 42)],
      rotationInterval: const Duration(seconds: 1),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CircleIcon draws the glyph inside a disc', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CircleIcon(icon: PhosphorIconsBold.bell, color: Colors.teal),
        ),
      ),
    );
    expect(find.byIcon(PhosphorIconsBold.bell), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container).first);
    expect((box.decoration as BoxDecoration).shape, BoxShape.circle);
  });
}
