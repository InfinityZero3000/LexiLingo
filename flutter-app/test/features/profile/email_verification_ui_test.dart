import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
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
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/profile_header.dart';
import 'package:lexilingo_app/features/user/domain/repositories/user_repository.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_weekly_activity_usecase.dart';
import 'package:provider/provider.dart';

UserEntity _user({required bool isVerified}) => UserEntity(
  id: 'user-1',
  email: 'learner@example.com',
  username: 'learner',
  displayName: 'Learner',
  isVerified: isVerified,
  createdAt: DateTime(2026),
);

class _AuthRepositoryStub implements AuthRepository {
  _AuthRepositoryStub(this.currentUser);

  UserEntity currentUser;
  Failure? currentUserFailure;
  int resendVerificationCalls = 0;

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async {
    final failure = currentUserFailure;
    return failure == null ? Right(currentUser) : Left(failure);
  }

  @override
  Future<Either<Failure, void>> resendVerificationEmail(String email) async {
    resendVerificationCalls++;
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GamificationRepositoryStub implements GamificationRepository {
  @override
  Future<List<InventoryItemEntity>> getInventory() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ApiClientStub implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UserRepositoryStub implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoogleSignInServiceStub implements GoogleSignInService {
  @override
  Future<String?> consumePendingWebRedirectIdToken() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FacebookSignInServiceStub implements FacebookSignInService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AuthProvider> _createAuthProvider(_AuthRepositoryStub repository) async {
  final provider = AuthProvider(
    signInWithGoogleUseCase: SignInWithGoogleUseCase(repository),
    signInWithFacebookUseCase: SignInWithFacebookUseCase(repository),
    signInWithEmailPasswordUseCase: SignInWithEmailPasswordUseCase(repository),
    signOutUseCase: SignOutUseCase(repository),
    getCurrentUserUseCase: GetCurrentUserUseCase(repository),
    registerUseCase: RegisterUseCase(repository),
    authRepository: repository,
    googleSignInService: _GoogleSignInServiceStub(),
    facebookSignInService: _FacebookSignInServiceStub(),
  );
  await provider.refreshCurrentUser();
  return provider;
}

ProfileProvider _createProfileProvider() {
  final repository = _UserRepositoryStub();
  return ProfileProvider(
    getUserStatsUseCase: GetUserStatsUseCase(repository),
    getWeeklyActivityUseCase: GetWeeklyActivityUseCase(repository),
  );
}

Future<void> _pumpEditProfile(
  WidgetTester tester,
  AuthProvider authProvider,
  GamificationProvider gamificationProvider,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<GamificationProvider>.value(
          value: gamificationProvider,
        ),
      ],
      child: const MaterialApp(home: EditProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileHeader email verification badge', () {
    testWidgets('shows verified icon only for a verified user', (tester) async {
      final levelProvider = LevelProvider(apiClient: _ApiClientStub());
      final profileProvider = _createProfileProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LevelProvider>.value(value: levelProvider),
            ChangeNotifierProvider<ProfileProvider>.value(
              value: profileProvider,
            ),
          ],
          child: MaterialApp(
            home: SingleChildScrollView(
              child: ProfileHeader(
                user: _user(isVerified: true),
                onProfileEdited: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byIcon(Icons.verified), findsOneWidget);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LevelProvider>.value(value: levelProvider),
            ChangeNotifierProvider<ProfileProvider>.value(
              value: profileProvider,
            ),
          ],
          child: MaterialApp(
            home: SingleChildScrollView(
              child: ProfileHeader(
                user: _user(isVerified: false),
                onProfileEdited: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byIcon(Icons.verified), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      levelProvider.dispose();
      profileProvider.dispose();
    });
  });

  group('EditProfileScreen email verification controls', () {
    testWidgets('unverified user can resend and refresh verification', (
      tester,
    ) async {
      final repository = _AuthRepositoryStub(_user(isVerified: false));
      final authProvider = await _createAuthProvider(repository);
      final gamificationProvider = GamificationProvider(
        repository: _GamificationRepositoryStub(),
      );
      await _pumpEditProfile(tester, authProvider, gamificationProvider);

      expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);
      expect(find.text('profile.emailNotVerified'), findsOneWidget);
      expect(find.text('auth.emailVerificationResend'), findsOneWidget);
      expect(find.text('profile.checkVerificationStatus'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);

      final resendButton = find.text('auth.emailVerificationResend');
      await tester.ensureVisible(resendButton);
      await tester.tap(resendButton);
      await tester.pumpAndSettle();

      expect(repository.resendVerificationCalls, 1);
      final resendButtonWidget = find.byWidgetPredicate(
        (widget) => widget is FilledButton,
      );
      final cooldownButton = tester.widget<FilledButton>(resendButtonWidget);
      expect(cooldownButton.onPressed, isNull);

      await tester.tap(resendButtonWidget, warnIfMissed: false);
      await tester.pump();
      expect(repository.resendVerificationCalls, 1);

      await tester.pump(const Duration(seconds: 60));
      final enabledResendButton = tester.widget<FilledButton>(
        resendButtonWidget,
      );
      expect(enabledResendButton.onPressed, isNotNull);

      repository.currentUser = repository.currentUser.copyWith(
        isVerified: true,
      );
      final checkButton = find.text('profile.checkVerificationStatus');
      await tester.ensureVisible(checkButton);
      await tester.tap(checkButton);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('profile.emailVerified'), findsWidgets);
      expect(find.text('auth.emailVerificationResend'), findsNothing);
      expect(find.text('profile.checkVerificationStatus'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      authProvider.dispose();
      gamificationProvider.dispose();
    });

    testWidgets('shows pending status when email is still unverified', (
      tester,
    ) async {
      final repository = _AuthRepositoryStub(_user(isVerified: false));
      final authProvider = await _createAuthProvider(repository);
      final gamificationProvider = GamificationProvider(
        repository: _GamificationRepositoryStub(),
      );
      await _pumpEditProfile(tester, authProvider, gamificationProvider);

      final checkButton = find.text('profile.checkVerificationStatus');
      await tester.ensureVisible(checkButton);
      await tester.tap(checkButton);
      await tester.pumpAndSettle();

      expect(find.text('profile.emailVerificationPending'), findsOneWidget);
      expect(find.text('profile.emailNotVerified'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      authProvider.dispose();
      gamificationProvider.dispose();
    });

    testWidgets('shows refresh error instead of a pending status', (
      tester,
    ) async {
      final repository = _AuthRepositoryStub(_user(isVerified: false));
      final authProvider = await _createAuthProvider(repository);
      final gamificationProvider = GamificationProvider(
        repository: _GamificationRepositoryStub(),
      );
      await _pumpEditProfile(tester, authProvider, gamificationProvider);
      repository.currentUserFailure = const NetworkFailure();

      final checkButton = find.text('profile.checkVerificationStatus');
      await tester.ensureVisible(checkButton);
      await tester.tap(checkButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Network error. Please check your internet connection.'),
        findsOneWidget,
      );
      expect(find.text('profile.emailVerificationPending'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      authProvider.dispose();
      gamificationProvider.dispose();
    });

    testWidgets('verified user has status without resend controls', (
      tester,
    ) async {
      final repository = _AuthRepositoryStub(_user(isVerified: true));
      final authProvider = await _createAuthProvider(repository);
      final gamificationProvider = GamificationProvider(
        repository: _GamificationRepositoryStub(),
      );
      await _pumpEditProfile(tester, authProvider, gamificationProvider);

      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('profile.emailVerified'), findsOneWidget);
      expect(find.text('auth.emailVerificationResend'), findsNothing);
      expect(find.text('profile.checkVerificationStatus'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      authProvider.dispose();
      gamificationProvider.dispose();
    });
  });
}
