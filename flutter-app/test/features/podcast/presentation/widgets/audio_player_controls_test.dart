import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/podcast/presentation/widgets/audio_player_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PodcastTestAssetLoader extends AssetLoader {
  const _PodcastTestAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    return const {
      'podcast': {
        'playbackSpeed': 'Playback Speed',
        'rewind15': 'Rewind 15 s',
        'forward15': 'Skip 15 s',
        'sleepTimer': 'Sleep Timer',
        'sleepTimerOff': 'Off',
        'sleepTimerMinutes': '{count} min',
        'sleepTimerCancel': 'Cancel timer ({count} min left)',
      },
    };
  }
}

Widget _localizedApp({required Widget home}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/i18n',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    useOnlyLangCode: true,
    assetLoader: const _PodcastTestAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: home,
      ),
    ),
  );
}

AudioPlayerControls _controls({
  required ValueChanged<Duration> onSeek,
  required ValueChanged<Duration?> onSleepTimerSet,
  Duration duration = const Duration(minutes: 10),
  int? sleepTimerSecondsRemaining,
}) {
  return AudioPlayerControls(
    onPlay: () {},
    onPause: () {},
    onSkipBack: () {},
    onSkipForward: () {},
    onSpeedChange: (_) {},
    onSeek: onSeek,
    onSleepTimerSet: onSleepTimerSet,
    isPlaying: false,
    playbackSpeed: 1.0,
    position: Duration.zero,
    duration: duration,
    episodeTitle: 'Test Episode',
    artworkUrl: '',
    sleepTimerSecondsRemaining: sleepTimerSecondsRemaining,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'dragging the seek bar calls onSeek with a position within the episode duration',
    (tester) async {
      Duration? seeked;
      await tester.pumpWidget(
        _localizedApp(
          home: Scaffold(
            body: _controls(onSeek: (d) => seeked = d, onSleepTimerSet: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      await tester.drag(sliderFinder, const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(seeked, isNotNull);
      expect(seeked!.inMilliseconds, greaterThan(0));
      expect(seeked!, lessThanOrEqualTo(const Duration(minutes: 10)));
    },
  );

  testWidgets('skip buttons no longer render a misleading 10-second icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        home: Scaffold(
          body: _controls(onSeek: (_) {}, onSleepTimerSet: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
    expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
    expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
  });

  testWidgets(
    'selecting a sleep timer preset calls onSleepTimerSet with that duration',
    (tester) async {
      // The default test surface is too short for the sheet's 7 rows —
      // widen it so the sheet fits without the test itself overflowing.
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Duration? setDuration;
      await tester.pumpWidget(
        _localizedApp(
          home: Scaffold(
            body: _controls(
              onSeek: (_) {},
              onSleepTimerSet: (d) => setDuration = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Sleep Timer'));
      await tester.pumpAndSettle();

      expect(find.text('15 min'), findsOneWidget);
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();

      expect(setDuration, const Duration(minutes: 15));
    },
  );

  testWidgets(
    'an active sleep timer shows a cancel option that calls onSleepTimerSet(null)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Duration? result = const Duration(minutes: 30); // sentinel != null
      var called = false;
      await tester.pumpWidget(
        _localizedApp(
          home: Scaffold(
            body: _controls(
              onSeek: (_) {},
              onSleepTimerSet: (d) {
                called = true;
                result = d;
              },
              sleepTimerSecondsRemaining: 300, // 5 min left
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Sleep Timer'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel timer (5 min left)'), findsOneWidget);
      await tester.tap(find.text('Cancel timer (5 min left)'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNull);
    },
  );
}
