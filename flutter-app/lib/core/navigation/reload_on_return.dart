import 'package:flutter/widgets.dart';
import 'package:lexilingo_app/core/services/app_navigation_service.dart';

/// Reloads a screen when it is uncovered again.
///
/// Awaiting `Navigator.push` is not enough after a lesson: "Next lesson"
/// replaces the session route, which completes that future while the next
/// lesson is still being played.
mixin ReloadOnReturn<T extends StatefulWidget> on State<T>
    implements RouteAware {
  void reload();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      AppNavigationService.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    AppNavigationService.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => reload();

  @override
  void didPop() {}

  @override
  void didPush() {}

  @override
  void didPushNext() {}
}
