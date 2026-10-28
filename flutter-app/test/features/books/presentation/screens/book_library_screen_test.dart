import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_library_screen.dart';
import 'package:lexilingo_app/features/books/presentation/widgets/book_card.dart';
import 'package:lexilingo_app/features/books/presentation/widgets/book_hero.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the shipped en.json so a missing key shows up here, not on a device.
class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

Book _book(
  String id, {
  String level = 'A1',
  String cover = 'https://example.invalid/c.jpg',
  String topic = 'Fiction',
}) => Book(
  id: id,
  title: 'Book $id',
  author: 'Author $id',
  coverUrl: cover,
  cefrLevel: level,
  topic: topic,
);

class _FakeRepo extends BookRepository {
  _FakeRepo({
    this.books = const [],
    this.saved = const [],
    this.reading = const [],
    this.search = const [],
    this.fail = false,
    this.hang,
  });

  final List<Book> books;
  final List<Book> saved;
  final List<ReadingEntry> reading;
  final List<Book> search;
  final bool fail;
  final Completer<List<Book>>? hang;
  int loads = 0;

  @override
  Future<List<Book>> getRecommendedBooks({String? cefrLevel}) async {
    loads++;
    if (hang != null) return hang!.future;
    if (fail) throw Exception('offline');
    return books;
  }

  @override
  Future<List<Book>> getSavedBooks() async => saved;

  @override
  Future<List<ReadingEntry>> getContinueReading({int limit = 5}) async =>
      reading;

  @override
  Future<List<Book>> searchBooks({
    required String query,
    String? cefrLevel,
    int page = 1,
  }) async => search;

  @override
  Future<List<Book>> browseByLevel({
    required String level,
    int page = 1,
    String? topic,
  }) async => const [];

  @override
  Future<UserBook?> getProgress(String bookId) async => null;

  @override
  Future<List<Bookmark>> getBookmarks(String bookId) async => const [];

  @override
  Future<String?> getDownloadedPath(String bookId) async => null;
}

ReadingEntry _reading(String id, {double progress = 0.42}) => ReadingEntry(
  book: _book(id),
  progress: UserBook(
    bookId: id,
    currentPage: 42,
    totalPages: 100,
    readingProgress: progress,
    lastReadAt: DateTime(2026, 10, 23),
  ),
);

final _library = [
  _book('a1', level: 'A1'),
  _book('a2', level: 'A1', topic: 'Fantasy'),
  _book('b1', level: 'B1'),
  _book('c2', level: 'C2', cover: ''),
];

