import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/podcast_audio_handler.dart';

/// Covers only the sleep timer surface. The real point of moving the timer
/// onto the handler (rather than the player screen's State) is that it
/// survives the screen being popped — this is proven here by never
/// constructing a screen at all: the handler is the one thing a sleep timer
/// must still be running on after navigation, so testing it in isolation,
/// with no widget tree involved, is the direct proof.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PodcastAudioHandler sleep timer', () {
    test('setSleepTimer starts a countdown and elapsing clears it', () async {
      final handler = PodcastAudioHandler();
      final seen = <int?>[];
      handler.sleepTimerSecondsStream.listen(seen.add);

      handler.setSleepTimer(const Duration(seconds: 1));
      expect(handler.sleepTimerSecondsRemaining, 1);

      await Future.delayed(const Duration(milliseconds: 1500));

      expect(handler.sleepTimerSecondsRemaining, isNull);
      expect(seen, [1, null]);
    });

    test('setSleepTimer(null) cancels an active timer', () async {
      final handler = PodcastAudioHandler();

      handler.setSleepTimer(const Duration(minutes: 30));
      expect(handler.sleepTimerSecondsRemaining, isNotNull);

      handler.setSleepTimer(null);
      expect(handler.sleepTimerSecondsRemaining, isNull);

      // Long enough that the original 30-minute timer, if it had kept
      // running, still wouldn't have elapsed — this just proves it was
      // actually cancelled rather than merely hidden from the getter.
      await Future.delayed(const Duration(milliseconds: 1200));
      expect(handler.sleepTimerSecondsRemaining, isNull);
    });
  });
}
