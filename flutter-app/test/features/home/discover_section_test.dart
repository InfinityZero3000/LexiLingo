import 'dart:async';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/discover_data.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/discover_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:provider/provider.dart';

const _book = Book(
  id: 'b1',
  title: 'The Little Prince, in plain English for learners of every age',
  author: 'Antoine de Saint-Exupery',
  cefrLevel: 'B1',
  chapterCount: 27,
);
const _podcast = Podcast(
  id: 'p1',
  title: 'The English We Speak, a rather long programme title',
  author: 'BBC Learning English',
  feedUrl: 'https://example.test/feed',
  cefrLevel: 'B1',
);

CourseEntity _course(String id, {bool? enrolled}) => CourseEntity(
  id: id,
  title: 'Everyday English for work and travel with a long course title',
  language: 'en',
  level: 'intermediate',
  tags: const [],
  totalXp: 0,
  estimatedDuration: 0,
  totalLessons: 12,
  isPublished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isEnrolled: enrolled,
);

class _Courses implements CourseRepository {
  _Courses(this.courses);
  final List<CourseEntity> courses;

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  }) async => Right((courses, 1));

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  }) async => const Right(([], 1));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Books implements BookRepository {
  _Books(this.byLevel, {this.fail = false});
  final Map<String, List<Book>> byLevel;
  final bool fail;
  final asked = <String?>[];

  @override
  Future<List<Book>> getRecommendedBooks({String? cefrLevel}) async {
    asked.add(cefrLevel);
    if (fail) throw Exception('offline');
    return byLevel[cefrLevel] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Podcasts implements PodcastRepository {
  _Podcasts(this.podcasts, {this.fail = false});
  final List<Podcast> podcasts;
  final bool fail;

  @override
  Future<List<PodcastCategory>> getCuratedPodcasts() async {
    if (fail) throw Exception('offline');
    return [
      PodcastCategory(id: 'c', label: 'c', podcasts: podcasts),
      PodcastCategory(id: 'd', label: 'd', podcasts: podcasts),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBookProvider extends BookProvider {
  final opened = <Book>[];

  @override
  Future<void> openBook(Book book) async => opened.add(book);
}

class _ProficiencyAt implements ProficiencyDataSource {
  _ProficiencyAt(this.level);
  final String level;

  @override
  Future<ProficiencyProfile> getProfile() async =>
      ProficiencyProfile.fromJson({'assessed_level': level});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeBookProvider> _pump(
  WidgetTester tester, {
  required Future<DiscoverFeed> Function(String level) loader,
  List<CourseEntity> courses = const [],
  ProficiencyDataSource? proficiency,
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Courses(courses);
  final home = HomeProvider(
    getCoursesUseCase: GetCoursesUseCase(repo),
    getEnrolledCoursesUseCase: GetEnrolledCoursesUseCase(repo),
  );
  await home.loadFeaturedCourses();
  final books = _FakeBookProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeProvider>.value(value: home),
        ChangeNotifierProvider<ProficiencyProvider>(
          create: (_) => ProficiencyProvider(dataSource: proficiency),
        ),
        ChangeNotifierProvider<BookProvider>.value(value: books),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1400),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(child: DiscoverSection(loader: loader)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return books;
}

Future<DiscoverFeed> Function(String) _feed({Book? book, Podcast? podcast}) =>
    (_) async => DiscoverFeed(book: book, podcast: podcast);

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

  group('pickWeekly', () {
    final items = ['a', 'b', 'c'];

    test('holds for a whole week and moves on in the next', () {
      final monday = DateTime.utc(2026, 11, 16);
      final startOfWeek = DateTime.utc(1970).add(
        Duration(days: (monday.difference(DateTime.utc(1970)).inDays ~/ 7) * 7),
      );
      final inWeek = [
        for (var d = 0; d < 7; d++) startOfWeek.add(Duration(days: d)),
      ].map((day) => pickWeekly(items, day)).toSet();
      expect(inWeek, hasLength(1));
      expect(
        pickWeekly(items, startOfWeek.add(const Duration(days: 7))),
        isNot(inWeek.single),
      );
    });

    test('is null for an empty list and ignores the time zone offset', () {
      expect(pickWeekly(<String>[], DateTime(2026, 11, 17)), isNull);
      final instant = DateTime.utc(2026, 11, 17, 3);
      expect(pickWeekly(items, instant), pickWeekly(items, instant.toLocal()));
    });
  });

  group('levels', () {
    test('tries the level, then below, then above', () {
      expect(levelsToTry('b1'), ['B1', 'A2', 'B2']);
      expect(levelsToTry('A1'), ['A1', 'A2']);
      expect(levelsToTry('C2'), ['C2', 'C1']);
      expect(levelsToTry('??'), ['??']);
    });

    test('neighbours count only when nothing matches exactly', () {
      String level(String l) => l;
      expect(atLevelOrNeighbour(['A2', 'B1', 'B2'], 'B1', level), ['B1']);
      expect(atLevelOrNeighbour(['A2', 'B2', 'C1'], 'B1', level), ['A2', 'B2']);
      expect(atLevelOrNeighbour(['C1', 'C2'], 'A1', level), isEmpty);
    });
  });

  group('loadDiscoverFeed', () {
    test('falls back one level down before one up', () async {
      final books = _Books({
        'A2': [_book],
        'B2': [const Book(id: 'up', title: 'Up')],
      });
      final feed = await loadDiscoverFeed(
        'B1',
        books: books,
        podcasts: _Podcasts(const []),
      );
      expect(feed.book?.id, 'b1');
      expect(books.asked, ['B1', 'A2']);
      expect(feed.podcast, isNull);
    });

    test('a failing source only hides its own block', () async {
      final feed = await loadDiscoverFeed(
        'B1',
        books: _Books(const {}, fail: true),
        podcasts: _Podcasts([_podcast]),
      );
      expect(feed.book, isNull);
      expect(feed.podcast?.id, 'p1');

      final other = await loadDiscoverFeed(
        'B1',
        books: _Books({
          'B1': [_book],
        }),
        podcasts: _Podcasts(const [], fail: true),
      );
      expect(other.book?.id, 'b1');
      expect(other.podcast, isNull);
    });
  });

  testWidgets('picks for the learner level without a visit to Profile', (
    tester,
  ) async {
    final asked = <String>[];
    await _pump(
      tester,
      proficiency: _ProficiencyAt('B2'),
      loader: (level) async {
        asked.add(level);
        return const DiscoverFeed();
      },
    );

    expect(asked.last, 'B2');
  });

  testWidgets('book, podcast and course share one card', (tester) async {
    await _pump(
      tester,
      loader: _feed(book: _book, podcast: _podcast),
      courses: [_course('done', enrolled: true), _course('c1')],
    );

    expect(find.text('home.discover'), findsOneWidget);
    expect(find.text('home.discoverSubtitle'), findsOneWidget);
    expect(find.text('home.bookOfWeek'), findsOneWidget);
    expect(find.text('home.readNow'), findsOneWidget);
    expect(find.text(_book.title), findsWidgets);
    expect(find.text(_podcast.title), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(4));
    expect(find.byType(SkeletonLoader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the book is shown when nothing else is available', (
    tester,
  ) async {
    await _pump(tester, loader: _feed(book: _book));

    expect(find.text('home.bookOfWeek'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('a course that is already enrolled is not offered', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: _feed(),
      courses: [_course('c', enrolled: true)],
    );

    expect(find.text('home.discover'), findsNothing);
  });

  testWidgets('nothing at all renders nothing, heading included', (
    tester,
  ) async {
    await _pump(tester, loader: _feed());

    expect(find.text('home.discover'), findsNothing);
    expect(find.byType(DiscoverSection), findsOneWidget);
    expect(tester.getSize(find.byType(DiscoverSection)).height, 0);
  });

  testWidgets('a loader that throws is swallowed and hides the section', (
    tester,
  ) async {
    await _pump(tester, loader: (_) => Future.error(Exception('boom')));

    expect(find.text('home.discover'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a skeleton inside the card while loading', (tester) async {
    final done = Completer<DiscoverFeed>();
    await _pump(tester, loader: (_) => done.future);

    expect(find.text('home.discover'), findsOneWidget);
    expect(find.byType(SkeletonLoader), findsWidgets);

    done.complete(const DiscoverFeed(book: _book));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsNothing);
    expect(find.text('home.bookOfWeek'), findsOneWidget);
  });

  testWidgets('tapping the book opens it', (tester) async {
    final books = await _pump(tester, loader: _feed(book: _book));

    await tester.tap(find.text('home.readNow'));
    await tester.pump();
    await tester.pump();

    expect(books.opened.map((b) => b.id), ['b1']);
  });

  for (final width in [360.0, 768.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'no overflow at 1.5x text, ${width.toInt()}px, ${brightness.name}',
        skip: !hasFont,
        (tester) async {
          await _pump(
            tester,
            loader: _feed(book: _book, podcast: _podcast),
            courses: [_course('c1')],
            width: width,
            textScale: 1.5,
            brightness: brightness,
          );

          expect(find.byType(FilledButton), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
