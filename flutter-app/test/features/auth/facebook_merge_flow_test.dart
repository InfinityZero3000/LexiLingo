import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/core/startup/auth_emulator.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_facebook_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fbToken(String email) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'email': email})}.sig';
}

UserEntity _user(String email) => UserEntity(
  id: 'id-$email',
  email: email,
  username: 'learner',
  displayName: 'Learner',
  createdAt: DateTime(2026),
);

class _Repo implements AuthRepository {
  /// The account a password sign-in opens.
  String passwordAccount = 'owner@example.com';
  Either<Failure, void> linkResult = const Right(null);
  final linked = <String>[];

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async =>
      const Left(AuthFailure());

  @override
  Future<Either<Failure, UserEntity>> loginWithFacebook(String token) async =>
      const Left(AccountLinkRequiredFailure(['password']));

  @override
  Future<Either<Failure, UserEntity>> login({
    required String email,
    required String password,
  }) async => Right(_user(passwordAccount));

  @override
  Future<Either<Failure, void>> linkFacebook(String token) async {
    linked.add(token);
    return linkResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Facebook extends Fake implements FacebookSignInService {
  _Facebook(this.onSignIn);

  final Future<String?> Function() onSignIn;
  var cancelled = 0;

  @override
  Future<String?> signIn() => onSignIn();

  @override
  Future<String?> linkWithGoogle(FacebookLinkRequired request) async =>
      throw const FacebookConfirmRequired();

  @override
  Future<void> cancelLink() async => cancelled++;
}

class _Google extends Fake implements GoogleSignInService {
  @override
  Future<String?> consumePendingWebRedirectIdToken() async => null;

  @override
  Future<String?> signIn() async => null;

  @override
  String? get lastError => null;
}

class _Api extends Fake implements ApiClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Repo repo;
  final token = _fbToken('owner@example.com');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _Repo();
    if (!sl.isRegistered<ApiClient>()) {
      sl.registerSingleton<ApiClient>(_Api());
    }
  });

  AuthProvider provider(_Facebook facebook) {
    final auth = AuthProvider(
      signInWithGoogleUseCase: SignInWithGoogleUseCase(repo),
      signInWithFacebookUseCase: SignInWithFacebookUseCase(repo),
      signInWithEmailPasswordUseCase: SignInWithEmailPasswordUseCase(repo),
      signOutUseCase: SignOutUseCase(repo),
      getCurrentUserUseCase: GetCurrentUserUseCase(repo),
      registerUseCase: RegisterUseCase(repo),
      authRepository: repo,
      googleSignInService: _Google(),
      facebookSignInService: facebook,
    );
    addTearDown(auth.dispose);
    return auth;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('a refused Facebook sign-in asks to merge and shows no error', () async {
    final auth = provider(_Facebook(() async => token));

    await auth.signInWithFacebook();

    expect(auth.facebookMergeStep, FacebookMergeStep.signInToMerge);
    expect(auth.facebookMergeEmail, 'owner@example.com');
    expect(auth.errorMessage, isNull);
    expect(repo.linked, isEmpty);
  });

  test('signing in to that account merges it, once', () async {
    final auth = provider(_Facebook(() async => token));
    await auth.signInWithFacebook();

    await auth.signInWithEmailPassword('owner@example.com', 'pw');
    await settle();

    expect(repo.linked, [token]);
    expect(auth.takeAccountNotice(), isNotNull);
    expect(auth.takeAccountNotice(), isNull);
    expect(auth.facebookMergeStep, FacebookMergeStep.none);
  });

  test('signing in to a different account merges nothing', () async {
    final auth = provider(_Facebook(() async => token));
    await auth.signInWithFacebook();
    repo.passwordAccount = 'someone-else@example.com';

    await auth.signInWithEmailPassword('someone-else@example.com', 'pw');
    await settle();

    expect(repo.linked, isEmpty);
    expect(auth.facebookMergeStep, FacebookMergeStep.none);
  });

  test('"not now" forgets the Facebook sign-in', () async {
    final auth = provider(_Facebook(() async => token));
    await auth.signInWithFacebook();

    auth.dismissFacebookLink();
    await auth.signInWithEmailPassword('owner@example.com', 'pw');
    await settle();

    expect(repo.linked, isEmpty);
  });

  test('closing the Facebook window shows no error', () async {
    final auth = provider(_Facebook(() async => null));

    await auth.signInWithFacebook();

    expect(auth.errorMessage, isNull);
    expect(auth.facebookMergeStep, FacebookMergeStep.none);
  });

  test('closing the Google window shows no error', () async {
    final auth = provider(_Facebook(() async => null));

    await auth.signInWithGoogle();

    expect(auth.errorMessage, isNull);
  });

  test('a taken email walks Google then a second Facebook tap, and giving up '
      'signs Firebase out', () async {
    final facebook = _Facebook(
      () async => throw const FacebookLinkRequired(null, null),
    );
    final auth = provider(facebook);

    await auth.signInWithFacebook();
    expect(auth.facebookMergeStep, FacebookMergeStep.proveWithGoogle);
    expect(auth.errorMessage, isNull);

    await auth.linkFacebookWithGoogle();
    expect(auth.facebookMergeStep, FacebookMergeStep.confirmFacebook);

    auth.dismissFacebookLink();
    expect(auth.facebookMergeStep, FacebookMergeStep.none);
    expect(facebook.cancelled, 1);
  });

  test('the auth emulator is never used in a release or off this machine', () {
    expect(authEmulatorTarget('127.0.0.1:9099', release: false), (
      '127.0.0.1',
      9099,
    ));
    expect(authEmulatorTarget('127.0.0.1:9099', release: true), isNull);
    expect(authEmulatorTarget('auth.example.com:9099', release: false), isNull);
    expect(authEmulatorTarget('', release: false), isNull);
  });
}
