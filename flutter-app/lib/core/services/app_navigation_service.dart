import 'package:flutter/material.dart';

class AppNavigationService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> openRoute(String route) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.pushNamed(route);
  }
}
