import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/core/services/session_expired_service.dart';
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

UserEntity _user(String id, {String name = 'Learner'}) => UserEntity(
  id: id,
  email: '$id@example.com',
  username: id,
  displayName: name,
  nativeLanguage: 'vi',
  createdAt: DateTime(2026),
);

class _Repo implements AuthRepository {
  bool hasTokens = true;
  Completer<Either<Failure, UserEntity>>? gate;
  Either<Failure, UserEntity> answer = const Left(ServerFailure());
  int fetches = 0;

  @override
  Future<bool> isAuthenticated() async => hasTokens;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() {
    fetches++;
    return gate?.future ?? Future.value(answer);
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

AuthProvider _provider(_Repo repo, {UserEntity? cached}) => AuthProvider(
  signInWithGoogleUseCase: SignInWithGoogleUseCase(repo),
  signInWithFacebookUseCase: SignInWithFacebookUseCase(repo),
  signInWithEmailPasswordUseCase: SignInWithEmailPasswordUseCase(repo),
  signOutUseCase: SignOutUseCase(repo),
  getCurrentUserUseCase: GetCurrentUserUseCase(repo),
  registerUseCase: RegisterUseCase(repo),
  authRepository: repo,
  googleSignInService: _Google(),
  facebookSignInService: _Facebook(),
  loadCachedUser: cached == null ? null : () async => cached,
);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('cold start with a learner cached on the device', () {
    test('opens at once, without waiting for the network', () async {
      final repo = _Repo()..gate = Completer();
      final provider = _provider(repo, cached: _user('u1'));
      await _settle();

      expect(provider.isCheckingAuth, isFalse);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.user!.id, 'u1');
      expect(repo.fetches, 1, reason: 'the server still confirms, behind the open app');
    });

    for (final failure in <Failure>[
      const NetworkFailure(),
      const ServerFailure('502'),
      const RateLimitFailure(),
      // A 401 whose refresh could not run (server restarting) arrives as this.
      const AuthFailure('Not authenticated'),
    ]) {
      test('${failure.runtimeType} while confirming keeps the learner signed in',
          () async {
        final repo = _Repo()..answer = Left(failure);
        final provider = _provider(repo, cached: _user('u1'));
        await _settle();

        expect(provider.isAuthenticated, isTrue);
        expect(provider.user!.id, 'u1');
      });
    }

    test('the server answer replaces what was cached', () async {
      final repo = _Repo()..answer = Right(_user('u1', name: 'Renamed'));
      final provider = _provider(repo, cached: _user('u1', name: 'Old'));
      await _settle();

      expect(provider.user!.displayName, 'Renamed');
    });

    test('a refresh token the server refused signs the learner out', () async {
      final repo = _Repo()..gate = Completer();
      final provider = _provider(repo, cached: _user('u1'));
      await _settle();
      expect(provider.isAuthenticated, isTrue);

      // refreshBackendToken clears the tokens, then announces it.
      repo.hasTokens = false;
      SessionExpiredService.instance.notifyExpired();
      await _settle();

      expect(provider.isAuthenticated, isFalse);
      repo.gate!.complete(const Left(AuthFailure('Not authenticated')));
      await _settle();
      expect(provider.isAuthenticated, isFalse);
    });

    test('tokens gone by the time confirmation fails also ends the session',
        () async {
      final repo = _Repo()..gate = Completer();
      final provider = _provider(repo, cached: _user('u1'));
      await _settle();

      repo.hasTokens = false;
      repo.gate!.complete(const Left(AuthFailure('Not authenticated')));
      await _settle();

      expect(provider.isAuthenticated, isFalse);
    });

    test('an answer that lands after another account signed in is dropped',
        () async {
      final repo = _Repo()..gate = Completer();
      final provider = _provider(repo, cached: _user('u1'));
      await _settle();

      SessionExpiredService.instance.notifyExpired();
      await _settle();
      repo.gate!.complete(Right(_user('u1', name: 'Late')));
      await _settle();

      expect(provider.user, isNull);
    });
  });

  group('without a cached learner', () {
    test('no stored tokens: no network call, signed out', () async {
      final repo = _Repo()..hasTokens = false;
      final provider = _provider(repo, cached: _user('u1'));
      await _settle();

      expect(provider.isAuthenticated, isFalse);
      expect(repo.fetches, 0);
    });

    test('waits for the server and signs in when it answers', () async {
      final repo = _Repo()..answer = Right(_user('u1'));
      final provider = _provider(repo);
      await _settle();

      expect(provider.user!.id, 'u1');
    });

    test('a failed check leaves the tokens alone for the next start', () async {
      final repo = _Repo()..answer = const Left(ServerFailure('502'));
      final provider = _provider(repo);
      await _settle();

      expect(provider.isAuthenticated, isFalse);
      expect(repo.hasTokens, isTrue);
    });
  });
}
