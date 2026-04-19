import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/firebase_messaging_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';

import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_facebook_usecase.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';

class AuthProvider extends ChangeNotifier {
  final SignInWithGoogleUseCase signInWithGoogleUseCase;
  final SignInWithFacebookUseCase signInWithFacebookUseCase;
  final SignInWithEmailPasswordUseCase signInWithEmailPasswordUseCase;
  final SignOutUseCase signOutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  final RegisterUseCase registerUseCase;
  final AuthRepository authRepository;
  final GoogleSignInService googleSignInService;
  final FacebookSignInService facebookSignInService;

  UserEntity? _user;
  bool _isLoading = false;
  bool _isCheckingAuth = true;
  bool _isJustLoggedIn = false;
  String? _errorMessage;

  AuthProvider({
    required this.signInWithGoogleUseCase,
    required this.signInWithFacebookUseCase,
    required this.signInWithEmailPasswordUseCase,
    required this.signOutUseCase,
    required this.getCurrentUserUseCase,
    required this.registerUseCase,
    required this.authRepository,
    required this.googleSignInService,
    required this.facebookSignInService,
  }) {
    _checkCurrentUser();
  }

  // Getters
  UserEntity? get user => _user;
  UserEntity? get currentUser => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isJustLoggedIn => _isJustLoggedIn;
  String? get errorMessage => _errorMessage;

  // Clear just logged in flag (call after welcome screen)
  void clearJustLoggedIn() {
    _isJustLoggedIn = false;
    notifyListeners();
  }

