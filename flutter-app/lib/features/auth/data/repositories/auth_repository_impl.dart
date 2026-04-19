import 'package:dartz/dartz.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/response_models.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_backend_datasource.dart';
import '../models/auth_models.dart';

/// Auth repository implementation using backend API
class AuthRepositoryImpl implements AuthRepository {
  final AuthBackendDataSource backendDataSource;

  AuthRepositoryImpl({required this.backendDataSource});

  @override
  Future<Either<Failure, UserEntity>> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    try {
      final user = await backendDataSource.register(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
      );
      return Right(user);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Registration failed: $e'));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> login({
    required String email,
    required String password,
  }) async {
    try {
      // Login and save tokens (done in datasource)
      final loginResponse = await backendDataSource.login(
        email: email,
        password: password,
      );
      // Fetch full user profile after login
      UserEntity user;
      try {
        user = await backendDataSource.getCurrentUser();
      } on ServerException {
        // Backend profile endpoint can timeout while auth succeeds.
        user = _buildFallbackUser(loginResponse);
      }
      return Right(user);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on UnauthorizedException catch (_) {
      return Left(AuthFailure('Invalid email or password.'));
    } on AuthException catch (_) {
      return Left(AuthFailure('Invalid email or password.'));
    } catch (e) {
      return Left(ServerFailure('Login failed: $e'));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> loginWithGoogle(String idToken) async {
    try {
      // Login and save tokens (done in datasource)
      final loginResponse = await backendDataSource.loginWithGoogle(idToken);
      // Fetch full user profile after login
      UserEntity user;
      try {
        user = await backendDataSource.getCurrentUser();
      } on ServerException {
        user = _buildFallbackUser(loginResponse, provider: 'google');
      }
      return Right(user);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } on AuthException catch (_) {
      return Left(AuthFailure('Google login failed'));
    } catch (e) {
      return Left(AuthFailure('Google login failed: $e'));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> loginWithFacebook(
    String firebaseIdToken,
  ) async {
    try {
      // Login and save tokens
      final loginResponse = await backendDataSource.loginWithFacebook(
        firebaseIdToken,
      );
      // Fetch full user profile after login
      UserEntity user;
      try {
        user = await backendDataSource.getCurrentUser();
      } on ServerException {
        user = _buildFallbackUser(loginResponse, provider: 'facebook');
      }
      return Right(user);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } on AuthException catch (_) {
      return Left(AuthFailure('Facebook login failed'));
    } catch (e) {
      return Left(AuthFailure('Facebook login failed: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await backendDataSource.logout();
      return const Right(null);
    } catch (e) {
      // Even if logout fails, consider it successful locally
      return const Right(null);
    }
  }

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async {
    try {
      final user = await backendDataSource.getCurrentUser();
      return Right(user);
    } on UnauthorizedException catch (_) {
      // User not logged in - this is expected, not an error
      return Left(AuthFailure('Not authenticated'));
    } on AuthException catch (_) {
      return Left(AuthFailure('Not authenticated'));
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get current user: $e'));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? nativeLanguage,
    String? targetLanguage,
    String? level,
    bool? isOnboardingCompleted,
  }) async {
    try {
      final user = await backendDataSource.updateProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
        nativeLanguage: nativeLanguage,
        targetLanguage: targetLanguage,
        level: level,
        isOnboardingCompleted: isOnboardingCompleted,
      );
      return Right(user);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Profile update failed: $e'));
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    return await backendDataSource.isAuthenticated();
  }

  @override
  Future<Either<Failure, void>> verifyEmail(String token) async {
    try {
      await backendDataSource.verifyEmail(token);
      return const Right(null);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Email verification failed: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> requestPasswordReset(String email) async {
    try {
      await backendDataSource.requestPasswordReset(email);
      return const Right(null);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Password reset request failed: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      await backendDataSource.resetPassword(
        token: token,
        newPassword: newPassword,
      );
      return const Right(null);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Password reset failed: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await backendDataSource.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return const Right(null);
    } on ApiErrorException catch (e) {
      return Left(_mapApiErrorToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Password change failed: $e'));
    }
  }

  /// Map API error codes to specific failures
  Failure _mapApiErrorToFailure(ApiErrorException e) {
    switch (e.code) {
      case ErrorCodes.authInvalid:
      case ErrorCodes.authExpired:
      case ErrorCodes.authMissing:
        return AuthFailure(e.message);

      case ErrorCodes.validationError:
      case ErrorCodes.invalidInput:
      case ErrorCodes.missingField:
        return ValidationFailure(e.message);

      case ErrorCodes.notFound:
        return NotFoundFailure(e.message);

      case ErrorCodes.alreadyExists:
        return ConflictFailure(e.message);

      case ErrorCodes.rateLimited:
        return RateLimitFailure(e.message);

      case ErrorCodes.permissionDenied:
        return PermissionFailure(e.message);

      default:
        return ServerFailure(e.message);
    }
  }

  UserEntity _buildFallbackUser(
    LoginResponse response, {
    String provider = 'local',
  }) {
    final now = DateTime.now();
    return UserEntity(
      id: response.userId,
      email: response.email,
      username: response.username,
      displayName: response.username,
      provider: provider,
      createdAt: now,
      updatedAt: now,
    );
  }
}
