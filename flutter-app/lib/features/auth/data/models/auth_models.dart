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

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    if (value != null) {
      final normalized = value.toString();
      if (normalized.isNotEmpty && normalized != 'null') {
        return normalized;
      }
    }
    throw FormatException('Missing or invalid "$key" in auth response');
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    final normalized = value.toString();
    return normalized == 'null' ? null : normalized;
  }

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: _requiredString(json, 'access_token'),
      refreshToken: _requiredString(json, 'refresh_token'),
      tokenType: _optionalString(json['token_type']) ?? 'bearer',
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
  final String userId;
  final String username;
  final String email;

  const LoginResponse({
    required this.tokens,
    required this.userId,
    required this.username,
    required this.email,
  });

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    if (value != null) {
      final normalized = value.toString();
      if (normalized.isNotEmpty && normalized != 'null') {
        return normalized;
      }
    }
    throw FormatException('Missing or invalid "$key" in login response');
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    final normalized = value.toString();
    return normalized == 'null' ? null : normalized;
  }

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      tokens: AuthTokens(
        accessToken: _requiredString(json, 'access_token'),
        refreshToken: _requiredString(json, 'refresh_token'),
        tokenType: _optionalString(json['token_type']) ?? 'bearer',
      ),
      userId: _requiredString(json, 'user_id'),
      username: _requiredString(json, 'username'),
      email: _requiredString(json, 'email'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': tokens.accessToken,
      'refresh_token': tokens.refreshToken,
      'token_type': tokens.tokenType,
      'user_id': userId,
      'username': username,
      'email': email,
    };
  }
}

/// Device registration/update request
/// From backend-service/app/models/user.py UserDevice
class DeviceInfo {
  final String deviceId;
  final String deviceType; // 'ios', 'android', 'web'
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
      deviceId: LoginResponse._requiredString(json, 'device_id'),
      deviceType: LoginResponse._requiredString(json, 'device_type'),
      deviceName: LoginResponse._optionalString(json['device_name']),
      fcmToken: LoginResponse._optionalString(json['fcm_token']),
      appVersion: LoginResponse._optionalString(json['app_version']),
      osVersion: LoginResponse._optionalString(json['os_version']),
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

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}

/// Token refresh request
class RefreshTokenRequest {
  final String refreshToken;

  const RefreshTokenRequest({required this.refreshToken});

  Map<String, dynamic> toJson() {
    return {'refresh_token': refreshToken};
  }
}
