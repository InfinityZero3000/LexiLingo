import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_splash.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// The route a signed-out visitor asked for, replayed once they sign in.
abstract final class PendingRoute {
  static String? name;

  static String? take() {
    final value = name;
    name = null;
    return value;
  }
}

/// Keeps signed-out visitors off learner screens that would only fetch 401s.
///
/// A deep link (web URL) pushes the screen on top of [AuthWrapper], so the
/// guard remembers the route, pops back to the root where the login page
/// lives, and [AuthWrapper] reopens the route after sign-in.
class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _redirecting = false;

  void _redirectToLogin() {
    if (_redirecting) return;
    _redirecting = true;
    final route = ModalRoute.of(context);
    final name = route?.settings.name;
    if (name != null && name != '/' && route?.settings.arguments == null) {
      PendingRoute.name = name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth;
    try {
      auth = Provider.of<AuthProvider>(context);
    } on ProviderNotFoundException {
      return widget.child;
    }

    if (auth.isAuthenticated) {
      _redirecting = false;
      return widget.child;
    }
    if (!auth.isCheckingAuth) _redirectToLogin();
    return const Scaffold(body: AppSplash());
  }
}