  // Check current user on app start
  Future<void> _checkCurrentUser() async {
    try {
      _isCheckingAuth = true;
      notifyListeners();

      // Web redirect flow: if we just came back from Google, finish backend
      // sign-in before checking stored session.
      final pendingGoogleIdToken =
          await googleSignInService.consumePendingWebRedirectIdToken();
      if (pendingGoogleIdToken != null) {
        await _authenticateWithGoogleIdToken(pendingGoogleIdToken);
        return;
      }

      // Fast-path: if there are no local tokens, skip network call completely.
      final hasStoredSession = await authRepository.isAuthenticated();
      if (!hasStoredSession) {
        _user = null;
        _errorMessage = null;
        UserScopeService.clearActiveUserId();
        return;
      }

      final result = await getCurrentUserUseCase(
        NoParams(),
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () => Left(AuthFailure('Auth check timed out')),
      );
      result.fold(
        (failure) {
          // Don't show error for AuthFailure (401) - user just not logged in
          if (failure is AuthFailure || failure is UnauthorizedFailure) {
            _errorMessage = null; // Silent - normal state when not logged in
          } else {
            _errorMessage = _getFailureMessage(failure);
          }
          _user = null;
          UserScopeService.clearActiveUserId();
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
      UserScopeService.clearActiveUserId();
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

      // Get real ID token from Google Sign-In
      final idToken = await googleSignInService.signIn();
      if (idToken == GoogleSignInService.redirectInProgressMarker) {
        // Redirect flow has started, browser will navigate away.
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (idToken == null) {
        final signInError = googleSignInService.lastError?.toLowerCase();
        if (signInError == null || signInError.contains('cancelled')) {
          _errorMessage = 'Google sign in was cancelled';
        } else {
          _errorMessage = _parseErrorMessage(googleSignInService.lastError!);
        }
        _isLoading = false;
        notifyListeners();
        return;
      }

      await _authenticateWithGoogleIdToken(idToken);
    } catch (e) {
      debugPrint("Google sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _authenticateWithGoogleIdToken(String idToken) async {
    debugPrint('Google ID token obtained (length: ${idToken.length})');

    final result = await signInWithGoogleUseCase(
      SignInWithGoogleParams(idToken: idToken),
    );

    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _user = null;
        _isJustLoggedIn = false;
      },
      (user) {
        _user = user;
        _errorMessage = null;
        _isJustLoggedIn = true;
        FirebaseMessagingService.instance.registerTokenWithBackend(
          sl<ApiClient>(),
        );
      },
    );
  }

  // Sign in with Facebook
  Future<void> signInWithFacebook() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Get Firebase ID token via Facebook authentication
      final idToken = await facebookSignInService.signIn();
      if (idToken == null) {
        _errorMessage = 'Facebook sign in was cancelled or failed';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final result = await signInWithFacebookUseCase(
        SignInWithFacebookParams(idToken: idToken),
      );

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _user = null;
          _isJustLoggedIn = false;
        },
        (user) {
          _user = user;
          _errorMessage = null;
          _isJustLoggedIn = true;
          // Register FCM token with backend after successful Facebook sign-in
          FirebaseMessagingService.instance.registerTokenWithBackend(
            sl<ApiClient>(),
          );
        },
      );
    } catch (e) {
      debugPrint("Facebook sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
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
          _isJustLoggedIn = false;
        },
        (user) {
          _user = user;
          _errorMessage = null;
          _isJustLoggedIn = true; // Set flag for welcome screen
          // Register FCM token with backend after successful email sign-in
          FirebaseMessagingService.instance.registerTokenWithBackend(
            sl<ApiClient>(),
          );
        },
      );
    } catch (e) {
      debugPrint("Email sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Request password reset link/email.
  Future<bool> requestPasswordReset(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.requestPasswordReset(email);

      return result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          return false;
        },
        (_) {
          _errorMessage = null;
          return true;
        },
      );
    } catch (e) {
      _errorMessage = _parseErrorMessage(e.toString());
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset password with token from email link.
  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.resetPassword(
        token: token,
        newPassword: newPassword,
      );

      return result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          return false;
        },
        (_) {
          _errorMessage = null;
          return true;
        },
      );
    } catch (e) {
      _errorMessage = _parseErrorMessage(e.toString());
      return false;
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
      // Clear stored FCM token so it gets re-registered on next login
      await FirebaseMessagingService.instance.clearRegisteredToken();
      _user = null;
    } catch (e) {
      debugPrint("Sign out error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Register new user
  Future<void> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final params = RegisterParams(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
      );

      final result = await registerUseCase(params);

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _user = null;
          _isJustLoggedIn = false;
        },
        (user) {
          _user = user;
          _errorMessage = null;
          _isJustLoggedIn = true;
        },
      );
    } catch (e) {
      debugPrint("Register error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user profile (display name, avatar)
  Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.updateProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
      );

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          throw Exception(_errorMessage);
        },
        (updatedUser) {
          _user = updatedUser;
          _errorMessage = null;
        },
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit onboarding payload once at the end of onboarding flow.
  Future<void> submitOnboarding(Map<String, dynamic> payload) async {
    final selectedLevel = (payload['level'] as String?)?.toUpperCase();

    final result = await authRepository.updateProfile(
      level: selectedLevel,
      nativeLanguage: 'vi',
      targetLanguage: 'en',
      isOnboardingCompleted: true,
    );

    result.fold(
      (_) {
        // Keep onboarding non-blocking on backend issues.
      },
      (updatedUser) {
        _user = updatedUser;
      },
    );
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Parse error messages to user-friendly format
  String _parseErrorMessage(String error) {
    final normalized = error.toLowerCase();

    if (normalized.contains('timeoutexception') || normalized.contains('timed out')) {
      return 'Server is not responding in time. Please try again in a moment.';
    }
    if (normalized.contains('/users/me failed')) {
      return 'Login succeeded but profile sync failed. Please try again.';
    }
    if (normalized.contains('internal server error')) {
      return 'Server error occurred. Please try again later.';
    }
    if (normalized.contains('google_server_client_id')) {
      return 'Google sign-in config is missing. Please contact support.';
    }

    if (error.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (normalized.contains('cancelled') || normalized.contains('canceled')) {
      return 'Sign in was cancelled.';
    } else if (normalized.contains('email')) {
      return 'Invalid email address.';
    } else if (normalized.contains('password')) {
      return 'Invalid password.';
    } else if (normalized.contains('user-not-found')) {
      return 'No account found with this email.';
    } else if (normalized.contains('wrong-password')) {
      return 'Incorrect password.';
    } else if (normalized.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }

  // Convert Failure to user-friendly message
  String _getFailureMessage(Failure failure) {
    if (failure is AuthFailure) {
      return failure.message;
    } else if (failure is ServerFailure) {
      final normalized = failure.message.toLowerCase();
      if (normalized.contains('timeoutexception') || normalized.contains('timed out')) {
        return 'Server timeout. Please check server status and try again.';
      }
      if (normalized.contains('/users/me failed')) {
        return 'Signed in, but profile sync timed out. Please reopen the app.';
      }
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
