import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_detail_screen.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_player_screen.dart';
import 'package:lexilingo_app/features/podcast/presentation/widgets/episode_tile.dart';
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

const _podcast = Podcast(
  id: 'p1',
  title: 'Show One',
  author: 'Host One',
  description:
      'A long description of the show. '
      'It goes on and on. '
      'More words here. '
      'Even more words so it needs three lines at least on a phone.',
  feedUrl: 'feed://one',
  episodeCount: 3,
  cefrLevel: 'B1',
);

PodcastEpisode _episode(
  int i, {
  int duration = 600,
  String published = '',
  String? level,
}) => PodcastEpisode(
  guid: 'g$i',
  title: 'Episode $i',
  audioUrl: 'https://x/$i.mp3',
  durationSeconds: duration,
  publishedAt: published,
  feedUrl: 'feed://one',
  cefrLevel: level,
);

class _FakeRepo extends PodcastRepository {
  _FakeRepo({this.episodes = const [], this.fail = false, this.hang});

  final List<PodcastEpisode> episodes;
  final bool fail;
  final Completer<List<PodcastEpisode>>? hang;
  int loads = 0;
  final downloads = <String>[];

  @override
  Future<List<PodcastEpisode>> getEpisodes({
    required String feedUrl,
    int limit = 20,
  }) async {
    loads++;
    if (hang != null) return hang!.future;
    if (fail) throw Exception('offline');
    return episodes;
  }

  @override
  Future<PodcastEpisode> downloadEpisode(PodcastEpisode episode) async {
    downloads.add(episode.guid);
    return episode.copyWith(downloadState: DownloadState.downloaded);
  }
}

String _historyJson(String guid, {int position = 200, bool done = false}) =>
    jsonEncode(
      ListeningHistory(
        episodeGuid: guid,
        feedUrl: 'feed://one',
        lastPositionSeconds: position,
        durationSeconds: 600,
        completed: done,
        updatedAt: DateTime(2026, 10, 23),
      ).toJson(),
    );

late PodcastProvider _provider;

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  Map<String, Object> prefs = const {},
  ThemeData? theme,
  Size size = const Size(375, 812),
  double textScale = 1,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _provider = PodcastProvider(repository: repo);

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
            home: const PodcastDetailScreen(podcast: _podcast),
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

  final threeEpisodes = [for (var i = 1; i <= 3; i++) _episode(i, level: 'B1')];

  group('header and list', () {
    testWidgets('shows the show, its actions and one tile per episode', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(episodes: threeEpisodes),
        size: const Size(375, 1600),
      );

      expect(
        find.text('Show One'),
        findsNWidgets(2),
        reason: 'header + the top bar title that shows once scrolled',
      );
      expect(find.text('Host One'), findsOneWidget);
      expect(find.text('B1'), findsWidgets);
      expect(find.text('Play latest episode'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('3 episodes'), findsOneWidget);
      expect(find.byType(EpisodeTile), findsNWidgets(3));
    });

    testWidgets('saved progress shows on the matching episodes', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(episodes: threeEpisodes),
        prefs: {
          'podcast_listening_history': [
            _historyJson('g1', position: 180),
            _historyJson('g2', position: 590, done: true),
          ],
        },
      );
      expect(find.text('30% listened'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });

    testWidgets('the description folds and unfolds', (tester) async {
      await _pump(tester, _FakeRepo(episodes: threeEpisodes));
      expect(find.text('Show more'), findsOneWidget);
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('a download button asks the provider to download', (
      tester,
    ) async {
      final repo = _FakeRepo(episodes: [_episode(1)]);
      await _pump(tester, repo);
      await tester.tap(find.byTooltip('Download'));
      await tester.pumpAndSettle();
      expect(repo.downloads, ['g1']);
      expect(find.byTooltip('Downloaded'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('follow flips to Following and confirms with a snack bar', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(episodes: threeEpisodes));
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();

      expect(find.text('Following'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_provider.followedPodcasts.single.feedUrl, 'feed://one');

      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      expect(_provider.followedPodcasts, isEmpty);
    });

    testWidgets('play latest opens the player on the first episode', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(episodes: threeEpisodes));
      await tester.tap(find.text('Play latest episode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final player = tester.widget<PodcastPlayerScreen>(
        find.byType(PodcastPlayerScreen),
      );
      expect(player.episode.guid, 'g1');
      expect(player.podcastTitle, 'Show One');
      // The player polls for the audio handler every 500ms for up to 10s.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('tapping an episode opens the player on that one', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(episodes: threeEpisodes));
      await tester.scrollUntilVisible(
        find.text('Episode 3'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Episode 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester
            .widget<PodcastPlayerScreen>(find.byType(PodcastPlayerScreen))
            .episode
            .guid,
        'g3',
      );
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('no play-latest while there are no episodes', (tester) async {
      await _pump(tester, _FakeRepo());
      expect(find.text('Play latest episode'), findsNothing);
      expect(find.text('Follow'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('loading shows skeleton rows and lays out cleanly', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(hang: Completer()), settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EpisodeTile), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed load offers a retry that reloads', (tester) async {
      final repo = _FakeRepo(fail: true);
      await _pump(tester, repo);
      expect(find.text('Failed to load episodes'), findsOneWidget);
      final before = repo.loads;
      // The state sits under the header, so on a phone it starts below the fold.
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.loads, before + 1);
    });

    testWidgets('an empty feed says so', (tester) async {
      await _pump(tester, _FakeRepo());
      expect(find.text('No episodes available'), findsOneWidget);
    });
  });

  group('top bar', () {
    double titleOpacity(WidgetTester t) => t
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text('Show One').last,
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('is clear over the artwork, solid with a title once scrolled', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(episodes: [for (var i = 1; i <= 12; i++) _episode(i)]),
      );
      expect(titleOpacity(tester), 0);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(titleOpacity(tester), 1);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(titleOpacity(tester), 0);
    });
  });

  group('EpisodeTile labels', () {
    Future<List<String>> ages(WidgetTester tester, List<String> dates) async {
      SharedPreferences.setMockInitialValues({});
      late List<String> out;
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          assetLoader: const _DiskAssetLoader(),
          child: Builder(
            builder: (context) {
              final now = DateTime(2026, 10, 23, 12);
              out = [for (final d in dates) EpisodeTile.ageLabel(d, now: now)];
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return out;
    }

    testWidgets('age is spoken in whole units, newest first', (tester) async {
      expect(
        await ages(tester, [
          '2026-10-23T08:00:00',
          '2026-10-22T08:00:00',
          '2026-10-20T08:00:00',
          '2026-10-02T08:00:00',
          '2026-06-01T08:00:00',
          '2024-10-01T08:00:00',
          '',
          'not a date',
        ]),
        [
          'Today',
          'Yesterday',
          '3d ago',
          '3w ago',
          '4mo ago',
          '2y ago',
          '',
          'not a date',
        ],
      );
    });

    test('duration is mm:ss, h m, or a dash when unknown', () {
      expect(EpisodeTile.durationLabel(0), '–');
      expect(EpisodeTile.durationLabel(65), '01:05');
      expect(EpisodeTile.durationLabel(3900), '1h 5m');
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
          episodes: [
            for (var i = 1; i <= 4; i++)
              _episode(i, published: '2026-10-20T00:00:00', level: 'B2'),
          ],
        ),
        prefs: {
          'podcast_listening_history': [_historyJson('g1', position: 200)],
        },
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
