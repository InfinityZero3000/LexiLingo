import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/sleep_timer_countdown.dart';

void main() {
  group('SleepTimerCountdown', () {
    test('calls onElapsed exactly once after the countdown reaches zero', () async {
      final countdown = SleepTimerCountdown();
      var elapsedCalls = 0;
      final ticks = <int>[];

      countdown.start(
        duration: const Duration(seconds: 2),
        onTick: ticks.add,
        onElapsed: () => elapsedCalls++,
      );

      expect(ticks, [2]); // fires immediately with the starting value
      expect(countdown.isActive, isTrue);

      await Future.delayed(const Duration(milliseconds: 2500));

      expect(elapsedCalls, 1);
      expect(ticks, [2, 1]);
      expect(countdown.isActive, isFalse);
    });

    test('cancel stops ticking and prevents onElapsed from firing', () async {
      final countdown = SleepTimerCountdown();
      var elapsedCalls = 0;

      countdown.start(
        duration: const Duration(seconds: 1),
        onTick: (_) {},
        onElapsed: () => elapsedCalls++,
      );
      countdown.cancel();

      await Future.delayed(const Duration(milliseconds: 1500));

      expect(elapsedCalls, 0);
      expect(countdown.isActive, isFalse);
    });

    test('start replaces a running countdown instead of stacking', () async {
      final countdown = SleepTimerCountdown();
      var elapsedCalls = 0;

      countdown.start(
        duration: const Duration(seconds: 1),
        onTick: (_) {},
        onElapsed: () => elapsedCalls++,
      );
      // Restart with a longer duration before the first one would elapse.
      countdown.start(
        duration: const Duration(seconds: 2),
        onTick: (_) {},
        onElapsed: () => elapsedCalls++,
      );

      await Future.delayed(const Duration(milliseconds: 2500));

      expect(elapsedCalls, 1);
    });
  });
}
