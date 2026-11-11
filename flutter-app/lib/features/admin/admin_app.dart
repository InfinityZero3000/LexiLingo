import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_provider.dart';
import 'shared/admin_exit_scope.dart';

/// Full-screen admin panel embedded inside the main flutter-app.
/// Opened via Navigator.push from profile_page when the user is an admin.
///
/// FROZEN: this is a mobile port of the web admin (admin-service) and now trails
/// it. New admin features go to the web admin; change this module only to keep
/// it building and safe. If a mobile companion is ever wanted, rebuild a small
/// one (approve jobs, read the audit log) on the shared ApiClient, Theme and i18n.
class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final AuthProvider _authProvider;
  late final _router = createRouter(_authProvider);

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _authProvider.init();
  }

  @override
  void dispose() {
    _authProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: AdminExitScope(
        onExit: () => Navigator.of(context).maybePop(),
        child: ChangeNotifierProvider.value(
          value: _authProvider,
          child: MaterialApp.router(
            title: 'LexiLingo Admin',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
