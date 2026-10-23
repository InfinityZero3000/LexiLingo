import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/entitlement_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_detail_screen.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_quiz_screen.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_reader_screen.dart';
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

class _Entitlements implements EntitlementService {
  _Entitlements(this.premium);
  final bool premium;

  @override
  Future<bool> fetchCached({String entitlementId = 'premium'}) async => premium;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo extends BookRepository {
  _FakeRepo({this.progress, this.downloaded});

  final UserBook? progress;
  String? downloaded;
  int downloadCalls = 0;

  @override
  Future<UserBook?> getProgress(String bookId) async => progress;

  @override
  Future<List<Bookmark>> getBookmarks(String bookId) async => const [];

  @override
  Future<String?> getDownloadedPath(String bookId) async => downloaded;

  @override
  Future<String> downloadBook(Book book) async {
    downloadCalls++;
    return downloaded = '/tmp/${book.id}.txt';
  }
}

const _book = Book(
  id: 'b1',
  title: 'Alice in Wonderland',
  author: 'Lewis Carroll',
  subject: 'Fantasy fiction',
  description: 'A girl falls down a rabbit hole into a fantasy world.',
  cefrLevel: 'B1',
  chapterCount: 12,
  wordCount: 27000,
  language: 'en',
);

const _started = UserBook(
  bookId: 'b1',
  currentPage: 42,
  totalPages: 100,
  readingProgress: 0.42,
);

late BookProvider _provider;
late _FakeRepo _repo;

Future<void> _pump(
  WidgetTester tester, {
  UserBook? progress,
  String? downloaded,
  bool premium = true,
  Book book = _book,
  ThemeData? theme,
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  if (sl.isRegistered<EntitlementService>()) {
    sl.unregister<EntitlementService>();
  }
  sl.registerSingleton<EntitlementService>(_Entitlements(premium));
  addTearDown(() {
    if (sl.isRegistered<EntitlementService>()) {
      sl.unregister<EntitlementService>();
    }
  });

  _repo = _FakeRepo(progress: progress, downloaded: downloaded);
  _provider = BookProvider(repository: _repo);
  await _provider.openBook(book);

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
            home: BookDetailScreen(book: book),
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

  group('header', () {
    testWidgets('shows the book, its level and its numbers', (tester) async {
      await _pump(tester);
      expect(find.text('Alice in Wonderland'), findsWidgets);
      expect(find.text('Lewis Carroll'), findsOneWidget);
      expect(find.text('Fantasy fiction'), findsOneWidget);
      expect(find.text('B1'), findsWidgets);
      expect(find.text('12 ch.'), findsOneWidget);
      expect(find.text('27k words'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('leaves out stats and subject the book does not have', (
      tester,
    ) async {
      await _pump(
        tester,
        book: const Book(id: 'b2', title: 'Bare', author: 'Someone'),
      );
      expect(find.textContaining('ch.'), findsNothing);
      expect(find.textContaining('words'), findsNothing);
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('the About section follows the description', (tester) async {
      await _pump(tester);
      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
      expect(find.textContaining('rabbit hole'), findsOneWidget);

      await _pump(
        tester,
        book: const Book(id: 'b3', title: 'No blurb'),
      );
      expect(find.text('About'), findsNothing);
    });
  });

  group('progress and reading', () {
    testWidgets('a new book invites the learner to start', (tester) async {
      await _pump(tester);
      expect(find.text('Start reading'), findsOneWidget);
      expect(find.text('Reading Progress'), findsNothing);
      expect(find.text('Chapter Quiz'), findsNothing);
    });

    testWidgets('a started book continues, with its progress and a quiz', (
      tester,
    ) async {
      await _pump(tester, progress: _started);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Start reading'), findsNothing);
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('Page 43 of 100'), findsOneWidget);
      expect(find.text('Chapter Quiz'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.42, 1e-9));
    });

    testWidgets('the read button opens the reader on this book', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Start reading'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<BookReaderScreen>(find.byType(BookReaderScreen)).book.id,
        'b1',
      );
    });

    testWidgets('the quiz button opens the quiz', (tester) async {
      await _pump(tester, progress: _started);
      await tester.tap(find.text('Chapter Quiz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BookQuizScreen), findsOneWidget);
    });
  });

  group('save and download', () {
    testWidgets('the heart saves the book and unsaves it again', (
      tester,
    ) async {
      await _pump(tester);
      expect(_provider.isBookSaved('b1'), isFalse);

      await tester.tap(find.byTooltip('Save book'));
      await tester.pumpAndSettle();
      expect(_provider.isBookSaved('b1'), isTrue);
      expect(find.byIcon(PhosphorIconsFill.heart), findsOneWidget);

      await tester.tap(find.byTooltip('Remove from saved'));
      await tester.pumpAndSettle();
      expect(_provider.isBookSaved('b1'), isFalse);
    });

    testWidgets('a premium learner downloads, then sees it as downloaded', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Download for offline'));
      await tester.pumpAndSettle();

      expect(_repo.downloadCalls, 1);
      expect(find.text('Downloaded'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Downloaded'),
      );
      expect(button.onPressed, isNull, reason: 'nothing left to download');
    });

    testWidgets('a free learner sees the download locked', (tester) async {
      await _pump(tester, premium: false);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(_repo.downloadCalls, 0);
    });

    testWidgets('an already-downloaded book stays usable without premium', (
      tester,
    ) async {
      await _pump(tester, premium: false, downloaded: '/tmp/b1.txt');
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });
  });

  testWidgets('the top bar is clear over the cover, solid once scrolled', (
    tester,
  ) async {
    // Enough text that the page can scroll past the header.
    await _pump(
      tester,
      progress: _started,
      book: Book(
        id: 'b1',
        title: 'Alice in Wonderland',
        description: List.filled(
          40,
          'A long paragraph of the blurb.',
        ).join('\n\n'),
      ),
    );
    double titleOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.text('Alice in Wonderland').last,
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    expect(titleOpacity(), 0);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(titleOpacity(), 1);
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
        progress: _started,
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
