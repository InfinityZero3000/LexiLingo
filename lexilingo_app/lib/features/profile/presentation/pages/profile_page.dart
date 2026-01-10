import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
              child: user?.photoUrl == null ? const Icon(Icons.person, size: 50) : null,
            ),
            const SizedBox(height: 16),
            Text(user?.displayName ?? 'Guest User', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 32),
            if (authService.isAuthenticated)
              ElevatedButton(onPressed: authService.signOut, child: const Text('Sign Out'))
            else
              ElevatedButton(onPressed: authService.signIn, child: const Text('Sign In With Google')),
          ],
        ),
      ),
    );
  }
}
