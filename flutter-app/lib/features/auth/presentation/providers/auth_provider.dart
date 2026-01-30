import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';

class AuthProvider extends ChangeNotifier {
  final SignInWithGoogleUseCase signInWithGoogleUseCase;
  final SignInWithEmailPasswordUseCase signInWithEmailPasswordUseCase;
  final SignOutUseCase signOutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  
  UserEntity? _user;
  bool _isLoading = false;
  bool _isCheckingAuth = true;
  String? _errorMessage;

  AuthProvider({
    required this.signInWithGoogleUseCase,
    required this.signInWithEmailPasswordUseCase,
    required this.signOutUseCase,
    required this.getCurrentUserUseCase,
  }) {
    _checkCurrentUser();
  }

  // Getters
  UserEntity? get user => _user;
  UserEntity? get currentUser => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  String? get errorMessage => _errorMessage;

  // Check current user on app start
  Future<void> _checkCurrentUser() async {
    try {
      _isCheckingAuth = true;
      notifyListeners();
      
      final result = await getCurrentUserUseCase(NoParams());
      result.fold(
        (failure) {
          // Don't show error for AuthFailure (401) - user just not logged in
          if (failure is AuthFailure || failure is UnauthorizedFailure) {
            _errorMessage = null; // Silent - normal state when not logged in
          } else {
            _errorMessage = _getFailureMessage(failure);
          }
          _user = null;
        },
        (user) {
          _user = user;
          _errorMessage = null;
        },
      );
    } catch (e) {
      debugPrint("Check current user error: $e");
      // Don't show error for auth check failures - user just not logged in
      _errorMessage = null;
      _user = null;
    } finally {
      _isCheckingAuth = false;
      notifyListeners();
    }
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await signInWithGoogleUseCase(
        SignInWithGoogleParams(idToken: ''),  // TODO: Get real idToken from GoogleSignIn
      );
      
      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _user = null;
        },
        (user) {
          _user = user;
          _errorMessage = null;
        },
      );
    } catch (e) {
      debugPrint("Google sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in with email and password
  Future<void> signInWithEmailPassword(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final params = SignInWithEmailPasswordParams(
        email: email,
        password: password,
      );
      
      final result = await signInWithEmailPasswordUseCase(params);
      
      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _user = null;
        },
        (user) {
          _user = user;
          _errorMessage = null;
        },
      );
    } catch (e) {
      debugPrint("Email sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await signOutUseCase(NoParams());
      _user = null;
    } catch (e) {
      debugPrint("Sign out error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Parse error messages to user-friendly format
  String _parseErrorMessage(String error) {
    if (error.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (error.contains('cancelled') || error.contains('canceled')) {
      return 'Sign in was cancelled.';
    } else if (error.contains('email')) {
      return 'Invalid email address.';
    } else if (error.contains('password')) {
      return 'Invalid password.';
    } else if (error.contains('user-not-found')) {
      return 'No account found with this email.';
    } else if (error.contains('wrong-password')) {
      return 'Incorrect password.';
    } else if (error.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }

  // Convert Failure to user-friendly message
  String _getFailureMessage(Failure failure) {
    if (failure is ServerFailure) {
      return failure.message;
    } else if (failure is NetworkFailure) {
      return 'Network error. Please check your internet connection.';
    } else if (failure is CacheFailure) {
      return 'Local storage error.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }
}
