/// Authentication token model matching backend response
/// From backend-service/app/schemas/auth.py
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String tokenType;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'bearer',
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': tokenType,
    };
  }

  /// Get authorization header value
  String get authorizationHeader => '$tokenType $accessToken';
}

/// Login response containing user and tokens
/// From backend-service/app/routes/auth.py
class LoginResponse {
  final AuthTokens tokens;
  final dynamic user;  // Will be UserModel

  const LoginResponse({
    required this.tokens,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      tokens: AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
      ),
      user: json['user'],  // Will be parsed as UserModel externally
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': tokens.accessToken,
      'refresh_token': tokens.refreshToken,
      'token_type': tokens.tokenType,
      'user': user,
    };
  }
}

/// Device registration/update request
/// From backend-service/app/models/user.py UserDevice
class DeviceInfo {
  final String deviceId;
  final String deviceType;  // 'ios', 'android', 'web'
  final String? deviceName;
  final String? fcmToken;
  final String? appVersion;
  final String? osVersion;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceType,
    this.deviceName,
    this.fcmToken,
    this.appVersion,
    this.osVersion,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String,
      deviceType: json['device_type'] as String,
      deviceName: json['device_name'] as String?,
      fcmToken: json['fcm_token'] as String?,
      appVersion: json['app_version'] as String?,
      osVersion: json['os_version'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'device_type': deviceType,
      if (deviceName != null) 'device_name': deviceName,
      if (fcmToken != null) 'fcm_token': fcmToken,
      if (appVersion != null) 'app_version': appVersion,
      if (osVersion != null) 'os_version': osVersion,
    };
  }
}

/// Registration request model
class RegisterRequest {
  final String email;
  final String username;
  final String password;
  final String? displayName;

  const RegisterRequest({
    required this.email,
    required this.username,
    required this.password,
    this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'username': username,
      'password': password,
      if (displayName != null) 'display_name': displayName,
    };
  }
}

/// Login request model
class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
    };
  }
}

/// Token refresh request
class RefreshTokenRequest {
  final String refreshToken;

  const RefreshTokenRequest({
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'refresh_token': refreshToken,
    };
  }
}
