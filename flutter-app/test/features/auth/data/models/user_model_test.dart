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
      'role_slug': 'admin',
      'cefr_level': 'B1',
      'total_xp': 500,
      'numeric_level': 3,
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
      expect(user.roleSlug, 'admin');
      expect(user.canAccessAdminPanel, true);
      expect(user.cefrLevel, 'B1');
      expect(user.totalXp, 500);
      expect(user.numericLevel, 3);
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
        roleSlug: 'super_admin',
        cefrLevel: 'A1',
        totalXp: 0,
        numericLevel: 1,
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
      expect(json['role_slug'], 'super_admin');
      expect(json['level'], 'A1');
      expect(json['total_xp'], 0);
      expect(json['numeric_level'], 1);
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
        'cefr_level': 'A1',
        'total_xp': 0,
        'numeric_level': 1,
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
        roleSlug: 'admin',
        cefrLevel: 'B2',
        totalXp: 1000,
        numericLevel: 4,
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
      expect(model.roleSlug, 'admin');
      expect(model.cefrLevel, 'B2');
      expect(model.totalXp, 1000);
      expect(model.numericLevel, 4);
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
      expect(user.roleSlug, 'user'); // Default
      expect(user.canAccessAdminPanel, false);
      expect(user.cefrLevel, 'A1'); // Default
      expect(user.totalXp, 0); // Default
      expect(user.numericLevel, 1); // Default
      expect(user.currentStreak, 0); // Default
    });

    test('should parse legacy role field and normalize access checks', () {
      final admin = UserModel.fromJson({
        ...testJson,
        'role_slug': null,
        'role': ' ADMIN ',
      });
      final superAdmin = UserModel.fromJson({
        ...testJson,
        'role_slug': 'SUPER_ADMIN',
      });
      final regularUser = UserModel.fromJson({
        ...testJson,
        'role_slug': 'user',
      });

      expect(admin.canAccessAdminPanel, true);
      expect(superAdmin.canAccessAdminPanel, true);
      expect(regularUser.canAccessAdminPanel, false);
    });
  });
}
