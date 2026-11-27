import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/services/session_expired_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'core/permissions/admin_permissions.dart';
import 'core/router/app_router.dart';
import 'core/storage/admin_session_store.dart';
import 'core/theme/admin_palette.dart';
import 'core/theme/admin_theme_controller.dart';
import 'features/auth/presentation/auth_provider.dart';
import 'shared/admin_exit_scope.dart';

/// Full-screen admin panel embedded in the main app. Opened with
/// Navigator.push from the profile page when the user is an admin. There is no
/// admin login: it uses the learner's session and only checks the account is
/// an admin. It keeps its own router, theme controller, and permission set.
class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final AuthProvider _authProvider = AuthProvider();
  late final AdminPermissions _permissions = AdminPermissions();
  late final AdminThemeController _themeController = AdminThemeController();
  late final _router = createRouter(_authProvider, _permissions);
  AuthState? _lastAuthState;
  StreamSubscription<void>? _expiredSub;
  bool _exited = false;

  @override
  void initState() {
    super.initState();
    purgeLegacyAdminSession();
    _themeController.load();
    _authProvider.addListener(_syncPermissions);
    _expiredSub = SessionExpiredService.instance.onSessionExpired.listen(
      (_) => _exit(),
    );
    _authProvider.init();
  }

  void _exit() {
    if (_exited || !mounted) return;
    _exited = true;
    Navigator.of(context).maybePop();
  }

  void _syncPermissions() {
    final state = _authProvider.state;
    if (state == _lastAuthState) return;
    _lastAuthState = state;
    if (state == AuthState.authenticated) {
      _permissions.load();
    } else {
      _permissions.clear();
      if (state == AuthState.unauthenticated) _exit();
    }
  }

  @override
  void dispose() {
    _expiredSub?.cancel();
    _authProvider
      ..removeListener(_syncPermissions)
      ..dispose();
    _permissions.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        final mode = _themeController.mode;
        final brightness = mode == ThemeMode.system
            ? MediaQuery.platformBrightnessOf(context)
            : (mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemUiOverlayStyle(brightness),
          child: AdminExitScope(
            onExit: _exit,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: _authProvider),
                ChangeNotifierProvider.value(value: _permissions),
                ChangeNotifierProvider.value(value: _themeController),
              ],
              child: MaterialApp.router(
                title: 'LexiLingo Admin',
                debugShowCheckedModeBanner: false,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                theme: AdminTheme.light(),
                darkTheme: AdminTheme.dark(),
                themeMode: mode,
                routerConfig: _router,
              ),
            ),
          ),
        );
      },
    );
  }
}
