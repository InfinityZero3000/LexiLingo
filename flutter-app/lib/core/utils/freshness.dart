/// How long a successful load stays good enough for passive reloads (startup
/// fan-out, tab switches). Explicit refreshes pass no `maxAge` and always fetch.
const Duration kPassiveReloadWindow = Duration(seconds: 30);

/// Remembers when a load last succeeded, so a passive reload within `maxAge`
/// can be skipped. Callers must [invalidate] on user switch and mark only
/// after a successful, current-generation load.
class Freshness {
  Freshness({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _at;

  bool isFresh(Duration? maxAge) {
    final at = _at;
    if (maxAge == null || at == null) return false;
    return _clock().difference(at) < maxAge;
  }

  void mark() => _at = _clock();

  void invalidate() => _at = null;
}
