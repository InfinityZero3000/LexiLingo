import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';

Map<String, dynamic> _me({required int level, bool? adminAccess}) => {
  'id': 'u1',
  'email': 'a@example.com',
  'display_name': 'A',
  'role_slug': level >= 2 ? 'super_admin' : (level == 1 ? 'admin' : 'user'),
  'role_level': level,
  'admin_access': ?adminAccess,
};

void main() {
  test('an admin signed in with Google may use the panel', () {
    final user = AdminUser.fromJson(_me(level: 1, adminAccess: true));
    expect(user.mayUsePanel, isTrue);
    expect(user.needsGoogleSignIn, isFalse);
  });

  test('an admin signed in another way is sent to Google sign-in', () {
    final user = AdminUser.fromJson(_me(level: 2, adminAccess: false));
    expect(user.mayUsePanel, isFalse);
    expect(user.needsGoogleSignIn, isTrue);
  });

  test('a learner never needs Google for the panel: they have no role', () {
    final user = AdminUser.fromJson(_me(level: 0, adminAccess: false));
    expect(user.mayUsePanel, isFalse);
    expect(user.needsGoogleSignIn, isFalse);
  });

  test('an older server that does not report it keeps the role check', () {
    expect(AdminUser.fromJson(_me(level: 1)).mayUsePanel, isTrue);
  });
}
