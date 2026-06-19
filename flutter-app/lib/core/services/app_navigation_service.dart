import 'package:flutter/material.dart';

class AppNavigationService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> openRoute(String route, {Object? arguments}) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.pushNamed(route, arguments: arguments);
  }

  static void returnToRoot() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }
}
