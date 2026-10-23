import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_player_screen.dart';
import 'package:lexilingo_app/features/podcast/presentation/widgets/player_header.dart';
import 'package:lexilingo_app/features/podcast/presentation/widgets/transcript_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the shipped en.json so a missing key shows up here, not on a device.
class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  ThemeData? theme,
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      assetLoader: const _DiskAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
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
          home: home,
        ),
      ),
    ),
  );
  await tester.pump();
}

const _episode = PodcastEpisode(
  guid: 'g1',
  title: 'What should you eat for a better night\'s sleep?',
  audioUrl: 'https://x/a.mp3',
  durationSeconds: 360,
  feedUrl: 'feed://one',
  cefrLevel: 'B2',
);

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

  group('PlayerHeader', () {
    testWidgets('shows the episode, the show and the level', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: PlayerHeader(
            title: 'Episode title',
            podcastTitle: 'Show title',
            artworkUrl: '',
            level: 'B2',
          ),
        ),
      );
      expect(find.text('Episode title'), findsOneWidget);
      expect(find.text('Show title'), findsOneWidget);
      expect(find.text('B2'), findsOneWidget);
    });

    testWidgets('leaves out the show line when there is none', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: PlayerHeader(
            title: 'Episode title',
            podcastTitle: '',
            artworkUrl: '',
            level: 'A1',
          ),
        ),
      );
      expect(find.text('Episode title'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });

    testWidgets('artwork fills a phone but never grows past 280', (
      tester,
    ) async {
      Size artwork() => tester.getSize(
        find
            .descendant(
              of: find.byType(PlayerHeader),
              matching: find.byType(ClipRRect),
            )
            .at(1),
      );
      const header = Scaffold(
        body: PlayerHeader(
          title: 't',
          podcastTitle: 'p',
          artworkUrl: '',
          level: 'B1',
        ),
      );
      await _pump(tester, header);
      expect(artwork().width, 375 - 96);

      await _pump(tester, header, size: const Size(900, 800));
      expect(artwork().width, 280);
    });

    for (final (name, buildTheme) in <(String, ThemeData Function())>[
      ('light', () => AppTheme.lightTheme),
      ('dark', () => AppTheme.darkTheme),
    ]) {
      testWidgets('lays out at 320px and 2x text ($name)', (tester) async {
        await _pump(
          tester,
          const Scaffold(
            body: SingleChildScrollView(
              child: PlayerHeader(
                title:
                    'A very long episode title that has to wrap over several lines',
                podcastTitle: 'A long show title as well',
                artworkUrl: '',
                level: 'C1',
              ),
            ),
          ),
          theme: buildTheme(),
          size: const Size(320, 640),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('TranscriptPanel', () {
    testWidgets('loading shows a skeleton, not the empty message', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(body: TranscriptPanel(isLoading: true)),
      );
      expect(find.text('No transcript available'), findsNothing);
      expect(find.text('Transcript'), findsOneWidget);
    });

    testWidgets('a transcript is split into one block per paragraph', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: TranscriptPanel(
              isLoading: false,
              transcript: 'First paragraph.\n\nSecond paragraph.\n\n\n\nThird.',
            ),
          ),
        ),
      );
      expect(find.text('First paragraph.'), findsOneWidget);
      expect(find.text('Second paragraph.'), findsOneWidget);
      expect(find.text('Third.'), findsOneWidget);
    });

    testWidgets('empty offers to generate one, and the button works', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: TranscriptPanel(
              isLoading: false,
              onGenerateTranscript: () => taps++,
            ),
          ),
        ),
      );
      expect(find.text('No transcript available'), findsOneWidget);
      await tester.tap(find.text('Generate Transcript'));
      expect(taps, 1);
    });

    testWidgets('the heading can be left to the screen', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: TranscriptPanel(isLoading: true, showHeading: false),
        ),
      );
      expect(find.text('Transcript'), findsNothing);
    });
  });

  group('PodcastPlayerScreen without an audio handler yet', () {
    Future<void> openScreen(
      WidgetTester tester, {
      Size? size,
      double scale = 1,
    }) => _pump(
      tester,
      const PodcastPlayerScreen(
        episode: _episode,
        artworkUrl: '',
        podcastTitle: 'Show title',
      ),
      size: size ?? const Size(375, 812),
      textScale: scale,
    );

    testWidgets('shows the header and a loader instead of controls', (
      tester,
    ) async {
      await openScreen(tester);
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text(_episode.title), findsOneWidget);
      expect(find.text('Show title'), findsOneWidget);
      expect(find.byType(LottieLoadingWidget), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      // The player polls for the audio handler every 500ms for up to 10s.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('the transcript section folds open and shut', (tester) async {
      await openScreen(tester);
      expect(find.byType(TranscriptPanel), findsNothing);

      await tester.ensureVisible(find.text('Transcript'));
      await tester.tap(find.text('Transcript'));
      await tester.pump();
      expect(find.byType(TranscriptPanel), findsOneWidget);
      expect(
        tester
            .widget<TranscriptPanel>(find.byType(TranscriptPanel))
            .showHeading,
        isFalse,
      );

      await tester.tap(find.text('Transcript'));
      await tester.pump();
      expect(find.byType(TranscriptPanel), findsNothing);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('lays out at 320px and 2x text', (tester) async {
      await openScreen(tester, size: const Size(320, 640), scale: 2);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