late BookProvider _provider;

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  ThemeData? theme,
  Size size = const Size(375, 812),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _provider = BookProvider(repository: repo);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      assetLoader: const _DiskAssetLoader(),
      child: Builder(
        builder: (context) => ChangeNotifierProvider.value(
          value: _provider,
          child: MaterialApp(
            theme: theme ?? AppTheme.lightTheme,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const BookLibraryScreen(),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('GoogleFonts')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  });

  int dotIndex(WidgetTester t) =>
      t.widget<ContentDots>(find.byType(ContentDots)).index;

  group('hero', () {
    testWidgets('leads with books in progress, showing where the learner is', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(
          books: _library,
          reading: [_reading('r1'), _reading('r2', progress: 0.9)],
        ),
      );

      expect(find.text('NOW READING'), findsWidgets);
      expect(find.text('Book r1'), findsWidgets);
      expect(find.text('42% read'), findsOneWidget);
      expect(find.text('Continue'), findsWidgets);
      expect(find.text('FEATURED BOOK'), findsNothing);
      expect(tester.widgetList(find.byType(BookHero)), hasLength(2));
      expect(tester.widget<ContentDots>(find.byType(ContentDots)).count, 2);
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byType(BookHero).first,
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, closeTo(0.42, 1e-9));
    });

    testWidgets('with nothing in progress it features curated covers', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(books: _library));

      expect(find.text('FEATURED BOOK'), findsWidgets);
      expect(find.text('Start reading'), findsWidgets);
      expect(find.text('NOW READING'), findsNothing);
      // Three of the four books have artwork; the cover-less one is skipped.
      expect(tester.widget<ContentDots>(find.byType(ContentDots)).count, 3);
    });

    testWidgets('features at most four books', (tester) async {
      await _pump(
        tester,
        _FakeRepo(books: [for (var i = 0; i < 9; i++) _book('x$i')]),
      );
      expect(tester.widget<ContentDots>(find.byType(ContentDots)).count, 4);
    });

    testWidgets('advances on its own', (tester) async {
      await _pump(tester, _FakeRepo(books: _library));
      expect(dotIndex(tester), 0);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(dotIndex(tester), 1);
    });
  });

  group('shelves', () {
    testWidgets('one shelf per level that has books, titled with its level', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(books: _library));
      await tester.scrollUntilVisible(
        find.text('C2 · Proficiency'),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('A1 · Beginner'), findsOneWidget);
      expect(find.text('B1 · Intermediate'), findsOneWidget);
      expect(find.text('C2 · Proficiency'), findsOneWidget);
      expect(find.text('A2 · Elementary'), findsNothing, reason: 'no A2 books');
    });

    testWidgets('a saved shelf appears with its count', (tester) async {
      await _pump(
        tester,
        _FakeRepo(books: _library, saved: [_book('s1'), _book('s2')]),
      );
      expect(find.text('Saved Books · 2'), findsOneWidget);
      expect(find.byType(BookCard), findsWidgets);
    });

    testWidgets('no saved shelf when nothing is saved', (tester) async {
      await _pump(tester, _FakeRepo(books: _library));
      expect(find.textContaining('Saved Books'), findsNothing);
    });

    testWidgets('a cover-less book gets a typeset jacket, not a blank', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(books: [_book('only', cover: '')]));
      expect(find.byType(BookJacket), findsWidgets);
      expect(find.text('Book only'), findsWidgets);
    });
  });

  group('topic chips', () {
    testWidgets('start on All and filter the provider when tapped', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(books: _library));
      expect(find.text('All'), findsOneWidget);
      expect(_provider.selectedTopic, isNull);

      final chip = find.widgetWithText(InkWell, 'Fantasy');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(_provider.selectedTopic, 'Fantasy');
      expect(
        tester.widget<ContentChipBar>(find.byType(ContentChipBar)).selected,
        BookProvider.kTopics.indexOf('Fantasy') + 1,
      );
    });
  });

  group('states', () {
    testWidgets('initial loading lays out (no intrinsic-size error)', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(hang: Completer()), settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(LottieLoadingWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed load offers a retry that reloads', (tester) async {
      final repo = _FakeRepo(fail: true);
      await _pump(tester, repo);

      expect(find.text('Retry'), findsOneWidget);
      final before = repo.loads;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.loads, before + 1);
    });

    testWidgets('an empty library still renders its chrome', (tester) async {
      await _pump(tester, _FakeRepo());
      expect(find.text('Book Library'), findsOneWidget);
      expect(find.byType(BookHero), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('search', () {
    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.byIcon(PhosphorIconsBold.magnifyingGlass));
      await tester.pumpAndSettle();
    }

    testWidgets('shows result tiles, and closing it restores the library', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(books: _library, search: [_book('found')]));
      await openSearch(tester);
      expect(find.byType(BookHero), findsNothing);

      await tester.enterText(find.byType(TextField), 'found');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.text('Book found'), findsOneWidget);

      await tester.tap(find.byIcon(PhosphorIconsBold.x));
      await tester.pumpAndSettle();
      expect(find.text('Book found'), findsNothing);
      expect(find.byType(BookHero), findsWidgets);
    });

    testWidgets('no match says so, naming the query', (tester) async {
      await _pump(tester, _FakeRepo(books: _library));
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.text('No books found for zzzz'), findsOneWidget);
    });
  });

  for (final (name, buildTheme) in <(String, ThemeData Function())>[
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    testWidgets('lays out without overflow at 320px and 2x text ($name)', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(
          books: _library,
          saved: [_book('s1')],
          reading: [_reading('r1')],
        ),
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
