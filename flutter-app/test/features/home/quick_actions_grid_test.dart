import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/quick_actions_grid.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    double textScale = 1,
    bool lock = false,
    RouteFactory? onGenerateRoute,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        onGenerateRoute: onGenerateRoute,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickActionsGrid(lockSecondary: lock),
          ),
        ),
      ),
    );
  }

  double rowOf(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  testWidgets('phone width: two full rows of four', (tester) async {
    await pumpAt(tester, 375);

    expect(rowOf(tester, 'home.navLearning'), rowOf(tester, 'home.games'));
    expect(rowOf(tester, 'home.youtube'), rowOf(tester, 'home.books'));
    expect(
      rowOf(tester, 'home.navLearning'),
      lessThan(rowOf(tester, 'home.youtube')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new learner: four starting tiles in one row at 375', (
    tester,
  ) async {
    await pumpAt(tester, 375, lock: true);

    expect(find.byType(InkResponse), findsNWidgets(4));
    expect(rowOf(tester, 'home.navLearning'), rowOf(tester, 'home.games'));
    expect(tester.takeException(), isNull);
    for (final tile in tester.widgetList<InkResponse>(
      find.byType(InkResponse),
    )) {
      expect(tile.onTap, isNotNull);
    }
    for (final element in find.byType(InkResponse).evaluate()) {
      final size = tester.getSize(find.byElementPredicate((e) => e == element));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
  });

  // Outside a MainScreen the Learning and Lexi tiles fall back to their routes;
  // inside one they switch its tab through MainScreen.switchTab (no push).
  const routes = {
    'home.navLearning': '/courses',
    'home.navLexi': '/lexi',
    'home.games': '/games',
    'home.youtube': '/youtube',
    'home.news': '/news',
    'home.podcast': '/podcast',
    'home.books': '/books',
  };
  for (final entry in routes.entries) {
    testWidgets('${entry.key} opens ${entry.value}', (tester) async {
      String? pushed;
      await pumpAt(
        tester,
        375,
        onGenerateRoute: (settings) {
          pushed = settings.name;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox(),
          );
        },
      );
      await tester.tap(find.text(entry.key));
      await tester.pump();
      expect(pushed, entry.value);
    });
  }

  testWidgets('home.vocabulary opens the vocabulary library', (tester) async {
    await pumpAt(tester, 375);
    await tester.tap(find.text('home.vocabulary'));
    await tester.pump();
    // The page needs VocabProvider, which this harness does not supply:
    // failing to build it is the proof the route was pushed.
    expect(tester.takeException(), isA<ProviderNotFoundException>());
  });

  for (final width in [640.0, 768.0, 1280.0]) {
    testWidgets('$width wide: one row, never a short last row', (tester) async {
      await pumpAt(tester, width);

      expect(rowOf(tester, 'home.navLearning'), rowOf(tester, 'home.books'));
    });
  }

  testWidgets('200% text on a phone: tiles grow, nothing overflows', (
    tester,
  ) async {
    await pumpAt(tester, 375, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('home.vocabulary'), findsOneWidget);
  });
}
