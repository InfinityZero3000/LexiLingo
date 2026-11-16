import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_facebook_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/verify_email_banner.dart';
import 'package:provider/provider.dart';

class _Repo implements AuthRepository {
  _Repo(this.user);
  final UserEntity user;
  int resends = 0;

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async => Right(user);

  @override
  Future<Either<Failure, void>> resendVerificationEmail(String email) async {
    resends++;
    return const Right(null);
  }

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

Future<AuthProvider> _provider(_Repo repo) async {
  final provider = AuthProvider(
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
  await provider.refreshCurrentUser();
  return provider;
}

UserEntity _user({required bool verified}) => UserEntity(
  id: 'u1',
  email: 'learner@example.com',
  username: 'learner',
  displayName: 'Learner',
  isVerified: verified,
  createdAt: DateTime(2026),
);

Future<void> _pump(WidgetTester tester, AuthProvider auth) => tester.pumpWidget(
  ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: const MaterialApp(home: Scaffold(body: VerifyEmailBanner())),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => EasyLocalization.logger.enableLevels = []);

  testWidgets(
    'an unverified learner is asked to verify and can get a new link',
    (tester) async {
      final repo = _Repo(_user(verified: false));
      await _pump(tester, await _provider(repo));

      expect(find.text('auth.verifyEmailBanner'), findsOneWidget);
      await tester.tap(find.text('auth.verifyEmailBannerAction'));
      await tester.pumpAndSettle();

      expect(repo.resends, 1);
      expect(find.text('auth.emailVerificationResendSuccess'), findsOneWidget);
    },
  );

  testWidgets('a verified learner sees nothing', (tester) async {
    await _pump(tester, await _provider(_Repo(_user(verified: true))));
    expect(find.text('auth.verifyEmailBanner'), findsNothing);
  });
}
