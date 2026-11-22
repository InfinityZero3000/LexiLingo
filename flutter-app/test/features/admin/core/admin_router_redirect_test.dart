import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/core/router/app_router.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/auth_provider.dart';

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
  AuthState state = AuthState.authenticated,
  AdminUser? user,
  AdminPermissions? perms,
}) => adminRedirect(
  state: state,
  location: location,
  user: user ?? _user(level: 1),
  permissions: perms ?? _perms(['users:read', 'ops:read']),
);

void main() {
  test(
    'while the account is checked, or there is no session, wait on splash',
    () {
      expect(_go('/users', state: AuthState.unknown, user: null), '/splash');
      expect(_go('/splash', state: AuthState.unknown, user: null), isNull);
      expect(
        _go('/users', state: AuthState.unauthenticated, user: null),
        '/splash',
      );
    },
  );

  test('there is no login route to land on', () {
    expect(
      _go('/login', state: AuthState.unauthenticated, user: null),
      '/splash',
    );
  });

  test('an account without an admin role gets the no-access page', () {
    final user = _user(level: 0);
    expect(
      _go('/dashboard', state: AuthState.forbidden, user: user),
      '/no-access',
    );
    expect(_go('/no-access', state: AuthState.forbidden, user: user), isNull);
  });

  test('a failed account check gets the retry page', () {
    expect(
      _go('/dashboard', state: AuthState.failed, user: null),
      '/load-error',
    );
    expect(_go('/load-error', state: AuthState.failed, user: null), isNull);
  });

  test('an admin leaves the gate pages for the dashboard', () {
    expect(_go('/splash'), '/dashboard');
    expect(_go('/no-access'), '/dashboard');
    expect(_go('/load-error'), '/dashboard');
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
