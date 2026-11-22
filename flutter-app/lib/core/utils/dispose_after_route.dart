import 'package:flutter/foundation.dart';

const Duration kRouteExitDuration = Duration(milliseconds: 500);

/// For a caller that must keep reading [notifiers] after the route future
/// resolves. A dialog that can own its controllers should dispose them in its
/// own State instead; this is the fallback when it cannot.
void disposeAfterRoute(Iterable<ChangeNotifier> notifiers) {
  final held = List<ChangeNotifier>.of(notifiers);
  Future<void>.delayed(kRouteExitDuration, () {
    for (final n in held) {
      n.dispose();
    }
  });
}
