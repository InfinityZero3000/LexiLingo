import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/auth_provider.dart';

AdminUser _admin({bool superAdmin = false}) => AdminUser(
  id: '1',
  email: 'a@b.c',
  displayName: 'A',
  roleSlug: superAdmin ? 'super_admin' : 'admin',
  roleLevel: superAdmin ? 2 : 1,
  isSuperAdmin: superAdmin,
  isAdmin: true,
  hasUserAccount: true,
);

DioException _http(int code, [Object? body]) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  response: Response(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: code,
    data: body,
  ),
);

class _FakeRepo implements AuthRepository {
  AdminUser? me;
  Object? verifyError;
  bool loggedOut = false;

  @override
  Future<AdminUser?> getMe() async => me;
  @override
  Future<AdminUser> verifyOtp(String email, String otp) async {
    if (verifyError != null) throw verifyError!;
    return _admin();
  }

  @override
  Future<void> requestOtp(String email) async {}
  @override
  Future<AdminUser> loginWithGoogle(String idToken) async => _admin();
  @override
  Future<void> logout() async => loggedOut = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  test('init reads the stored session', () async {
    final repo = _FakeRepo()..me = _admin(superAdmin: true);
    final auth = AuthProvider(repository: repo);
    await auth.init();
    expect(auth.state, AuthState.authenticated);
    expect(auth.isSuperAdmin, isTrue);

    final empty = AuthProvider(repository: _FakeRepo());
    await empty.init();
    expect(empty.state, AuthState.unauthenticated);
  });

  test('verifyOtp signs in', () async {
    final auth = AuthProvider(repository: _FakeRepo());
    expect(await auth.verifyOtp('a@b.c', '123456'), isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.error, isNull);
  });

  test('failures become keyed messages, not hard-coded text', () async {
    final repo = _FakeRepo()..verifyError = _http(403);
    final auth = AuthProvider(repository: repo);
    expect(await auth.verifyOtp('a@b.c', '1'), isFalse);
    expect(auth.state, AuthState.unauthenticated);
    expect(auth.errorText, isNotNull);
    expect(auth.error, 'admin.errors.notAdmin');

    repo.verifyError = _http(401);
    await auth.verifyOtp('a@b.c', '1');
    expect(auth.error, 'admin.errors.notVerified');

    repo.verifyError = _http(503, {
      'detail': 'Admin Google OAuth not configured',
    });
    await auth.verifyOtp('a@b.c', '1');
    expect(auth.error, 'admin.errors.oauthMissing');
  });

  test('logout clears the user', () async {
    final repo = _FakeRepo()..me = _admin();
    final auth = AuthProvider(repository: repo);
    await auth.init();
    await auth.logout();
    expect(repo.loggedOut, isTrue);
    expect(auth.user, isNull);
    expect(auth.state, AuthState.unauthenticated);
  });
}
