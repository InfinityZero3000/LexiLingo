import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/user_scope_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';
import 'device_manager.dart';
import 'token_storage.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';

const _tag = 'AuthBackendDataSource';

/// Auth remote datasource using backend API
/// Replaces Firebase auth with custom backend authentication
class AuthBackendDataSource {
  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final DeviceManager deviceManager;

  AuthBackendDataSource({
    required this.apiClient,
    required this.tokenStorage,
    required this.deviceManager,
  });

  /// Register new user with email and password
  /// POST /auth/register
  Future<UserModel> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    final request = RegisterRequest(
      email: email,
      username: username,
      password: password,
      displayName: displayName,
    );

    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/register',
      // The verification email goes out before onboarding saves the native
      // language, so it is written in the UI language instead.
      body: {...request.toJson(), 'locale': await LocaleService.getSavedLocale()},
      fromJson: (data) => data as Map<String, dynamic>,
    );

    return UserModel.fromJson(envelope.data);
  }

  /// Login with email and password
  /// POST /auth/login
  /// Returns tokens and user data
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    logDebug(_tag, 'Starting login for $email');

    final request = LoginRequest(email: email, password: password);

    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/login',
      body: request.toJson(),
      fromJson: (data) => data as Map<String, dynamic>,
    );

    logDebug(_tag, 'Login response received');
    final loginResponse = LoginResponse.fromJson(envelope.data);
    logDebug(
      _tag,
      'Token parsed, length: ${loginResponse.tokens.accessToken.length}',
    );

    // Save tokens securely
    await tokenStorage.saveTokens(loginResponse.tokens);
    await UserScopeService.setActiveUserId(loginResponse.userId);
    logDebug(_tag, 'Tokens saved, now registering device...');

    // Register device with FCM token
    await _registerDevice();
    logInfo(_tag, 'Login complete');

    return loginResponse;
  }

  /// Login with Google (OAuth)
  /// POST /auth/google
  Future<LoginResponse> loginWithGoogle(String idToken) async {
    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/google',
      body: {'id_token': idToken, 'source': 'app'},
      fromJson: (data) => data as Map<String, dynamic>,
    );

    final loginResponse = LoginResponse.fromJson(envelope.data);

    await tokenStorage.saveTokens(loginResponse.tokens);
    await UserScopeService.setActiveUserId(loginResponse.userId);
    await _registerDevice();

    return loginResponse;
  }

  /// Login with Facebook (via Firebase)
  /// POST /auth/facebook
  Future<LoginResponse> loginWithFacebook(String firebaseIdToken) async {
    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/facebook',
      body: {'id_token': firebaseIdToken, 'source': 'app'},
      fromJson: (data) => data as Map<String, dynamic>,
    );

    final loginResponse = LoginResponse.fromJson(envelope.data);

    await tokenStorage.saveTokens(loginResponse.tokens);
    await UserScopeService.setActiveUserId(loginResponse.userId);
    await _registerDevice();

    return loginResponse;
  }

  /// POST /auth/facebook/link
  Future<void> linkFacebook(String firebaseIdToken) async {
    await apiClient.post(
      '/auth/facebook/link',
      body: {'id_token': firebaseIdToken},
    );
  }

  /// Logout user
  /// POST /auth/logout
  Future<void> logout() async {
    try {
      await apiClient.post('/auth/logout');
    } catch (e) {
      // Even if logout fails, clear local tokens
    } finally {
      await tokenStorage.clearTokens();
    }
  }

  /// Get current user profile
  /// GET /users/me
  Future<UserModel> getCurrentUser() async {
    logDebug(_tag, 'Getting current user...');
    final envelope = await apiClient.getEnvelope<Map<String, dynamic>>(
      '/users/me',
      fromJson: (data) => data as Map<String, dynamic>,
    );
    logDebug(_tag, 'User received: ${envelope.data['email']}');

    final userModel = UserModel.fromJson(envelope.data);
    await UserScopeService.setActiveUserId(userModel.id);
    await _rememberUser(envelope.data);

    return userModel;
  }

  /// The learner saved by the last successful [getCurrentUser] or
  /// [updateProfile]; null when none, or when it no longer parses.
  Future<UserModel?> getCachedUser() async {
    try {
      final raw = await tokenStorage.readSessionUser();
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? UserModel.fromJson(decoded)
          : null;
    } catch (e) {
      logWarn(_tag, 'Cached session user unreadable: $e');
      return null;
    }
  }

  Future<void> _rememberUser(Map<String, dynamic> json) async {
    try {
      await tokenStorage.saveSessionUser(jsonEncode(json));
    } catch (e) {
      logWarn(_tag, 'Could not cache session user: $e');
    }
  }

  /// Update user profile
  /// PUT /users/me
  Future<UserModel> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? nativeLanguage,
    String? lexiReplyLanguage,
    String? targetLanguage,
    String? level,
    String? goal,
    String? interest,
    bool? isOnboardingCompleted,
  }) async {
    final envelope = await apiClient.putEnvelope<Map<String, dynamic>>(
      '/users/me',
      body: {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (nativeLanguage != null) 'native_language': nativeLanguage,
        if (lexiReplyLanguage != null) 'lexi_reply_language': lexiReplyLanguage,
        if (targetLanguage != null) 'target_language': targetLanguage,
        if (level != null) 'level': level,
        if (goal != null) 'goal': goal,
        if (interest != null) 'interest': interest,
        if (isOnboardingCompleted != null)
          'is_onboarding_completed': isOnboardingCompleted,
      },
      fromJson: (data) => data as Map<String, dynamic>,
    );

    final updated = UserModel.fromJson(envelope.data);
    await _rememberUser(envelope.data);
    return updated;
  }

  /// Upload a JPEG/PNG/WebP picked on the device as the avatar
  /// POST /users/me/avatar
  Future<UserModel> uploadAvatar({
    required Uint8List bytes,
    required String filename,
  }) async {
    final data = await apiClient.postMultipart(
      '/users/me/avatar',
      fileField: 'file',
      fileBytes: bytes,
      filename: filename,
    );
    return UserModel.fromJson(data);
  }

  /// Register device for push notifications
  /// POST /devices
  Future<void> _registerDevice() async {
    try {
      final deviceInfo = await deviceManager.getDeviceInfo();
      await apiClient.post('/devices', body: deviceInfo.toJson());
    } catch (e) {
      // Device registration is not critical, log but don't fail
      logWarn(_tag, 'Device registration failed: $e');
    }
  }

  /// Update device FCM token
  /// PUT /devices/{device_id}
  Future<void> updateDeviceFCMToken(String fcmToken) async {
    try {
      final deviceInfo = await deviceManager.getDeviceInfo();
      await apiClient.post(
        '/devices/${deviceInfo.deviceId}',
        body: {'fcm_token': fcmToken},
      );
    } catch (e) {
      logWarn(_tag, 'FCM token update failed: $e');
    }
  }

  /// Check if user is authenticated (has valid tokens)
  Future<bool> isAuthenticated() async {
    return await tokenStorage.hasTokens();
  }

  /// Verify email with token
  /// POST /auth/verify-email
  Future<LoginResponse?> verifyEmail(String token) async {
    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/verify-email',
      body: {'token': token},
      fromJson: (data) => data as Map<String, dynamic>,
    );
    // The first verification also returns a session shaped like /auth/login; a link that was
    // already used returns none. Saved exactly as a login would be.
    final data = envelope.data;
    final accessToken = data['access_token'];
    if (accessToken is! String || accessToken.isEmpty) return null;
    final session = LoginResponse.fromJson(data);
    await tokenStorage.saveTokens(session.tokens);
    await UserScopeService.setActiveUserId(session.userId);
    await _registerDevice();
    return session;
  }

  /// Resend verification email
  /// POST /auth/resend-verification
  Future<void> resendVerificationEmail(String email) async {
    await apiClient.post('/auth/resend-verification', body: {'email': email});
  }

  /// Request password reset
  /// POST /auth/forgot-password
  Future<void> requestPasswordReset(String email) async {
    await apiClient.post('/auth/forgot-password', body: {'email': email});
  }

  /// Reset password with token
  /// POST /auth/reset-password
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await apiClient.post(
      '/auth/reset-password',
      body: {'token': token, 'new_password': newPassword},
    );
  }

  /// Change password (authenticated user)
  /// POST /auth/change-password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await apiClient.post(
      '/auth/change-password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }
}
