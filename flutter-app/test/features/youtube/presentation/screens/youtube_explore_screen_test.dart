import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/features/youtube/data/repositories/youtube_repository.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';
import 'package:lexilingo_app/features/youtube/presentation/screens/youtube_explore_screen.dart';
import 'package:lexilingo_app/features/youtube/presentation/widgets/youtube_video_tiles.dart';
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

YouTubeVideo _video(int i, {String level = 'B1', String channel = 'Chan'}) =>
    YouTubeVideo(
      videoId: 'v$i',
      title: 'Video $i',
      description: '',
      channelTitle: '$channel $i',
      channelId: 'c$i',
      publishedAt: '',
      thumbnailUrl: '',
      cefrLevel: level,
    );

YouTubeChannel _channel(
  String id,
  String name, {
  String category = 'general',
}) => YouTubeChannel(
  id: id,
  name: name,
  description: '',
  level: 'B1',
  thumbnail: '',
  category: category,
);

class _FakeRepo extends YouTubeRepository {
  _FakeRepo({
    this.channels = const [],
    this.recommended = const [],
    this.searchHits = const [],
    this.channelVideos = const [],
    this.hangChannels,
    this.searchError,
  });

  final List<YouTubeChannel> channels;
  final List<YouTubeVideo> recommended;
  final List<YouTubeVideo> searchHits;
  final List<YouTubeVideo> channelVideos;
  final Completer<List<YouTubeChannel>>? hangChannels;
  final Exception? searchError;
  final categoryCalls = <String?>[];

  @override
  Future<List<YouTubeChannel>> getCuratedChannels({String? category}) async {
    categoryCalls.add(category);
    if (hangChannels != null) return hangChannels!.future;
    return channels;
  }

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    int maxResults = 10,
    String? channelId,
    String? pageToken,
  }) async {
    // loadRecommendations always asks for this query; anything else is a search.
    if (query != 'Learn English') {
      if (searchError != null) throw searchError!;
      return YouTubeSearchResult(
        videos: searchHits,
        totalResults: searchHits.length,
      );
    }
    return YouTubeSearchResult(
      videos: recommended,
      totalResults: recommended.length,
    );
  }

  @override
  Future<YouTubeSearchResult> getChannelVideos(
    String channelId, {
    int maxResults = 10,
    String? pageToken,
  }) async => YouTubeSearchResult(
    videos: channelVideos,
    totalResults: channelVideos.length,
  );
}

