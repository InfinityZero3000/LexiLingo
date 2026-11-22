import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/l10n/relative_time.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';

// No translations are loaded here, so `.tr()` returns the key: the tests
// assert which message was chosen, not its wording.
void main() {
  final now = DateTime(2026, 11, 16, 12);
  String ago(Duration d, {bool coarse = false}) =>
      relativeTime(now.subtract(d), now: now, coarse: coarse);

  group('relativeTime', () {
    test('counts up through minutes, hours, yesterday and days', () {
      expect(ago(const Duration(seconds: 20)), 'datetime.justNow');
      expect(ago(const Duration(minutes: 5)), 'datetime.minutesAgo');
      expect(ago(const Duration(hours: 3)), 'datetime.hoursAgo');
      expect(ago(const Duration(days: 1)), 'datetime.yesterday');
      expect(ago(const Duration(days: 4)), 'datetime.daysAgo');
    });

    test('shows a date after a week unless coarse', () {
      expect(ago(const Duration(days: 10)), isNot(startsWith('datetime.')));
      expect(ago(const Duration(days: 10), coarse: true), 'datetime.weeksAgo');
      expect(ago(const Duration(days: 90), coarse: true), 'datetime.monthsAgo');
      expect(ago(const Duration(days: 400), coarse: true), 'datetime.yearsAgo');
    });

    test('time left switches from hours to days at 24', () {
      expect(timeLeft(5), 'datetime.hoursLeft');
      expect(timeLeft(48), 'datetime.daysLeft');
    });
  });

  group('UiText.failure', () {
    test('an English default becomes the translated message for its type', () {
      expect(
        UiText.failure(const NetworkFailure()).resolve(),
        'errors.networkRetry',
      );
      expect(
        UiText.failure(const ServerFailure()).resolve(),
        'errors.serverRetry',
      );
      expect(
        UiText.failure(const ServerFailure('')).resolve(),
        'errors.serverRetry',
      );
    });

    test("a server's own message is shown as it came", () {
      expect(
        UiText.failure(const ValidationFailure('Email is taken')).resolve(),
        'Email is taken',
      );
    });
  });
}
