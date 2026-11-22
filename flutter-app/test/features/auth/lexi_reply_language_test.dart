import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/features/auth/data/models/user_model.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_facebook_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';

UserEntity _user({String reply = UserEntity.lexiReplyApp}) => UserEntity(
  id: 'user-1',
  email: 'learner@example.com',
  username: 'learner',
  displayName: 'Learner',
  nativeLanguage: 'vi',
  lexiReplyLanguage: reply,
  createdAt: DateTime(2026),
);

class _Repo implements AuthRepository {
  _Repo(this.user);

  UserEntity user;
  Completer<Either<Failure, UserEntity>>? pending;
  final sent = <String?>[];

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async => Right(user);

  @override
  Future<Either<Failure, UserEntity>> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? nativeLanguage,
    String? lexiReplyLanguage,
    String? targetLanguage,
    String? level,
    String? goal,
    String? interest,
    bool? isOnboardingCompleted,
  }) {
    sent.add(lexiReplyLanguage);
    return (pending = Completer()).future;
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

Map<String, dynamic> _json([Object? reply]) => {
  'id': 'user-1',
  'email': 'learner@example.com',
  'username': 'learner',
  'native_language': 'ja',
  if (reply != null) 'lexi_reply_language': reply,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reply language', () {
    test('an account that never chose follows the app language', () {
      expect(UserModel.fromJson(_json()).lexiReplyLanguage, 'app');
      expect(UserModel.fromJson(_json('nonsense')).lexiReplyLanguage, 'app');
      expect(UserModel.fromJson(_json()).lexiReplyLanguageFor('fr'), 'fr');
    });

    test('"native" answers in the mother tongue whatever the UI shows', () {
      final user = UserModel.fromJson(_json('native'));
      expect(user.lexiReplyLanguageFor('fr'), 'ja');
      expect(user.toJson()['lexi_reply_language'], 'native');
      expect(UserModel.fromEntity(user).lexiReplyLanguage, 'native');
    });
  });

  group('AuthProvider.updateLexiReplyLanguage', () {
    test('shows the choice before the server answers, then keeps it', () async {
      final repo = _Repo(_user());
      final auth = await _provider(repo);
      addTearDown(auth.dispose);

      final saving = auth.updateLexiReplyLanguage(UserEntity.lexiReplyNative);
      expect(auth.user!.lexiReplyLanguage, 'native');
      expect(repo.sent, ['native']);

      repo.pending!.complete(Right(_user(reply: UserEntity.lexiReplyNative)));
      expect(await saving, isTrue);
      expect(auth.user!.lexiReplyLanguage, 'native');
    });

    test('puts the old choice back when the server refuses', () async {
      final repo = _Repo(_user());
      final auth = await _provider(repo);
      addTearDown(auth.dispose);

      final saving = auth.updateLexiReplyLanguage(UserEntity.lexiReplyNative);
      repo.pending!.complete(const Left(NetworkFailure()));

      expect(await saving, isFalse);
      expect(auth.user!.lexiReplyLanguage, 'app');
    });

    test('choosing the current value sends nothing', () async {
      final repo = _Repo(_user());
      final auth = await _provider(repo);
      addTearDown(auth.dispose);

      expect(
        await auth.updateLexiReplyLanguage(UserEntity.lexiReplyApp),
        isTrue,
      );
      expect(repo.sent, isEmpty);
    });
  });
}
