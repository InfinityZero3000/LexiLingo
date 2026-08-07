import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user_entity.dart';

/// Auth repository interface
/// Using Either for error handling (functional approach)
abstract class AuthRepository {
  /// Register new user
  Future<Either<Failure, UserEntity>> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  });

  /// Login with email and password
  Future<Either<Failure, UserEntity>> login({
    required String email,
    required String password,
  });

  /// Login with Google OAuth
  Future<Either<Failure, UserEntity>> loginWithGoogle(String idToken);

  /// Login with Facebook OAuth (via Firebase)
  Future<Either<Failure, UserEntity>> loginWithFacebook(String firebaseIdToken);

  /// Logout current user
  Future<Either<Failure, void>> logout();

  /// Get current authenticated user
  Future<Either<Failure, UserEntity>> getCurrentUser();

  /// Update user profile
  Future<Either<Failure, UserEntity>> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? nativeLanguage,
    String? targetLanguage,
    String? level,
    String? goal,
    String? interest,
    bool? isOnboardingCompleted,
  });

  /// Check if user is authenticated
  Future<bool> isAuthenticated();

  /// Verify email with token
  Future<Either<Failure, void>> verifyEmail(String token);

  /// Resend verification email
  Future<Either<Failure, void>> resendVerificationEmail(String email);

  /// Request password reset
  Future<Either<Failure, void>> requestPasswordReset(String email);

  /// Reset password with token
  Future<Either<Failure, void>> resetPassword({
    required String token,
    required String newPassword,
  });

  /// Change password (authenticated user)
  Future<Either<Failure, void>> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}
