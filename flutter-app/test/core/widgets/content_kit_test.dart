import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? ThemeData(useMaterial3: true),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // google_fonts has nothing bundled in tests and reports that as a
  // zone error after the frame; the layout under test is unaffected.
  void swallowFontErrors() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('GoogleFonts')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  group('ContentHero', () {
    testWidgets('shows copy and fires onTap from anywhere on the card', (
      tester,
    ) async {
      swallowFontErrors();
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 335,
            child: ContentHero(
              imageUrl: '',
              eyebrow: 'Featured',
              title: 'Slow down',
              subtitle: 'By someone',
              cta: const ContentCta(
                label: 'Listen',
                icon: PhosphorIconsFill.play,
              ),
              onTap: () => taps++,
            ),
          ),
        ),
      );

      expect(find.text('FEATURED'), findsOneWidget);
      expect(find.text('Slow down'), findsOneWidget);
      expect(find.text('By someone'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ContentHero)).height,
        ContentHero.height,
      );

      await tester.tap(find.text('Slow down'));
      await tester.tap(find.text('Listen'));
      expect(taps, 2);
    });

    testWidgets('omits eyebrow and subtitle when absent', (tester) async {
      swallowFontErrors();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 335,
            child: ContentHero(
              imageUrl: '',
              title: 'Only title',
              cta: const SizedBox(),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('Only title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is one button that reads the title exactly once', (
      tester,
    ) async {
      swallowFontErrors();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 335,
            child: ContentHero(
              imageUrl: '',
              title: 'Slow down',
              cta: const ContentCta(
                label: 'Listen',
                icon: PhosphorIconsFill.play,
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(ContentHero));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect('Slow down'.allMatches(node.label).length, 1);
      expect(node.label, contains('Listen'));
      handle.dispose();
    });
  });

  group('ContentChipBar', () {
    testWidgets('reports taps and marks only the selected chip', (
      tester,
    ) async {
      final picked = <int>[];
      await tester.pumpWidget(
        _host(
          ContentChipBar(
            labels: const ['All', 'Beginner', 'Advanced'],
            selected: 1,
            onSelected: picked.add,
          ),
        ),
      );

      await tester.tap(find.text('Advanced'));
      expect(picked, [2]);

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Beginner')),
        matchesSemantics(
          label: 'Beginner',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('chips are at least 44 logical px tall', (tester) async {
      await tester.pumpWidget(
        _host(
          ContentChipBar(
            labels: const ['All'],
            selected: 0,
            onSelected: (_) {},
          ),
        ),
      );
      final box = find.ancestor(
        of: find.text('All'),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(box).height, greaterThanOrEqualTo(44));
    });

    testWidgets('selected chip uses the theme primary on both themes', (
      tester,
    ) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          _host(
            ContentChipBar(
              labels: const ['All'],
              selected: 0,
              onSelected: (_) {},
            ),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        final deco =
            tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.text('All'),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(deco.color, theme.colorScheme.primary);
      }
    });
  });

  group('ContentSectionHeader', () {
    testWidgets('renders the action only when both label and callback exist', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          ContentSectionHeader(
            title: 'For you',
            actionLabel: 'See all',
            onAction: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('See all'));
      expect(taps, 1);

      await tester.pumpWidget(
        _host(
          const ContentSectionHeader(title: 'For you', actionLabel: 'See all'),
        ),
      );
      expect(find.text('See all'), findsNothing);
    });
  });

  group('ContentDots', () {
    testWidgets('only the active dot is wide', (tester) async {
      await tester.pumpWidget(_host(const ContentDots(count: 3, index: 1)));
      await tester.pumpAndSettle();
      final widths = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => c.constraints!.maxWidth)
          .toList();
      expect(widths, [6, 20, 6]);
    });
  });

  group('ContentCarousel', () {
    Widget carousel(int count, {Duration every = const Duration(seconds: 5)}) =>
        _host(
          SizedBox(
            width: 300,
            child: ContentCarousel(
              count: count,
              height: 80,
              autoAdvance: every,
              itemBuilder: (_, i) => Center(child: Text('page $i')),
            ),
          ),
        );

    int dot(WidgetTester t) =>
        t.widget<ContentDots>(find.byType(ContentDots)).index;

    testWidgets('moves on by itself and wraps to the first page', (
      tester,
    ) async {
      await tester.pumpWidget(carousel(3));
      expect(dot(tester), 0);
      for (final expected in [1, 2, 0]) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(dot(tester), expected);
      }
    });

    testWidgets('one page: no dots and no movement', (tester) async {
      await tester.pumpWidget(carousel(1));
      expect(find.byType(ContentDots), findsNothing);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('page 0'), findsOneWidget);
    });

    testWidgets('zero pages render nothing and do not throw', (tester) async {
      await tester.pumpWidget(carousel(0));
      expect(find.byType(PageView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starts moving when pages arrive after the first build', (
      tester,
    ) async {
      await tester.pumpWidget(carousel(1));
      await tester.pumpWidget(carousel(2));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(dot(tester), 1);
    });

    testWidgets('a swipe restarts the countdown', (tester) async {
      await tester.pumpWidget(carousel(3));
      await tester.pump(const Duration(seconds: 4));
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(dot(tester), 1);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(dot(tester), 1, reason: 'old timer would have fired by now');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(dot(tester), 2);
    });
  });

  group('ContentBackdrop', () {
    testWidgets('draws the fallback when there is no artwork url', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 100,
            child: ContentBackdrop(
              url: '',
              fallback: ColoredBox(key: Key('fallback'), color: Colors.red),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('fallback')), findsOneWidget);
    });

    testWidgets('without a fallback it uses the tinted image placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 100,
            child: ContentBackdrop(url: ''),
          ),
        ),
      );
      expect(find.byType(ContentImage), findsOneWidget);
    });

    testWidgets('clips its blurred, scaled-up copy to its own box', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 100,
            child: ContentBackdrop(url: ''),
          ),
        ),
      );
      final clip = find.descendant(
        of: find.byType(ContentBackdrop),
        matching: find.byType(ClipRect),
      );
      expect(clip, findsOneWidget);
      expect(tester.getSize(clip), const Size(200, 100));
    });

    testWidgets('keeps a dark scrim over the artwork for white text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 100,
            child: ContentBackdrop(url: ''),
          ),
        ),
      );
      final scrim = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(ContentBackdrop),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color.a > 0.5 && w.color.r == 0,
          ),
        ),
      );
      expect(scrim.color.a, greaterThan(0.5));
    });
  });

  group('ContentImage', () {
    testWidgets('empty url renders the fallback icon', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(width: 80, height: 80, child: ContentImage(url: '')),
        ),
      );
      expect(find.byIcon(PhosphorIconsBold.headphones), findsOneWidget);
    });
  });
}
