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
import 'package:lexilingo_app/features/books/presentation/screens/book_quiz_screen.dart';
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
  _FakeRepo(this.quiz);

  final BookQuiz quiz;

  @override
  Future<BookQuiz> getChapterQuiz({
    required String bookId,
    required int chapter,
    Book? book,
    String? chapterExcerpt,
  }) async => quiz;

  @override
  Future<UserBook?> getProgress(String bookId) async => null;

  @override
  Future<List<Bookmark>> getBookmarks(String bookId) async => const [];

  @override
  Future<String?> getDownloadedPath(String bookId) async => null;
}

BookQuiz _quiz(int n) => BookQuiz(
  bookId: 'b1',
  chapter: 1,
  xpReward: 40,
  questions: [
    for (var i = 0; i < n; i++)
      BookQuizQuestion(
        id: 'q$i',
        question: 'Question $i?',
        options: const ['Right', 'Wrong one', 'Wrong two'],
        correctIndex: 0,
        explanation: 'Because of reason $i.',
      ),
  ],
);

late BookProvider _provider;

Future<void> _pump(
  WidgetTester tester,
  BookQuiz quiz, {
  ThemeData? theme,
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _provider = BookProvider(repository: _FakeRepo(quiz));
  await _provider.openBook(const Book(id: 'b1', title: 'T', cefrLevel: 'B1'));

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
            home: const BookQuizScreen(chapter: 1),
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

  testWidgets('shows the first question, its options and where you are', (
    tester,
  ) async {
    await _pump(tester, _quiz(2));
    expect(find.text('Question 0?'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(
      find.text('Next question'),
      findsNothing,
      reason: 'not answered yet',
    );
  });

  testWidgets('answering reveals the explanation and the next step', (
    tester,
  ) async {
    await _pump(tester, _quiz(2));
    await tester.tap(find.text('Right'));
    await tester.pumpAndSettle();
    expect(find.text('Because of reason 0.'), findsOneWidget);
    expect(find.text('Next question'), findsOneWidget);
  });

  testWidgets('the last question offers results instead of "next"', (
    tester,
  ) async {
    await _pump(tester, _quiz(1));
    await tester.tap(find.text('Right'));
    await tester.pumpAndSettle();
    expect(find.text('See results'), findsOneWidget);
    expect(find.text('Next question'), findsNothing);
  });

  testWidgets('a perfect run ends on an excellent result with XP', (
    tester,
  ) async {
    await _pump(tester, _quiz(2));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Right'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(i == 0 ? 'Next question' : 'See results'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Excellent!'), findsOneWidget);
    expect(find.text('2 / 2 correct'), findsOneWidget);
    expect(find.text('Back to Book'), findsOneWidget);
    expect(find.textContaining('40'), findsOneWidget, reason: 'XP earned');
  });

  testWidgets('getting everything wrong says to keep reading, with no XP', (
    tester,
  ) async {
    await _pump(tester, _quiz(1));
    await tester.tap(find.text('Wrong one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See results'));
    await tester.pumpAndSettle();
    expect(find.text('Keep reading!'), findsOneWidget);
    expect(find.text('0 / 1 correct'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
  });

  testWidgets('an empty quiz says it is not available', (tester) async {
    await _pump(tester, _quiz(0));
    expect(find.text('Quiz not available.'), findsOneWidget);
  });

  testWidgets(
    'the action button is readable on the theme accent in dark mode',
    (tester) async {
      final dark = AppTheme.darkTheme;
      await _pump(tester, _quiz(2), theme: dark);
      await tester.tap(find.text('Right'));
      await tester.pumpAndSettle();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next question'),
      );
      final fg = button.style!.foregroundColor!.resolve({})!;
      expect(
        fg,
        dark.colorScheme.onPrimary,
        reason: 'white on cyan is unreadable',
      );
    },
  );

  for (final (name, buildTheme) in <(String, ThemeData Function())>[
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    testWidgets('lays out at 320px and 2x text ($name)', (tester) async {
      await _pump(
        tester,
        _quiz(2),
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      await tester.tap(find.text('Right'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
