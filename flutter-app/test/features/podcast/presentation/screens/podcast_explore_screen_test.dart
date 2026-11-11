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
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_explore_screen.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_player_screen.dart';
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

Podcast _podcast(String id, {String level = 'A2', String art = ''}) => Podcast(
  id: id,
  title: 'Show $id',
  author: 'Host $id',
  feedUrl: 'feed://$id',
  artworkUrl: art,
  episodeCount: 12,
  cefrLevel: level,
);

class _FakeRepo extends PodcastRepository {
  _FakeRepo({
    this.categories = const [],
    this.follows = const [],
    this.search = const [],
    this.failCurated = false,
    this.hang,
    this.continueItems = const [],
  });

  final List<PodcastCategory> categories;
  final List<UserPodcastFollow> follows;
  final List<Podcast> search;
  final bool failCurated;
  int curatedCalls = 0;
  final Completer<List<PodcastCategory>>? hang;
  final List<ListeningHistory> continueItems;

  @override
  Future<List<PodcastCategory>> getCuratedPodcasts() async {
    curatedCalls++;
    if (hang != null) return hang!.future;
    if (failCurated) throw Exception('offline');
    return categories;
  }

  @override
  Future<List<UserPodcastFollow>> getFollowedPodcasts() async => follows;

  @override
  Future<List<ListeningHistory>> getContinueListening({int limit = 5}) async =>
      continueItems;

  @override
  Future<List<Podcast>> searchPodcasts({
    required String query,
    int maxResults = 10,
  }) async => search;
}

class _SlowSearchRepo extends _FakeRepo {
  _SlowSearchRepo(this.pending) : super(categories: _twoShelves);
  final Completer<List<Podcast>> pending;

  @override
  Future<List<Podcast>> searchPodcasts({
    required String query,
    int maxResults = 10,
  }) => pending.future;
}

ListeningHistory _resumeEntry(String id, {int position = 120}) =>
    ListeningHistory(
      episodeGuid: 'ep$id',
      feedUrl: 'feed://$id',
      lastPositionSeconds: position,
      durationSeconds: 600,
      updatedAt: DateTime(2026, 10, 23),
      episode: PodcastEpisode(
        guid: 'ep$id',
        title: 'Episode title $id',
        audioUrl: 'https://x/$id.mp3',
        durationSeconds: 600,
        feedUrl: 'feed://$id',
      ),
      podcastTitle: 'Show $id',
    );

final _twoShelves = [
  PodcastCategory(
    id: 'beg',
    label: 'Starter shelf',
    cefrLevel: 'A1-A2',
    podcasts: [
      _podcast('1', art: 'https://example.invalid/a.png'),
      _podcast('2'),
    ],
  ),
  PodcastCategory(
    id: 'adv',
    label: 'Expert shelf',
    cefrLevel: 'C1-C2',
    podcasts: [
      _podcast('3', level: 'C1'),
      _podcast('4', level: 'C2'),
    ],
  ),
];

