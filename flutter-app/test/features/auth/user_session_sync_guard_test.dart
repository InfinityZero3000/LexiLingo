import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Root providers that hold no learner data, with the reason. Anything else in
/// main.dart's MultiProvider must be reset by UserSessionSync.afterSignOut: an
/// app-lifetime provider that is not is how one account's gems, chats and words
/// ended up on the next account's screen.
const _notReset = <String, String>{
  'AuthProvider':
      'is the session itself; signing out is what triggers the reset',
  'SettingsProvider':
      'theme and language are device choices; per-user settings are reloaded by loadSettings on sign-in',
  'TtsSettingsProvider': 'device-level speech speed and voice',
  'PromoBannerProvider':
      'public banners; the dismissed ids are per device, not per learner',
};

Set<String> _rootProviders(String main) {
  final start = main.indexOf('MultiProvider(');
  final end = main.indexOf('child: Consumer<SettingsProvider>', start);
  expect(
    start,
    greaterThan(-1),
    reason: 'MultiProvider not found in main.dart',
  );
  expect(end, greaterThan(start), reason: 'MultiProvider block not found');
  return RegExp(
    r'di\.sl<(\w+Provider)>\(\)',
  ).allMatches(main.substring(start, end)).map((m) => m.group(1)!).toSet();
}

Set<String> _resetOnSignOut(String sync) {
  final start = sync.indexOf('static void afterSignOut');
  final end = sync.indexOf('/// Singletons outside the widget tree', start);
  expect(start, greaterThan(-1));
  expect(end, greaterThan(start));
  return RegExp(
    r'_reset<(\w+)>\(',
  ).allMatches(sync.substring(start, end)).map((m) => m.group(1)!).toSet();
}

void main() {
  final main = File('lib/main.dart').readAsStringSync();
  final sync = File(
    'lib/features/auth/presentation/user_session_sync.dart',
  ).readAsStringSync();

  test('every root provider is reset on sign-out or explicitly exempt', () {
    final roots = _rootProviders(main);
    final reset = _resetOnSignOut(sync);

    expect(roots.length, greaterThan(20), reason: 'root provider scan broke');
    final missing = roots.difference(reset).difference(_notReset.keys.toSet());
    expect(
      missing,
      isEmpty,
      reason:
          'Reset these in UserSessionSync.afterSignOut, or add them to _notReset '
          'with a reason: $missing',
    );
  });

  test('the exemptions and the resets are real', () {
    final roots = _rootProviders(main);
    final reset = _resetOnSignOut(sync);

    expect(
      _notReset.keys.toSet().difference(roots),
      isEmpty,
      reason: 'exempt providers that are no longer root providers',
    );
    expect(
      _notReset.keys.toSet().intersection(reset),
      isEmpty,
      reason: 'a provider is both reset and exempt',
    );
    expect(
      reset.difference(roots),
      isEmpty,
      reason: 'reset providers that are not root providers in main.dart',
    );
  });

  test('singletons that hold learner data are reset on sign-out', () {
    // GetIt singletons have no marker for "holds per-user data", and scanning
    // their fields flags plain config as often as real state. So this list is
    // kept by hand: add a service here when it caches what a learner did, and
    // reset it in UserSessionSync._resetServices.
    const holdLearnerData = [
      'KnownWordsService',
      'ListeningHistoryRecorder',
      'PodcastAudioHandler',
    ];
    final start = sync.indexOf('static void _resetServices');
    final end = sync.indexOf('static void _reset<', start);
    expect(start, greaterThan(-1));
    final body = sync.substring(start, end);

    for (final type in holdLearnerData) {
      expect(body, contains('sl<$type>()'), reason: '$type is not reset');
    }
  });
}
