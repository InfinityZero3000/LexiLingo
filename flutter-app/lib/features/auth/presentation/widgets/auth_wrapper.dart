import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../home/presentation/pages/main_screen.dart';
import '../pages/login_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Show loading while checking auth state
    if (authProvider.isCheckingAuth) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show main screen if authenticated, otherwise show login
    return authProvider.isAuthenticated 
        ? const MainScreen() 
        : const LoginPage();
  }
}
