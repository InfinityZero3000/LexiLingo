import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/network/admin_api_error.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';

void main() {
  test('can() matches exact slugs and the resource:manage wildcard', () {
    final p = AdminPermissions()
      ..apply({
        'all': false,
        'permissions': ['users:read', 'courses:manage'],
      });
    expect(p.can('users:read'), isTrue);
    expect(p.can('users:update'), isFalse);
    expect(p.can('courses:delete'), isTrue);
    expect(p.can('content:read'), isFalse);
    expect(p.canAny('users'), isTrue);
    expect(p.canAny('rbac'), isFalse);
  });

  test('all grants everything', () {
    final p = AdminPermissions()..apply({'all': true, 'permissions': []});
    expect(p.can('rbac:manage'), isTrue);
    expect(p.hasAll, isTrue);
  });

  test('reads a {data} envelope and tolerates a missing list', () {
    final p = AdminPermissions()
      ..apply({
        'data': {
          'all': false,
          'permissions': ['ops:read'],
        },
      });
    expect(p.can('ops:read'), isTrue);
    p.apply({'all': false});
    expect(p.can('ops:read'), isFalse);
    expect(p.isReady, isTrue);
  });

  test('load() fetches and notifies; a failure fails closed', () async {
    var calls = 0;
    final p = AdminPermissions(
      fetch: () async {
        calls++;
        return {
          'all': false,
          'permissions': ['users:read'],
        };
      },
    );
    var notified = 0;
    p.addListener(() => notified++);
    await p.load();
    expect(calls, 1);
    expect(p.isReady, isTrue);
    expect(p.can('users:read'), isTrue);
    expect(notified, greaterThanOrEqualTo(2));

    final failing = AdminPermissions(fetch: () async => throw StateError('x'));
    await failing.load();
    expect(failing.status, AdminPermissionsStatus.failed);
    expect(failing.error?.kind, AdminErrorKind.unknown);
    expect(failing.can('users:read'), isFalse);
  });

  test('clear() forgets everything', () {
    final p = AdminPermissions()..apply({'all': true, 'permissions': []});
    p.clear();
    expect(p.status, AdminPermissionsStatus.idle);
    expect(p.can('users:read'), isFalse);
  });
}