Future<void> _pickChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(InkWell, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
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
        builder: (context) => ChangeNotifierProvider(
          create: (_) => PodcastProvider(repository: repo),
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
            home: const PodcastExploreScreen(),
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

  testWidgets(
    'shows a featured hero, filter chips and one shelf per category',
    (tester) async {
      await _pump(tester, _FakeRepo(categories: _twoShelves));

      expect(find.text('FEATURED PODCAST'), findsWidgets);
      expect(find.text('Show 1'), findsWidgets);
      expect(find.text('Listen now'), findsWidgets);
      expect(find.byType(ContentDots), findsOneWidget);
      expect(find.byType(ContentChipBar), findsOneWidget);
      for (final label in ['Starter shelf', 'Expert shelf']) {
        expect(find.text(label), findsNWidgets(2), reason: 'chip + header');
      }
      expect(find.text('All'), findsOneWidget);
    },
  );

  int dotIndex(WidgetTester t) =>
      t.widget<ContentDots>(find.byType(ContentDots)).index;

  testWidgets('featured carousel advances on its own and wraps around', (
    tester,
  ) async {
    await _pump(tester, _FakeRepo(categories: _twoShelves));
    expect(dotIndex(tester), 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(dotIndex(tester), 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(dotIndex(tester), 0, reason: 'two slides wrap back to the first');
  });

  testWidgets('a swipe restarts the countdown instead of racing it', (
    tester,
  ) async {
    await _pump(tester, _FakeRepo(categories: _twoShelves));

    await tester.pump(const Duration(seconds: 4));
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(dotIndex(tester), 1);

    // 4s after the swipe the old timer would already have fired at t=5s.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(dotIndex(tester), 1);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(dotIndex(tester), 0);
  });

  testWidgets('a single featured podcast never auto-advances', (tester) async {
    await _pump(
      tester,
      _FakeRepo(
        categories: [
          PodcastCategory(id: 'x', label: 'Only', podcasts: [_podcast('1')]),
        ],
      ),
    );
    expect(find.byType(ContentDots), findsNothing);
    await tester.pump(const Duration(seconds: 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion setting stops the auto-advance', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, _FakeRepo(categories: _twoShelves));

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(dotIndex(tester), 0);
  });

  testWidgets('continue shelf shows the episode, its show and time left', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(
        categories: _twoShelves,
        continueItems: [_resumeEntry('1'), _resumeEntry('2', position: 540)],
      ),
    );

    expect(find.text('Continue listening'), findsOneWidget);
    expect(find.text('Episode title 1'), findsOneWidget);
    expect(find.text('Show 1'), findsWidgets);
    expect(find.text('8 min left'), findsOneWidget, reason: '600s - 120s');
    expect(find.text('1 min left'), findsOneWidget, reason: '600s - 540s');
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).first,
    );
    expect(bar.value, closeTo(0.2, 1e-9));
  });

  testWidgets('continue shelf sits above "Following"', (tester) async {
    await _pump(
      tester,
      _FakeRepo(
        categories: _twoShelves,
        continueItems: [_resumeEntry('1')],
        follows: [
          UserPodcastFollow(
            feedUrl: 'feed://1',
            podcastTitle: 'Followed Show',
            followedAt: DateTime(2026),
          ),
        ],
      ),
    );
    expect(
      tester.getTopLeft(find.text('Continue listening')).dy,
      lessThan(tester.getTopLeft(find.text('Following')).dy),
    );
  });

  testWidgets('no continue shelf when nothing is in progress', (tester) async {
    await _pump(tester, _FakeRepo(categories: _twoShelves));
    expect(find.text('Continue listening'), findsNothing);
  });

  testWidgets('continue shelf is hidden under a level filter', (tester) async {
    await _pump(
      tester,
      _FakeRepo(categories: _twoShelves, continueItems: [_resumeEntry('1')]),
    );
    await _pickChip(tester, 'Expert shelf');
    expect(find.text('Continue listening'), findsNothing);
  });

  testWidgets('tapping a continue tile opens the player on that episode', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(categories: _twoShelves, continueItems: [_resumeEntry('7')]),
    );

    await tester.tap(find.text('Episode title 7'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final player = tester.widget<PodcastPlayerScreen>(
      find.byType(PodcastPlayerScreen),
    );
    expect(player.episode.guid, 'ep7');
    expect(player.podcastTitle, 'Show 7');
    // The player polls for the audio handler every 500ms for up to 10s.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('continue shelf survives 320px width and 2x text', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(categories: _twoShelves, continueItems: [_resumeEntry('1')]),
      size: const Size(320, 640),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a level chip narrows the page to that shelf', (tester) async {
    await _pump(tester, _FakeRepo(categories: _twoShelves));

    await _pickChip(tester, 'Expert shelf');

    expect(find.text('Expert shelf'), findsNWidgets(2));
    expect(find.text('Starter shelf'), findsOneWidget, reason: 'chip only');
    expect(find.text('Show 3'), findsWidgets);
  });

  testWidgets('followed shelf appears only under "All"', (tester) async {
    final repo = _FakeRepo(
      categories: _twoShelves,
      follows: [
        UserPodcastFollow(
          feedUrl: 'feed://1',
          podcastTitle: 'Followed Show',
          followedAt: DateTime(2026),
        ),
      ],
    );
    await _pump(tester, repo);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Followed Show'), findsOneWidget);

    await _pickChip(tester, 'Expert shelf');
    expect(find.text('Following'), findsNothing);
  });

  testWidgets('search swaps the page for result tiles and clear restores it', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(categories: _twoShelves, search: [_podcast('9')]),
    );

    await tester.enterText(find.byType(TextField), 'news');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('Show 9'), findsOneWidget);
    expect(find.text('12 episodes'), findsOneWidget);
    expect(find.byType(ContentChipBar), findsNothing);

    await tester.tap(find.byIcon(PhosphorIconsBold.x));
    await tester.pumpAndSettle();
    expect(find.byType(ContentChipBar), findsOneWidget);
    expect(find.text('Show 9'), findsNothing);
  });

  testWidgets('empty search result explains itself', (tester) async {
    await _pump(tester, _FakeRepo(categories: _twoShelves));
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text('No podcasts found'), findsOneWidget);
  });

  testWidgets('failed load shows a retry that calls the repository again', (
    tester,
  ) async {
    final repo = _FakeRepo(failCurated: true);
    await _pump(tester, repo);

    expect(find.text('Failed to load podcasts'), findsOneWidget);
    final before = repo.curatedCalls;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.curatedCalls, before + 1);
  });

  testWidgets('initial loading state lays out (no intrinsic-size error)', (
    tester,
  ) async {
    final repo = _FakeRepo(hang: Completer());
    tester.view.physicalSize = const Size(375, 812);
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
          builder: (context) => ChangeNotifierProvider(
            create: (_) => PodcastProvider(repository: repo),
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const PodcastExploreScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.curatedCalls, 1);
    expect(find.byType(LottieLoadingWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searching state lays out while results are pending', (
    tester,
  ) async {
    final pending = Completer<List<Podcast>>();
    await _pump(tester, _SlowSearchRepo(pending));
    await tester.enterText(find.byType(TextField), 'news');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LottieLoadingWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    pending.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('empty curated list shows the empty state', (tester) async {
    await _pump(tester, _FakeRepo());
    expect(find.text('No curated podcasts yet'), findsOneWidget);
    expect(find.byType(ContentHero), findsNothing);
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
        _FakeRepo(categories: _twoShelves),
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
