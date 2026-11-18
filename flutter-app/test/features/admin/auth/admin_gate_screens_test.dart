import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/admin_gate_screens.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/features/admin/shared/admin_exit_scope.dart';
import 'package:provider/provider.dart';

class _Repo implements AuthRepository {
  _Repo(this.results);
  final List<Object?> results;
  int calls = 0;

  @override
  Future<AdminUser?> getMe() async {
    final r = results[calls++ % results.length];
    if (r is Exception) throw r;
    return r as AdminUser?;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _admin = AdminUser(
  id: '1',
  email: 'a@b.c',
  displayName: 'A',
  roleSlug: 'admin',
  roleLevel: 1,
  isSuperAdmin: false,
  isAdmin: true,
  hasUserAccount: true,
);

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  Future<int> pump(
    WidgetTester tester,
    Widget screen,
    AuthProvider auth,
  ) async {
    var exits = 0;
    await tester.pumpWidget(
      AdminExitScope(
        onExit: () => exits++,
        child: ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(home: screen),
        ),
      ),
    );
    await tester.pump();
    return exits;
  }

  testWidgets('no-access explains and offers a way back', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      AdminExitScope(
        onExit: () => exits++,
        child: const MaterialApp(home: AdminNoAccessScreen()),
      ),
    );
    expect(find.text('admin.gate.noAccessTitle'), findsOneWidget);
    expect(find.text('admin.gate.retry'), findsNothing);
    await tester.tap(find.text('admin.gate.exit'));
    expect(exits, 1);
  });

  testWidgets('the load-error page retries, and can be left', (tester) async {
    final repo = _Repo([
      DioException(
        requestOptions: RequestOptions(path: '/users/me'),
        type: DioExceptionType.connectionTimeout,
      ),
      _admin,
    ]);
    final auth = AuthProvider(repository: repo);
    await auth.init();
    expect(auth.state, AuthState.failed);

    await pump(tester, const AdminLoadErrorScreen(), auth);
    expect(find.text('admin.gate.loadErrorTitle'), findsOneWidget);
    expect(find.text('admin.gate.exit'), findsOneWidget);

    await tester.tap(find.text('admin.gate.retry'));
    await tester.pump();
    expect(repo.calls, 2);
    expect(auth.state, AuthState.authenticated);
  });

  testWidgets('the splash is just a spinner', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminSplashScreen()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
