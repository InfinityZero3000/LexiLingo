import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
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
      // Load user settings when authenticated
      final userId = authProvider.currentUser?.id;
      if (userId != null) {
        context.read<SettingsProvider>().loadSettings(userId);
      }
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

    // Determine which page to show
    Widget currentPage;
    if (authProvider.isAuthenticated && _showWelcome) {
      currentPage = WelcomePage(
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
    } else if (authProvider.isAuthenticated) {
      currentPage = const MainScreen();
    } else {
      currentPage = const LoginPage();
    }

    // Use AnimatedSwitcher for smooth transitions between pages
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        // Fade + Scale + Slide transition
        final fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ));

        final scaleAnimation = Tween<double>(
          begin: 0.95,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));

        final slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));

        return FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(
            scale: scaleAnimation,
            child: SlideTransition(
              position: slideAnimation,
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          authProvider.isAuthenticated 
              ? (_showWelcome ? 'welcome' : 'main') 
              : 'login'
        ),
        child: currentPage,
      ),
    );
  }
}