late YouTubeProvider _provider;
final _pushedVideos = <String>[];

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
  _provider = YouTubeProvider(repository: repo);
  _pushedVideos.clear();

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
            onGenerateRoute: (settings) {
              if (settings.name == '/youtube/player') {
                _pushedVideos.add((settings.arguments as YouTubeVideo).videoId);
                return MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('player page')),
                );
              }
              return null;
            },
            home: const YouTubeExploreScreen(),
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
    // Thumbnails load through cached_network_image, which needs platform
    // plugins a unit test does not have; the tile's own fallback is what is
    // shown, and that is what these tests look at.
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = '${details.exception}';
      if (text.contains('GoogleFonts') ||
          text.contains('MissingPluginException') ||
          text.contains('HttpException') ||
          text.contains('SocketException')) {
        return;
      }
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  });

  int dotCount(WidgetTester t) =>
      t.widget<ContentDots>(find.byType(ContentDots)).count;

  final channels = [
    _channel('c1', 'BBC Learning'),
    _channel('c2', 'TED Ed', category: 'academic'),
  ];

  group('home tab', () {
    testWidgets('hero takes four recommended videos, the rest go on a shelf', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(
          channels: channels,
          recommended: [for (var i = 0; i < 6; i++) _video(i)],
        ),
      );

      expect(dotCount(tester), 4);
      expect(find.text('Watch now'), findsWidgets);
      expect(find.text('Video 0'), findsWidgets);
      expect(find.byType(YouTubeShelfCard), findsNWidgets(2));
      expect(
        find.text('For you'),
        findsNWidgets(2),
        reason: 'tab + shelf header',
      );
    });

    testWidgets('without recommendations there is no hero or shelf', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(channels: channels));
      expect(find.byType(ContentHero), findsNothing);
      expect(find.byType(YouTubeShelfCard), findsNothing);
      expect(find.byType(YouTubeChannelAvatar), findsNWidgets(2));
    });

    testWidgets('hero advances on its own', (tester) async {
      await _pump(
        tester,
        _FakeRepo(recommended: [for (var i = 0; i < 3; i++) _video(i)]),
      );
      int index() => tester.widget<ContentDots>(find.byType(ContentDots)).index;
      expect(index(), 0);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(index(), 1);
    });

    testWidgets('tapping the hero opens the player with that video', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(recommended: [for (var i = 0; i < 2; i++) _video(i)]),
      );
      await tester.tap(find.text('Video 0').first);
      await tester.pumpAndSettle();
      expect(_pushedVideos, ['v0']);
      expect(find.text('player page'), findsOneWidget);
    });

    testWidgets('a shelf card opens the player too', (tester) async {
      await _pump(
        tester,
        _FakeRepo(recommended: [for (var i = 0; i < 6; i++) _video(i)]),
      );
      final card = find.byType(YouTubeShelfCard).first;
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(_pushedVideos, ['v4']);
    });
  });

  group('channels and topics', () {
    testWidgets(
      'each channel shows its name and an initial when it has no image',
      (tester) async {
        await _pump(tester, _FakeRepo(channels: channels));
        expect(find.text('BBC Learning'), findsOneWidget);
        expect(find.text('TED Ed'), findsOneWidget);
        expect(find.text('B'), findsOneWidget);
        expect(find.text('T'), findsOneWidget);
      },
    );

    testWidgets('avatars stay centred in their slot whatever the name length', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(
          channels: [
            _channel('c1', 'BBC Learning English with a long name'),
            _channel('c2', 'TED'),
            _channel('c3', 'English with Lucy'),
          ],
        ),
      );
      final avatars = find.byType(YouTubeChannelAvatar);
      expect(avatars, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final slot = tester.getCenter(avatars.at(i)).dx;
        final ring = tester.getCenter(
          find.descendant(of: avatars.at(i), matching: find.byType(ClipOval)),
        );
        expect(ring.dx, closeTo(slot, 0.5), reason: 'avatar $i is off-centre');
      }
    });

    testWidgets('a topic chip reloads channels for that category', (
      tester,
    ) async {
      final repo = _FakeRepo(channels: channels);
      await _pump(tester, repo);
      expect(repo.categoryCalls, [null]);

      final chip = find.widgetWithText(InkWell, 'Pronunciation');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(repo.categoryCalls.last, 'pronunciation');

      await tester.drag(find.byType(ContentChipBar), const Offset(800, 0));
      await tester.pumpAndSettle();
      final all = find.widgetWithText(InkWell, 'All');
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(repo.categoryCalls.last, isNull);
    });

    testWidgets('tapping a channel shows its videos under its name', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(channels: channels, channelVideos: [_video(7)]),
      );
      await tester.tap(find.text('BBC Learning'));
      await tester.pumpAndSettle();

      expect(find.text('BBC Learning'), findsOneWidget, reason: 'header');
      expect(find.text('Video 7'), findsOneWidget);
      expect(find.byType(YouTubeVideoTile), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(YouTubeChannelAvatar), findsNWidgets(2));
    });
  });

  testWidgets('tab labels are never squeezed into a quarter of the width', (
    tester,
  ) async {
    await _pump(tester, _FakeRepo());
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    for (final tab in tester.widgetList<Tab>(find.byType(Tab))) {
      final label = find.descendant(
        of: find.byWidget(tab),
        matching: find.byType(Text),
      );
      // The Tab is the room the label gets; the tab bar's padding sits outside.
      final text = tester.renderObject<RenderParagraph>(label);
      expect(
        text.size.width,
        lessThanOrEqualTo(tester.getSize(find.byWidget(tab)).width),
        reason: '"${tab.text}" would be clipped by its own tab',
      );
    }
  });

  group('tabs', () {
    Future<void> openTab(WidgetTester tester, String label) async {
      final tab = find.widgetWithText(Tab, label);
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    testWidgets('recommended lists every recommendation as a row', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(recommended: [for (var i = 0; i < 3; i++) _video(i)]),
      );
      await openTab(tester, 'For you');
      expect(find.byType(YouTubeVideoTile), findsNWidgets(3));
    });

    testWidgets('saved and history explain themselves when empty', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo());
      await openTab(tester, 'Saved');
      expect(find.text('No saved videos yet'), findsOneWidget);
      await openTab(tester, 'History');
      expect(find.text('History is empty'), findsOneWidget);
    });

    testWidgets('saving from a row bookmarks it and toggles back', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(recommended: [_video(1)]));
      await openTab(tester, 'For you');
      expect(_provider.isVideoSaved('v1'), isFalse);

      await tester.tap(find.byTooltip('Save video'));
      await tester.pumpAndSettle();
      expect(_provider.isVideoSaved('v1'), isTrue);

      await tester.tap(find.byTooltip('Removed from saved videos'));
      await tester.pumpAndSettle();
      expect(_provider.isVideoSaved('v1'), isFalse);
    });

    testWidgets('the header bookmark jumps to Saved and shows the count', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(recommended: [_video(1)]));
      await openTab(tester, 'For you');
      await tester.tap(find.byTooltip('Save video'));
      await tester.pumpAndSettle();
      await openTab(tester, 'Explore');

      expect(find.text('1'), findsOneWidget, reason: 'badge count');
      await tester.tap(find.byIcon(PhosphorIconsFill.bookmarkSimple).first);
      await tester.pumpAndSettle();
      expect(find.byType(YouTubeVideoTile), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('typing swaps the page for matching rows', (tester) async {
      await _pump(
        tester,
        _FakeRepo(channels: channels, searchHits: [_video(9)]),
      );
      await tester.enterText(find.byType(TextField), 'grammar');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(find.text('Video 9'), findsOneWidget);
      expect(find.byType(YouTubeChannelAvatar), findsNothing);
    });

    testWidgets('a service error is reported in the learner\'s language', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(searchError: Exception('503 unavailable')));
      await tester.enterText(find.byType(TextField), 'grammar');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The video service is temporarily unavailable.\nPlease try again later.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('initial loading lays out (no intrinsic-size error)', (
    tester,
  ) async {
    await _pump(tester, _FakeRepo(hangChannels: Completer()), settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LottieLoadingWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
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
          channels: channels,
          recommended: [for (var i = 0; i < 7; i++) _video(i)],
        ),
        theme: buildTheme(),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final tab = find.widgetWithText(Tab, 'For you');
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
