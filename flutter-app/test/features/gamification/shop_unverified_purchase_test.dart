import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
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
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/screens/shop_screen.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/shop_item_card.dart';
import 'package:provider/provider.dart';

class _AuthRepo implements AuthRepository {
  _AuthRepo(this.user);
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

Future<AuthProvider> _auth(_AuthRepo repo) async {
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

UserEntity _user() => UserEntity(
  id: 'u1',
  email: 'learner@example.com',
  username: 'learner',
  displayName: 'Learner',
  isVerified: false,
  createdAt: DateTime(2026),
);

ApiErrorException _refusal(String reason) => ApiErrorException(
  ErrorResponseEnvelope(
    error: ErrorDetail(
      code: ErrorCodes.authForbidden,
      message: 'Verify your email before buying',
      details: {'reason': reason},
    ),
    meta: const RequestMeta(requestId: 'r', timestamp: '2026-01-01T00:00:00Z'),
  ),
);

class _ShopRepo implements GamificationRepository {
  _ShopRepo(this.failure);
  final Object failure;

  @override
  Future<WalletEntity> getWallet() async =>
      WalletEntity(id: 'w', userId: 'u1', gems: 100);

  @override
  Future<List<ShopItemEntity>> getShopItems() async => [
    ShopItemEntity.fromJson({
      'id': 'i',
      'name': 'Heart',
      'description': 'd',
      'category': 'power_ups',
      'price_gems': 10,
      'effect_type': 'heart_refill',
    }),
  ];

  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async =>
      throw failure;

  @override
  Future<List<InventoryItemEntity>> getInventory() async => [];
  @override
  Future<List<WalletTransactionEntity>> getTransactions({
    int limit = 50,
  }) async => [];
  @override
  Future<StarterRewardEntity?> getPendingStarterReward() async => null;
  @override
  Future<bool> acknowledgeStarterReward() async => false;
  @override
  Future<Map<String, dynamic>?> useItem(
    String inventoryId, {
    String? gameSessionId,
  }) async => null;
  @override
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeaderboardEntity> getLeaderboard(String league) async =>
      throw UnimplementedError();
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async =>
      throw UnimplementedError();
}

Future<void> _buy(
  WidgetTester tester,
  _ShopRepo shop,
  _AuthRepo authRepo,
) async {
  tester.view.physicalSize = const Size(375, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = await _auth(authRepo);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => GamificationProvider(repository: shop),
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
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
            home: const ShopScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(
    find
        .descendant(
          of: find.byType(ShopItemCard),
          matching: find.byType(GestureDetector),
        )
        .last,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Purchase'));
  await tester.pump(const Duration(milliseconds: 500));
}

class _EnglishFromDisk extends AssetLoader {
  const _EnglishFromDisk();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('assets/i18n/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('an unverified buyer is told to verify and can resend', (
    tester,
  ) async {
    final authRepo = _AuthRepo(_user());
    await _buy(tester, _ShopRepo(_refusal('email_unverified')), authRepo);

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Verify your email to buy from the shop.'),
      findsOneWidget,
    );
    expect(find.text('Purchase failed. Please try again.'), findsNothing);

    await tester.tap(find.text('Resend email'));
    await tester.pump();

    expect(authRepo.resends, 1);
  });

  testWidgets('any other refusal keeps the generic message', (tester) async {
    await _buy(
      tester,
      _ShopRepo(_refusal('something_else')),
      _AuthRepo(_user()),
    );

    expect(find.text('Purchase failed. Please try again.'), findsOneWidget);
    expect(find.text('Verify your email to buy from the shop.'), findsNothing);
  });
}
