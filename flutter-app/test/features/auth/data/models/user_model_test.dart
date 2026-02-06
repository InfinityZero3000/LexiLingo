import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/data/models/user_model.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';

void main() {
  group('UserModel Tests', () {
    final testJson = {
      'id': '123e4567-e89b-12d3-a456-426614174000',
      'email': 'test@example.com',
      'username': 'testuser',
      'display_name': 'Test User',
      'avatar_url': 'https://example.com/avatar.jpg',
      'provider': 'local',
      'is_verified': true,
      'level': 'B1',
      'xp': 500,
      'current_streak': 7,
      'last_login': '2026-01-24T10:00:00Z',
      'last_login_ip': '192.168.1.1',
      'created_at': '2026-01-20T10:00:00Z',
      'updated_at': '2026-01-24T10:00:00Z',
    };

    test('should parse from JSON correctly', () {
      // Act
      final user = UserModel.fromJson(testJson);

      // Assert
      expect(user.id, '123e4567-e89b-12d3-a456-426614174000');
      expect(user.email, 'test@example.com');
      expect(user.username, 'testuser');
      expect(user.displayName, 'Test User');
      expect(user.avatarUrl, 'https://example.com/avatar.jpg');
      expect(user.provider, 'local');
      expect(user.isVerified, true);
      expect(user.level, 'B1');
      expect(user.xp, 500);
      expect(user.currentStreak, 7);
      expect(user.lastLoginIp, '192.168.1.1');
    });

    test('should serialize to JSON correctly', () {
      // Arrange
      final user = UserModel(
        id: 'test-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        provider: 'local',
        isVerified: false,
        level: 'A1',
        xp: 0,
        currentStreak: 0,
        createdAt: DateTime.parse('2026-01-24T10:00:00Z'),
      );

      // Act
      final json = user.toJson();

      // Assert
      expect(json['id'], 'test-id');
      expect(json['email'], 'test@example.com');
      expect(json['username'], 'testuser');
      expect(json['display_name'], 'Test User');
      expect(json['provider'], 'local');
      expect(json['is_verified'], false);
      expect(json['level'], 'A1');
      expect(json['xp'], 0);
    });

    test('should handle null optional fields', () {
      // Arrange
      final jsonWithNulls = {
        'id': 'test-id',
        'email': 'test@example.com',
        'username': 'testuser',
        'display_name': 'Test User',
        'avatar_url': null,
        'provider': 'local',
        'is_verified': false,
        'level': 'A1',
        'xp': 0,
        'current_streak': 0,
        'last_login': null,
        'last_login_ip': null,
        'created_at': '2026-01-24T10:00:00Z',
        'updated_at': null,
      };

      // Act
      final user = UserModel.fromJson(jsonWithNulls);

      // Assert
      expect(user.avatarUrl, null);
      expect(user.lastLogin, null);
      expect(user.lastLoginIp, null);
      expect(user.updatedAt, null);
    });

    test('should convert from entity correctly', () {
      // Arrange
      final entity = UserEntity(
        id: 'test-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        provider: 'google',
        isVerified: true,
        level: 'B2',
        xp: 1000,
        currentStreak: 10,
        createdAt: DateTime.parse('2026-01-24T10:00:00Z'),
      );

      // Act
      final model = UserModel.fromEntity(entity);

      // Assert
      expect(model.id, entity.id);
      expect(model.email, entity.email);
      expect(model.username, entity.username);
      expect(model.provider, 'google');
      expect(model.level, 'B2');
      expect(model.xp, 1000);
    });

    test('should use default values for missing optional fields', () {
      // Arrange
      final minimalJson = {
        'id': 'test-id',
        'email': 'test@example.com',
        'username': 'testuser',
        'display_name': 'Test User',
        'created_at': '2026-01-24T10:00:00Z',
      };

      // Act
      final user = UserModel.fromJson(minimalJson);

      // Assert
      expect(user.provider, 'local'); // Default
      expect(user.isVerified, false); // Default
      expect(user.level, 'A1'); // Default
      expect(user.xp, 0); // Default
      expect(user.currentStreak, 0); // Default
    });
  });
}
