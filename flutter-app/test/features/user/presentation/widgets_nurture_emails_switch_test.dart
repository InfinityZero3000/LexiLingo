import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:lexilingo_app/features/user/presentation/widgets/nurture_emails_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo implements SettingsRepository {
  Either<Failure, void> result = const Right(null);

  @override
  Future<Either<Failure, Settings>> getSettings(String userId) async =>
      const Right(Settings(id: 1, userId: 'u1'));

  @override
  Future<Either<Failure, void>> updateSettings(Settings next) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications extends NotificationService {
  @override
  Future<void> ensureInitialized() async {}
}

Future<(SettingsProvider, _Repo)> _provider() async {
  SharedPreferences.setMockInitialValues({});
  final repo = _Repo();
  final provider = SettingsProvider(
    repository: repo,
    notificationService: _Notifications(),
    themePreferenceStore: ThemePreferenceStore(
      await SharedPreferences.getInstance(),
    ),
    apiClient: ApiClient(enableLogging: false),
    hasServerPush: () => false,
    deviceTimezone: () async => null,
  );
  await provider.loadSettings('u1');
  return (provider, repo);
}

Widget _host(SettingsProvider provider) => MaterialApp(
  home: Scaffold(
    body: ListenableBuilder(
      listenable: provider,
      builder: (_, _) =>
          NurtureEmailsSwitch(settings: provider, primaryColor: Colors.blue),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('is at least 44 px tall and starts on', (tester) async {
    final (provider, _) = await _provider();
    await tester.pumpWidget(_host(provider));

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      tester.getSize(find.byType(SwitchListTile)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('tapping turns it off', (tester) async {
    final (provider, _) = await _provider();
    await tester.pumpWidget(_host(provider));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(provider.nurtureEmailsEnabled, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed save rolls the switch back and shows a snackbar', (
    tester,
  ) async {
    final (provider, repo) = await _provider();
    repo.result = const Left(ServerFailure('offline'));
    await tester.pumpWidget(_host(provider));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(provider.nurtureEmailsEnabled, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
