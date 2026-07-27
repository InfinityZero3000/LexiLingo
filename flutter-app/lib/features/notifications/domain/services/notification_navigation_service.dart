import 'dart:async';

import 'package:lexilingo_app/core/services/app_navigation_service.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';

class NotificationNavigationService {
  const NotificationNavigationService._();

  static void open(NotificationEntity notification) {
    if (notification.opensRoot) {
      AppNavigationService.returnToRoot();
      return;
    }

    final route = notification.destinationRoute;
    if (route == null) {
      AppNavigationService.returnToRoot();
      return;
    }

    unawaited(_openOrReturnToRoot(route));
  }

  static Future<void> _openOrReturnToRoot(String route) async {
    final opened = await AppNavigationService.openRoute(route);
    if (!opened) {
      AppNavigationService.returnToRoot();
    }
  }
}
