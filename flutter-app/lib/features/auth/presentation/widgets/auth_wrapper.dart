import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import '../providers/auth_provider.dart';
import '../../../home/presentation/pages/main_screen.dart';
import '../pages/login_page.dart';
import '../pages/welcome_page.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _showWelcome = false;
  bool _wasAuthenticated = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Show loading while checking auth state
    if (authProvider.isCheckingAuth) {
      return const Scaffold(
        body: LoadingScreen(message: 'Checking authentication...'),
      );
    }

    // Detect when user just logged in
    if (authProvider.isAuthenticated && !_wasAuthenticated) {
      _wasAuthenticated = true;
      // Only show welcome for fresh logins (not app restarts with existing session)
      if (authProvider.isJustLoggedIn) {
        _showWelcome = true;
      }
    }

    // Reset state when user logs out
    if (!authProvider.isAuthenticated && _wasAuthenticated) {
      _wasAuthenticated = false;
      _showWelcome = false;
    }

    // Show welcome page after login
    if (authProvider.isAuthenticated && _showWelcome) {
      return WelcomePage(
        userName: authProvider.currentUser?.displayName ?? 
                  authProvider.currentUser?.username,
        onComplete: () {
          setState(() {
            _showWelcome = false;
          });
          // Reset the just logged in flag
          authProvider.clearJustLoggedIn();
        },
      );
    }

    // Show main screen if authenticated, otherwise show login
    return authProvider.isAuthenticated 
        ? const MainScreen() 
        : const LoginPage();
  }
}
