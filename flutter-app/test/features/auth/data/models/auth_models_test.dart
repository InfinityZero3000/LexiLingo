import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/data/models/auth_models.dart';

void main() {
  group('Auth Models Tests', () {
    group('AuthTokens', () {
      test('should parse from JSON correctly', () {
        // Arrange
        final json = {
          'access_token': 'access_token_value',
          'refresh_token': 'refresh_token_value',
          'token_type': 'bearer',
        };

        // Act
        final tokens = AuthTokens.fromJson(json);

        // Assert
        expect(tokens.accessToken, 'access_token_value');
        expect(tokens.refreshToken, 'refresh_token_value');
        expect(tokens.tokenType, 'bearer');
      });

      test('should generate authorization header correctly', () {
        // Arrange
        final tokens = AuthTokens(
          accessToken: 'test_access_token',
          refreshToken: 'test_refresh_token',
        );

        // Act
        final header = tokens.authorizationHeader;

        // Assert
        expect(header, 'bearer test_access_token');
      });

      test('should use default token type if not provided', () {
        // Arrange
        final json = {
          'access_token': 'access_token_value',
          'refresh_token': 'refresh_token_value',
        };

        // Act
        final tokens = AuthTokens.fromJson(json);

        // Assert
        expect(tokens.tokenType, 'bearer');
      });
    });

    group('LoginResponse', () {
      test('should parse from JSON correctly', () {
        // Arrange
        final json = {
          'access_token': 'access_token_value',
          'refresh_token': 'refresh_token_value',
          'token_type': 'bearer',
          'user_id': 'user-id',
          'email': 'test@example.com',
          'username': 'testuser',
        };

        // Act
        final response = LoginResponse.fromJson(json);

        // Assert
        expect(response.tokens.accessToken, 'access_token_value');
        expect(response.tokens.refreshToken, 'refresh_token_value');
        expect(response.userId, 'user-id');
        expect(response.email, 'test@example.com');
        expect(response.username, 'testuser');
      });
    });

    group('DeviceInfo', () {
      test('should serialize to JSON correctly', () {
        // Arrange
        final deviceInfo = DeviceInfo(
          deviceId: 'device-123',
          deviceType: 'ios',
          deviceName: 'iPhone 15 Pro',
          fcmToken: 'fcm-token-123',
          appVersion: '1.0.0',
          osVersion: 'iOS 17.0',
        );

        // Act
        final json = deviceInfo.toJson();

        // Assert
        expect(json['device_id'], 'device-123');
        expect(json['device_type'], 'ios');
        expect(json['device_name'], 'iPhone 15 Pro');
        expect(json['fcm_token'], 'fcm-token-123');
        expect(json['app_version'], '1.0.0');
        expect(json['os_version'], 'iOS 17.0');
      });

      test('should omit null optional fields in JSON', () {
        // Arrange
        final deviceInfo = DeviceInfo(
          deviceId: 'device-123',
          deviceType: 'android',
        );

        // Act
        final json = deviceInfo.toJson();

        // Assert
        expect(json['device_id'], 'device-123');
        expect(json['device_type'], 'android');
        expect(json.containsKey('device_name'), false);
        expect(json.containsKey('fcm_token'), false);
      });
    });

    group('RegisterRequest', () {
      test('should serialize to JSON correctly', () {
        // Arrange
        final request = RegisterRequest(
          email: 'test@example.com',
          username: 'testuser',
          password: 'password123',
          displayName: 'Test User',
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json['email'], 'test@example.com');
        expect(json['username'], 'testuser');
        expect(json['password'], 'password123');
        expect(json['display_name'], 'Test User');
      });

      test('should omit displayName if null', () {
        // Arrange
        final request = RegisterRequest(
          email: 'test@example.com',
          username: 'testuser',
          password: 'password123',
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json.containsKey('display_name'), false);
      });
    });

    group('LoginRequest', () {
      test('should serialize to JSON correctly', () {
        // Arrange
        final request = LoginRequest(
          email: 'test@example.com',
          password: 'password123',
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json['email'], 'test@example.com');
        expect(json['password'], 'password123');
      });
    });

    group('RefreshTokenRequest', () {
      test('should serialize to JSON correctly', () {
        // Arrange
        final request = RefreshTokenRequest(
          refreshToken: 'refresh_token_value',
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json['refresh_token'], 'refresh_token_value');
      });
    });
  });
}
