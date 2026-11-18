import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:provider/provider.dart';

/// Pumps [screen] the way the admin app shows it: the shared theme, the
/// permissions provider, and a router so `context.push` works. [detail]
/// answers `/users/:id`.
Future<void> pumpAdminScreen(
  WidgetTester tester,
  Widget screen, {
  List<String> slugs = const ['users:read'],
  bool all = false,
  Size size = const Size(420, 900),
  Widget Function(String id)? detail,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final permissions = AdminPermissions()
    ..apply({'all': all, 'permissions': slugs});
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      GoRoute(
        path: '/users/:id',
        builder: (_, state) =>
            detail?.call(state.pathParameters['id']!) ??
            Text('detail ${state.pathParameters['id']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AdminPermissions>.value(
      value: permissions,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
}
