import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/services/session_expired_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'core/permissions/admin_permissions.dart';
import 'core/router/app_router.dart';
import 'core/storage/admin_session_store.dart';
import 'features/auth/presentation/auth_provider.dart';
import 'shared/admin_exit_scope.dart';

/// Follows the system, like the rest of the app.
const adminThemeMode = ThemeMode.system;

/// Full-screen admin panel embedded in the main app. Opened with
/// Navigator.push from the profile page when the user is an admin. There is no
/// admin login: it uses the learner's session and only checks the account is
/// an admin. It keeps its own router and permission set; theme, tokens and
/// widgets come from the app's `core/`.
class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final AuthProvider _authProvider = AuthProvider();
  late final AdminPermissions _permissions = AdminPermissions();
  late final _router = createRouter(_authProvider, _permissions);
  AuthState? _lastAuthState;
  StreamSubscription<void>? _expiredSub;
  bool _exited = false;

  @override
  void initState() {
    super.initState();
    purgeLegacyAdminSession();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = adminThemeMode == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context)
        : (adminThemeMode == ThemeMode.dark
              ? Brightness.dark
              : Brightness.light);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle(brightness),
      child: AdminExitScope(
        onExit: _exit,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: _authProvider),
            ChangeNotifierProvider.value(value: _permissions),
          ],
          child: MaterialApp.router(
            title: 'LexiLingo Admin',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: adminThemeMode,
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
