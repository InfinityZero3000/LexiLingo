import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/auth_provider.dart';

AdminUser _user({int level = 1}) => AdminUser(
  id: '1',
  email: 'a@b.c',
  displayName: 'A',
  roleSlug: level >= 2 ? 'super_admin' : (level == 1 ? 'admin' : 'user'),
  roleLevel: level,
  isSuperAdmin: level >= 2,
  isAdmin: level >= 1,
  hasUserAccount: true,
);

class _FakeRepo implements AuthRepository {
  AdminUser? me;
  Object? error;
  int calls = 0;

  @override
  Future<AdminUser?> getMe() async {
    calls++;
    if (error != null) throw error!;
    return me;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  test('an admin account is let in', () async {
    final auth = AuthProvider(repository: _FakeRepo()..me = _user(level: 2));
    expect(auth.state, AuthState.unknown);
    await auth.init();
    expect(auth.state, AuthState.authenticated);
    expect(auth.isSuperAdmin, isTrue);
  });

  test('a learner without an admin role is forbidden', () async {
    final auth = AuthProvider(repository: _FakeRepo()..me = _user(level: 0));
    await auth.init();
    expect(auth.state, AuthState.forbidden);
    expect(auth.isAuthenticated, isFalse);
  });

  test('no learner session means unauthenticated', () async {
    final auth = AuthProvider(repository: _FakeRepo());
    await auth.init();
    expect(auth.state, AuthState.unauthenticated);
    expect(auth.user, isNull);
  });

  test('a network failure is an error with a retry that can recover', () async {
    final repo = _FakeRepo()
      ..error = DioException(
        requestOptions: RequestOptions(path: '/users/me'),
        type: DioExceptionType.connectionTimeout,
      );
    final auth = AuthProvider(repository: repo);
    await auth.init();
    expect(auth.state, AuthState.failed);
    expect(auth.errorText, isNotNull);

    repo
      ..error = null
      ..me = _user();
    await auth.retry();
    expect(repo.calls, 2);
    expect(auth.state, AuthState.authenticated);
    expect(auth.errorText, isNull);
  });
}
