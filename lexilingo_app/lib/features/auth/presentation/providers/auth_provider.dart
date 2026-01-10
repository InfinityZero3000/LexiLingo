import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';

class AuthProvider extends ChangeNotifier {
  final SignInWithGoogleUseCase signInWithGoogleUseCase;
  final SignOutUseCase signOutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  UserEntity? _user;

  AuthProvider({
    required this.signInWithGoogleUseCase,
    required this.signOutUseCase,
    required this.getCurrentUserUseCase,
  }) {
    _checkCurrentUser();
  }

  UserEntity? get user => _user;
  bool get isAuthenticated => _user != null;

  Future<void> _checkCurrentUser() async {
    _user = await getCurrentUserUseCase(NoParams());
    notifyListeners();
  }

  Future<void> signIn() async {
    try {
      _user = await signInWithGoogleUseCase(NoParams());
      notifyListeners();
    } catch (e) {
      debugPrint("Sign in error: $e");
    }
  }

  Future<void> signOut() async {
    await signOutUseCase(NoParams());
    _user = null;
    notifyListeners();
  }
}
