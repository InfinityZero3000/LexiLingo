import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/core/router/app_router.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';

AdminUser _user({required int level}) => AdminUser(
  id: '1',
  email: 'a@b.c',
  displayName: 'A',
  roleSlug: level >= 2 ? 'super_admin' : (level == 1 ? 'admin' : 'user'),
  roleLevel: level,
  isSuperAdmin: level >= 2,
  isAdmin: level >= 1,
  hasUserAccount: true,
);

AdminPermissions _perms(List<String> slugs, {bool all = false}) =>
    AdminPermissions()..apply({'all': all, 'permissions': slugs});

String? _go(
  String location, {
  bool hasToken = true,
  AdminUser? user,
  AdminPermissions? perms,
}) => adminRedirect(
  hasToken: hasToken,
  location: location,
  user: user ?? _user(level: 1),
  permissions: perms ?? _perms(['users:read', 'ops:read']),
);

void main() {
  test('signed out goes to login, and stays there', () {
    expect(_go('/users', hasToken: false, user: null), '/login');
    expect(_go('/login', hasToken: false, user: null), isNull);
  });

  test('signed in leaves the login page', () {
    expect(_go('/login'), '/dashboard');
  });

  test('an account that is not an admin is sent back to login', () {
    expect(_go('/dashboard', user: _user(level: 0)), '/login');
    expect(_go('/login', user: _user(level: 0)), isNull);
  });

  test('super admin pages are closed to a plain admin', () {
    expect(_go('/super/dashboard'), '/dashboard');
    expect(_go('/super/admins'), '/dashboard');
    expect(_go('/super/dashboard', user: _user(level: 2)), isNull);
  });

  test('system pages need ops:read', () {
    expect(_go('/system-health'), isNull);
    expect(_go('/system-settings'), isNull);
    final noOps = _perms(['users:read']);
    expect(_go('/system-health', perms: noOps), '/dashboard');
    expect(_go('/system-settings', perms: noOps), '/dashboard');
  });

  test('a sub-route follows its parent permission', () {
    final noUsers = _perms(['ops:read']);
    expect(_go('/users/42', perms: noUsers), '/dashboard');
    expect(_go('/users/42'), isNull);
  });

  test('permissions that have not loaded do not block', () {
    expect(_go('/users', perms: AdminPermissions()), isNull);
  });

  test('routes without a permission stay open', () {
    final none = _perms([]);
    expect(_go('/dashboard', perms: none), isNull);
    expect(_go('/settings', perms: none), isNull);
  });
}
