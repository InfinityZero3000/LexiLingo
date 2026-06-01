import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const LexiLingoAdminApp());
}

class LexiLingoAdminApp extends StatefulWidget {
  const LexiLingoAdminApp({super.key});

  @override
  State<LexiLingoAdminApp> createState() => _LexiLingoAdminAppState();
}

class _LexiLingoAdminAppState extends State<LexiLingoAdminApp> {
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
    return ChangeNotifierProvider.value(
      value: _authProvider,
      child: MaterialApp.router(
        title: 'LexiLingo Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
