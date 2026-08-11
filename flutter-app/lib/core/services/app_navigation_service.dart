import 'package:flutter/material.dart';

class AppNavigationService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<bool> openRoute(String route, {Object? arguments}) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;

    try {
      await navigator.pushNamed(route, arguments: arguments);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Failed to open route "$route": $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static void returnToRoot() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }
}
