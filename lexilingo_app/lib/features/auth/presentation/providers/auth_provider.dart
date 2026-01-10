import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository repository;
  UserEntity? _user;

  AuthProvider({required this.repository}) {
    _checkCurrentUser();
  }

  UserEntity? get user => _user;
  bool get isAuthenticated => _user != null;

  Future<void> _checkCurrentUser() async {
    _user = await repository.getCurrentUser();
    notifyListeners();
  }

  Future<void> signIn() async {
    try {
      _user = await repository.signInWithGoogle();
      notifyListeners();
    } catch (e) {
      debugPrint("Sign in error: $e");
    }
  }

  Future<void> signOut() async {
    await repository.signOut();
    _user = null;
    notifyListeners();
  }
}
