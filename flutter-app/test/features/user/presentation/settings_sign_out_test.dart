import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_facebook_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo implements AuthRepository {
  final user = UserEntity(
    id: 'u1',
    email: 'learner@example.com',
    username: 'learner',
    displayName: 'Learner',
    isVerified: true,
    createdAt: DateTime(2026),
  );

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async => Right(user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Google implements GoogleSignInService {
  @override
  Future<String?> consumePendingWebRedirectIdToken() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Facebook implements FacebookSignInService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signs out when [succeed], or swallows the failure the way the real one
/// does, leaving the learner signed in.
class _Auth extends AuthProvider {
  _Auth(_Repo repo)
    : super(
        signInWithGoogleUseCase: SignInWithGoogleUseCase(repo),
        signInWithFacebookUseCase: SignInWithFacebookUseCase(repo),
        signInWithEmailPasswordUseCase: SignInWithEmailPasswordUseCase(repo),
        signOutUseCase: SignOutUseCase(repo),
        getCurrentUserUseCase: GetCurrentUserUseCase(repo),
        registerUseCase: RegisterUseCase(repo),
        authRepository: repo,
        googleSignInService: _Google(),
        facebookSignInService: _Facebook(),
      );

  bool succeed = true;
  bool signedOut = false;
  int signOuts = 0;
  Completer<void>? gate;

  @override
  bool get isAuthenticated => !signedOut && super.isAuthenticated;

  @override
  Future<void> signOut() async {
    signOuts++;
    await gate?.future;
    if (succeed) signedOut = true;
    notifyListeners();
  }
}

class _SettingsRepo implements SettingsRepository {
  @override
  Future<Either<Failure, Settings>> getSettings(String userId) async =>
      const Right(Settings(id: 1, userId: 'u1'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications extends NotificationService {
  @override
  Future<void> ensureInitialized() async {}
}

class _EnglishFromDisk extends AssetLoader {
  const _EnglishFromDisk();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('assets/i18n/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _PopRecorder extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pops++;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late _Auth auth;
  late _PopRecorder pops;

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    auth = _Auth(_Repo());
    await auth.refreshCurrentUser();
    pops = _PopRecorder();
    final settings = SettingsProvider(
      repository: _SettingsRepo(),
      notificationService: _Notifications(),
      themePreferenceStore: ThemePreferenceStore(
        await SharedPreferences.getInstance(),
      ),
      apiClient: ApiClient(enableLogging: false),
      hasServerPush: () => false,
      deviceTimezone: () async => null,
    );
    await tester.binding.setSurfaceSize(const Size(430, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'unused',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          assetLoader: const _EnglishFromDisk(),
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              navigatorObservers: [pops],
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmSignOut(WidgetTester tester) async {
    await tester.tap(find.text('Sign Out').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign Out'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('signing out ends the session, then returns to the first route', (
    tester,
  ) async {
    await open(tester);
    final popsBefore = pops.pops;

    await confirmSignOut(tester);
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    expect(auth.isAuthenticated, isFalse);
    expect(pops.pops, greaterThan(popsBefore));
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('a second tap while it runs does not sign out twice', (
    tester,
  ) async {
    await open(tester);
    auth.gate = Completer<void>();

    await confirmSignOut(tester);
    expect(find.byKey(const Key('settings.signingOut')), findsOneWidget);

    expect(find.byType(AlertDialog), findsNothing, reason: 'dialog closed');
    await tester.tap(find.text('Sign Out').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing, reason: 'tile is disabled');

    auth.gate!.complete();
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
  });

  testWidgets('a sign-out that did not take stays put and says so', (
    tester,
  ) async {
    await open(tester);
    auth.succeed = false;
    final popsBefore = pops.pops;

    await confirmSignOut(tester);
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isTrue);
    expect(pops.pops, popsBefore, reason: 'no pop while still signed in');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('An error occurred. Please try again.'), findsOneWidget);
    expect(find.byKey(const Key('settings.signingOut')), findsNothing);
  });
}
