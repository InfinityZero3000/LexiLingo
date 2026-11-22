import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/auth/data/auth_repository.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/features/admin/shared/admin_exit_scope.dart';
import 'package:lexilingo_app/features/admin/shared/widgets/admin_shell.dart';
import 'package:provider/provider.dart';

class _Repo implements AuthRepository {
  _Repo(this.user);
  final AdminUser user;
  @override
  Future<AdminUser?> getMe() async => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdminUser _user({bool superAdmin = false}) => AdminUser(
  id: '1',
  email: 'a@b.c',
  displayName: 'Ada Admin',
  roleSlug: superAdmin ? 'super_admin' : 'admin',
  roleLevel: superAdmin ? 2 : 1,
  isSuperAdmin: superAdmin,
  isAdmin: true,
  hasUserAccount: true,
);

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required List<String> slugs,
    bool superAdmin = false,
    ThemeMode themeMode = ThemeMode.light,
    VoidCallback? onExit,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final auth = AuthProvider(repository: _Repo(_user(superAdmin: superAdmin)));
    await auth.init();
    final perms = AdminPermissions()
      ..apply({'all': superAdmin, 'permissions': slugs});

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AdminShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const Center(child: Text('dashboard body')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      AdminExitScope(
        onExit: onExit ?? () {},
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<AdminPermissions>.value(value: perms),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone: no sidebar, the drawer holds the navigation', (
    tester,
  ) async {
    await pump(tester, size: const Size(375, 812), slugs: ['users:read']);
    expect(find.text('dashboard body'), findsOneWidget);
    expect(find.text('admin.nav.users'), findsNothing);

    AdminShell.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('admin.nav.dashboard'), findsOneWidget);
    expect(find.text('admin.nav.users'), findsOneWidget);
    expect(find.text('Ada Admin'), findsOneWidget);
  });

  testWidgets('wide: the sidebar is always there', (tester) async {
    await pump(tester, size: const Size(1024, 768), slugs: ['users:read']);
    expect(find.text('dashboard body'), findsOneWidget);
    expect(find.text('admin.nav.users'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('nav is filtered by permission and role', (tester) async {
    await pump(tester, size: const Size(1024, 768), slugs: ['users:read']);
    expect(find.text('admin.nav.users'), findsOneWidget);
    expect(find.text('admin.nav.courses'), findsNothing);
    expect(find.text('admin.nav.health'), findsNothing);
    expect(find.text('admin.nav.settings'), findsOneWidget);
    expect(find.text('admin.nav.superDashboard'), findsNothing);
  });

  testWidgets('super admin sees every group', (tester) async {
    tester.view.physicalSize = const Size(1024, 1600);
    await pump(
      tester,
      size: const Size(1024, 1600),
      slugs: const [],
      superAdmin: true,
    );
    expect(find.text('admin.nav.courses'), findsOneWidget);
    expect(find.text('admin.nav.superDashboard'), findsOneWidget);
    expect(find.text('admin.nav.group.superAdmin'), findsOneWidget);
  });

  testWidgets('nav rows are at least 44 px tall', (tester) async {
    await pump(tester, size: const Size(1024, 768), slugs: ['users:read']);
    final row = find.ancestor(
      of: find.text('admin.nav.users'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44));
  });

  testWidgets('tablet and dark: lays out at 768 px without overflow', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(768, 1024),
      slugs: ['users:read'],
      themeMode: ThemeMode.dark,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('dashboard body'), findsOneWidget);
  });

  testWidgets('there is no log-out: the shell offers Exit admin instead', (
    tester,
  ) async {
    var exited = 0;
    await pump(
      tester,
      size: const Size(1024, 768),
      slugs: ['users:read'],
      onExit: () => exited++,
    );
    expect(find.text('admin.shell.logout'), findsNothing);
    expect(find.text('admin.shell.exit'), findsOneWidget);

    await tester.tap(find.text('admin.shell.exit'));
    await tester.pumpAndSettle();
    expect(exited, 1);
  });
}
