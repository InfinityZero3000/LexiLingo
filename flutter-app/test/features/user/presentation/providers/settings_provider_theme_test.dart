import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

class _FakeNotificationService extends NotificationService {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> cancelDailyReminder() async {}
}

class _FakeSettingsRepository implements SettingsRepository {
  Settings loadedSettings;
  Either<Failure, void> updateResult = const Right(null);
  Completer<Either<Failure, void>>? updateCompleter;
  Settings? lastUpdatedSettings;

  _FakeSettingsRepository({required this.loadedSettings});

  @override
  Future<Either<Failure, Settings>> getSettings(String userId) async {
    return Right(loadedSettings);
  }

  @override
  Future<Either<Failure, void>> updateSettings(Settings settings) {
    lastUpdatedSettings = settings;
    return updateCompleter?.future ?? Future.value(updateResult);
  }

  @override
  Future<Either<Failure, void>> createSettings(Settings settings) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> updateDailyGoalXP(String userId, int xp) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> updateNotificationTime(
    String userId,
    String time,
  ) async {
    return const Right(null);
  }
}

class _TestLocalizationLoader extends AssetLoader {
  const _TestLocalizationLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    return {'languageCode': locale.languageCode};
  }
}

Future<SettingsProvider> _createProvider({
  Map<String, Object> initialPreferences = const {},
  Settings? loadedSettings,
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
  final preferences = await SharedPreferences.getInstance();
  final repository = _FakeSettingsRepository(
    loadedSettings: loadedSettings ?? const Settings(id: 1, userId: 'user-1'),
  );

  return SettingsProvider(
    repository: repository,
    notificationService: _FakeNotificationService(),
    themePreferenceStore: ThemePreferenceStore(preferences),
    apiClient: ApiClient(enableLogging: false),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstraps theme mode from local preference', () async {
    final provider = await _createProvider(
      initialPreferences: {AppConstants.themeModeKey: 'dark'},
    );

    expect(provider.theme, 'dark');
    expect(provider.themeMode, ThemeMode.dark);
  });

  test('notifies immediately before persistence completes', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeSettingsRepository(
      loadedSettings: const Settings(id: 1, userId: 'user-1'),
    );
    repository.updateCompleter = Completer<Either<Failure, void>>();
    final provider = SettingsProvider(
      repository: repository,
      notificationService: _FakeNotificationService(),
      themePreferenceStore: ThemePreferenceStore(preferences),
      apiClient: ApiClient(enableLogging: false),
    );
    await provider.loadSettings('user-1');
    var notifications = 0;
    provider.addListener(() => notifications++);

    final update = provider.updateTheme('dark');

    expect(provider.theme, 'dark');
    expect(provider.themeMode, ThemeMode.dark);
    expect(notifications, 1);

    repository.updateCompleter!.complete(const Right(null));
    await update;
  });

  test('migrates legacy user theme when local preference is absent', () async {
    final provider = await _createProvider(
      loadedSettings: const Settings(id: 1, userId: 'user-1', theme: 'dark'),
    );

    await provider.loadSettings('user-1');

    expect(provider.theme, 'dark');
  });

  test('local preference wins when user settings load later', () async {
    final provider = await _createProvider(
      initialPreferences: {AppConstants.themeModeKey: 'light'},
      loadedSettings: const Settings(id: 1, userId: 'user-1', theme: 'dark'),
    );

    await provider.loadSettings('user-1');

    expect(provider.theme, 'light');
    expect(provider.settings?.theme, 'light');
  });

  test('invalid requested theme normalizes to system', () async {
    final provider = await _createProvider();

    await provider.updateTheme('sepia');

    expect(provider.theme, 'system');
    expect(provider.themeMode, ThemeMode.system);
  });

  test('repository failure does not roll back effective theme', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeSettingsRepository(
      loadedSettings: const Settings(id: 1, userId: 'user-1'),
    )..updateResult = Left(CacheFailure('write failed'));
    final provider = SettingsProvider(
      repository: repository,
      notificationService: _FakeNotificationService(),
      themePreferenceStore: ThemePreferenceStore(preferences),
      apiClient: ApiClient(enableLogging: false),
    );
    await provider.loadSettings('user-1');

    await provider.updateTheme('dark');

    expect(provider.theme, 'dark');
    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.error, 'write failed');
  });

  testWidgets('updates locale before language persistence completes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeSettingsRepository(
      loadedSettings: const Settings(
        id: 1,
        userId: 'user-1',
        language: 'vi',
      ),
    );
    repository.updateCompleter = Completer<Either<Failure, void>>();
    final provider = SettingsProvider(
      repository: repository,
      notificationService: _FakeNotificationService(),
      themePreferenceStore: ThemePreferenceStore(preferences),
    );
    await provider.loadSettings('user-1');

    late BuildContext localeContext;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [
          Locale('vi'),
          Locale('en'),
          Locale('fr'),
        ],
        path: 'assets/i18n',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('vi'),
        useOnlyLangCode: true,
        assetLoader: const _TestLocalizationLoader(),
        child: Builder(
          builder: (context) {
            return MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Builder(
                builder: (context) {
                  localeContext = context;
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final update = provider.updateLanguage('fr', localeContext);
    await tester.pumpAndSettle();

    expect(provider.language, 'fr');
    expect(await LocaleService.getSavedLocale(), 'fr');
    expect(preferences.getString('lexi_app_locale'), 'fr');
    expect(repository.lastUpdatedSettings?.language, 'fr');

    repository.updateCompleter!.complete(const Right(null));
    await update;
  });

  test('serializes rapid theme persistence in selection order', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeSettingsRepository(
      loadedSettings: const Settings(id: 1, userId: 'user-1'),
    );
    repository.updateCompleter = Completer<Either<Failure, void>>();
    final provider = SettingsProvider(
      repository: repository,
      notificationService: _FakeNotificationService(),
      themePreferenceStore: ThemePreferenceStore(preferences),
      apiClient: ApiClient(enableLogging: false),
    );
    await provider.loadSettings('user-1');

    final darkUpdate = provider.updateTheme('dark');
    final lightUpdate = provider.updateTheme('light');

    expect(provider.theme, 'light');
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastUpdatedSettings?.theme, 'dark');

    repository.updateCompleter!.complete(const Right(null));
    await Future.wait([darkUpdate, lightUpdate]);

    expect(repository.lastUpdatedSettings?.theme, 'light');
    expect(preferences.getString(AppConstants.themeModeKey), 'light');
  });

  test('local theme persistence is not blocked by settings sync', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeSettingsRepository(
      loadedSettings: const Settings(id: 1, userId: 'user-1'),
    );
    repository.updateCompleter = Completer<Either<Failure, void>>();
    final provider = SettingsProvider(
      repository: repository,
      notificationService: _FakeNotificationService(),
      themePreferenceStore: ThemePreferenceStore(preferences),
      apiClient: ApiClient(enableLogging: false),
    );
    await provider.loadSettings('user-1');

    final darkUpdate = provider.updateTheme('dark');
    final lightUpdate = provider.updateTheme('light');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(preferences.getString(AppConstants.themeModeKey), 'light');

    repository.updateCompleter!.complete(const Right(null));
    await Future.wait([darkUpdate, lightUpdate]);
  });

  testWidgets('changing provider theme rebuilds MaterialApp immediately', (
    tester,
  ) async {
    final provider = await _createProvider(
      initialPreferences: {AppConstants.themeModeKey: 'light'},
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: settings.themeMode,
              themeAnimationDuration: Duration.zero,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      Text(
                        Theme.of(context).brightness.name,
                        key: const Key('effective-brightness'),
                      ),
                      TextButton(
                        key: const Key('select-dark-theme'),
                        onPressed: () => settings.updateTheme('dark'),
                        child: const Text('Dark'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('light'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-dark-theme')));
    await tester.pump();

    expect(find.text('dark'), findsOneWidget);
  });
}
