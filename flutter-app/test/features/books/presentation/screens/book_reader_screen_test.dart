import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_reader_screen.dart';
import 'package:lexilingo_app/features/books/presentation/widgets/reader_controls.dart';
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

class _FakeRepo extends BookRepository {
  _FakeRepo({this.fail = false});

  final bool fail;
  int fetches = 0;
  final savedProgress = <UserBook>[];

  @override
  Future<String> fetchBookText(Book book) async {
    fetches++;
    if (fail) throw Exception('network down');
    // ~7 pages at 2000 characters each.
    return List.filled(2500, 'reading').join(' ');
  }

  @override
  Future<UserBook?> getProgress(String bookId) async => null;

  @override
  Future<String?> getDownloadedPath(String bookId) async => null;

  @override
  Future<void> saveProgress(UserBook progress) async =>
      savedProgress.add(progress);

  @override
  Future<void> saveReadingSnapshot(Book book) async {}

  @override
  Future<void> awardXP({
    required int baseXp,
    required String sourceId,
    String sourceDetail = 'book_reading',
  }) async {}
}

const _book = Book(id: 'b1', title: 'Moby Dick', author: 'Melville');

late BookProvider _provider;
late _FakeRepo _repo;

Future<void> _pump(
  WidgetTester tester, {
  bool fail = false,
  ThemeData? theme,
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _repo = _FakeRepo(fail: fail);
  _provider = BookProvider(repository: _repo);
  await _provider.openBook(_book);

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
            home: const BookReaderScreen(book: _book),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('loads the text into pages and shows where you are', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Moby Dick'), findsOneWidget);
    expect(_provider.totalPages, greaterThan(3));
    expect(find.text('Page 1 / ${_provider.totalPages}'), findsOneWidget);
  });

  testWidgets('next and previous turn the page and save the place', (
    tester,
  ) async {
    await _pump(tester);
    final previous = find.widgetWithIcon(
      IconButton,
      Icons.navigate_before_rounded,
    );
    expect(tester.widget<IconButton>(previous).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.navigate_next_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 / ${_provider.totalPages}'), findsOneWidget);
    expect(_repo.savedProgress.last.currentPage, 1);

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 / ${_provider.totalPages}'), findsOneWidget);
  });

  testWidgets('tapping the page hides and shows the bars', (tester) async {
    await _pump(tester);
    double topOf() => tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned).first)
        .top!;
    expect(topOf(), 0);

    await tester.tapAt(const Offset(187, 400));
    await tester.pumpAndSettle();
    expect(topOf(), lessThan(0));

    await tester.tapAt(const Offset(187, 400));
    await tester.pumpAndSettle();
    expect(topOf(), 0);
  });

  testWidgets('the settings sheet changes the reading theme', (tester) async {
    await _pump(tester);
    expect(_provider.readerSettings.theme, isNot(ReaderTheme.dark));

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderControls), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(_provider.readerSettings.theme, ReaderTheme.dark);
  });

  testWidgets('a page can be bookmarked and the button reflects it', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Add bookmark'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    expect(_provider.bookmarks, hasLength(1));
  });

  testWidgets('with no bookmarks the panel says how to add one', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('All bookmarks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No bookmarks yet'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and retries', (tester) async {
    await _pump(tester, fail: true);
    expect(find.textContaining('Could not load book.'), findsOneWidget);
    final before = _repo.fetches;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(_repo.fetches, before + 1);
  });

  for (final (name, buildTheme) in <(String, ThemeData Function())>[
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    testWidgets('lays out at 320px and 2x text ($name)', (tester) async {
      await _pump(
        tester,
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
