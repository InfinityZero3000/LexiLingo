import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/discover_rail.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/recommendations_section.dart';
import 'package:provider/provider.dart';

RecommendationItem _rec(String type, String id, {String? title}) =>
    RecommendationItem(
      itemId: id,
      itemType: type,
      title:
          title ??
          'A rather long $type title that has to wrap or be cut off somewhere',
      reason: 'You study a lot about technology and science topics',
      level: 'B1',
      payload: type == 'vocab'
          ? const {'pronunciation': '/ˈprəʊses/'}
          : const {},
    );

class _Repo implements CourseRepository {
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
  }) async => const Right(([], 1));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  List<RecommendationItem> items, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => HomeProvider(
        getCoursesUseCase: GetCoursesUseCase(repo),
        getEnrolledCoursesUseCase: GetEnrolledCoursesUseCase(repo),
      ),
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: DiscoverRail(loader: () async => items),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  final fontDir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/usr/local/share/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final hasFont = File('$fontDir/Roboto-Regular.ttf').existsSync();

  setUpAll(() async {
    // Ahem (the default test font) is a full em wide and reports overflows
    // no device has.
    if (!hasFont) return;
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Bold']) {
      final bytes = File('$fontDir/Roboto-$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  test('groups by what the learner does with the item, lessons first', () {
    final groups = groupRecommendations([
      _rec('vocab', 'v1'),
      _rec('course', 'c1'),
      _rec('video', 'y1'),
      _rec('lesson', 'l1'),
      _rec('vocab', 'v2'),
      _rec('mystery', 'x'),
    ]);

    expect(groups.study.map((i) => i.itemId), ['l1', 'c1']);
    expect(groups.words.map((i) => i.itemId), ['v1', 'v2']);
    expect(groups.media.map((i) => i.itemId), ['y1']);
  });

  testWidgets('each kind gets its own titled rail and words are compact', (
    tester,
  ) async {
    await _pump(tester, [
      _rec('lesson', 'l1'),
      _rec('vocab', 'v1', title: 'process'),
      _rec('video', 'y1'),
    ]);

    expect(find.text('home.discoverStudy'), findsOneWidget);
    expect(find.text('home.discoverWords'), findsOneWidget);
    expect(find.text('home.discoverMedia'), findsOneWidget);
    expect(find.byType(VocabSuggestionTile), findsOneWidget);
    // The word no longer sits in a course-sized card next to lessons.
    expect(find.byType(RecommendationCard), findsNWidgets(2));
    expect(
      tester.getSize(find.byType(VocabSuggestionTile)).height,
      lessThanOrEqualTo(DiscoverRail.wordsRailHeight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a kind with nothing to show has no heading', (tester) async {
    await _pump(tester, [_rec('lesson', 'l1')]);

    expect(find.text('home.discoverStudy'), findsOneWidget);
    expect(find.text('home.discoverWords'), findsNothing);
    expect(find.text('home.discoverMedia'), findsNothing);
  });

  testWidgets('no overflow on a 320px phone with large text', skip: !hasFont, (
    tester,
  ) async {
    await _pump(
      tester,
      [_rec('lesson', 'l1'), _rec('vocab', 'v1'), _rec('video', 'y1')],
      width: 320,
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
  });
}
