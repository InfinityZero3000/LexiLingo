import '../../../../core/network/api_client.dart';
import '../../../../core/network/response_models.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';
import 'device_manager.dart';
import 'token_storage.dart';

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
      body: request.toJson(),
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
    final request = LoginRequest(
      email: email,
      password: password,
    );

    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/login',
      body: request.toJson(),
      fromJson: (data) => data as Map<String, dynamic>,
    );

    final loginResponse = LoginResponse.fromJson(envelope.data);
    
    // Save tokens securely
    await tokenStorage.saveTokens(loginResponse.tokens);
    
    // Register device with FCM token
    await _registerDevice();

    return loginResponse;
  }

  /// Login with Google (OAuth)
  /// POST /auth/google
  Future<LoginResponse> loginWithGoogle(String idToken) async {
    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/google',
      body: {'id_token': idToken},
      fromJson: (data) => data as Map<String, dynamic>,
    );

    final loginResponse = LoginResponse.fromJson(envelope.data);
    
    await tokenStorage.saveTokens(loginResponse.tokens);
    await _registerDevice();

    return loginResponse;
  }

  /// Refresh access token using refresh token
  /// POST /auth/refresh-token
  Future<AuthTokens> refreshToken(String refreshToken) async {
    final request = RefreshTokenRequest(refreshToken: refreshToken);

    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/refresh-token',
      body: request.toJson(),
      fromJson: (data) => data as Map<String, dynamic>,
    );

    final tokens = AuthTokens.fromJson(envelope.data);
    
    // Update stored tokens (token rotation)
    await tokenStorage.saveTokens(tokens);

    return tokens;
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
  /// GET /auth/me
  Future<UserModel> getCurrentUser() async {
    final envelope = await apiClient.getEnvelope<Map<String, dynamic>>(
      '/auth/me',
      fromJson: (data) => data as Map<String, dynamic>,
    );

    return UserModel.fromJson(envelope.data);
  }

  /// Update user profile
  /// PUT /auth/me
  Future<UserModel> updateProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    final envelope = await apiClient.postEnvelope<Map<String, dynamic>>(
      '/auth/me',
      body: {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      },
      fromJson: (data) => data as Map<String, dynamic>,
    );

    return UserModel.fromJson(envelope.data);
  }

  /// Register device for push notifications
  /// POST /devices
  Future<void> _registerDevice() async {
    try {
      final deviceInfo = await deviceManager.getDeviceInfo();
      await apiClient.post('/devices', body: deviceInfo.toJson());
    } catch (e) {
      // Device registration is not critical, log but don't fail
      print('Device registration failed: $e');
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
      print('FCM token update failed: $e');
    }
  }

  /// Check if user is authenticated (has valid tokens)
  Future<bool> isAuthenticated() async {
    return await tokenStorage.hasTokens();
  }

  /// Verify email with token
  /// POST /auth/verify-email
  Future<void> verifyEmail(String token) async {
    await apiClient.post('/auth/verify-email', body: {'token': token});
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
      body: {
        'token': token,
        'new_password': newPassword,
      },
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
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }
}
