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
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingNotifications extends NotificationService {
  int permissionRequests = 0;
  int scheduled = 0;
  int cancelled = 0;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> requestPermissions() async {
    permissionRequests += 1;
    return true;
  }

  @override
  Future<void> scheduleDailyReminder(TimeOfDay time, {int dueCount = 0}) async {
    scheduled += 1;
  }

  @override
  Future<void> cancelDailyReminder() async {
    cancelled += 1;
  }
}

class _Repo implements SettingsRepository {
  _Repo(this.settings);

  Settings settings;
  Either<Failure, void> updateResult = const Right(null);
  final List<Settings> updates = [];

  @override
  Future<Either<Failure, Settings>> getSettings(String userId) async =>
      Right(settings);

  @override
  Future<Either<Failure, void>> updateSettings(Settings next) async {
    updates.add(next);
    return updateResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(SettingsProvider, _Repo, _RecordingNotifications)> _build({
  bool serverPush = false,
  String? deviceZone,
  Settings settings = const Settings(id: 1, userId: 'u1'),
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _Repo(settings);
  final notifications = _RecordingNotifications();
  final provider = SettingsProvider(
    repository: repo,
    notificationService: notifications,
    themePreferenceStore: ThemePreferenceStore(
      await SharedPreferences.getInstance(),
    ),
    apiClient: ApiClient(enableLogging: false),
    hasServerPush: () => serverPush,
    deviceTimezone: () async => deviceZone,
  );
  return (provider, repo, notifications);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening the app never asks for notification permission', () async {
    final (provider, _, notifications) = await _build();

    await provider.loadSettings('u1');
    await _settle();

    expect(notifications.permissionRequests, 0);
  });

  test(
    'switching reminders on asks for permission and schedules locally',
    () async {
      final (provider, _, notifications) = await _build(
        settings: const Settings(
          id: 1,
          userId: 'u1',
          notificationEnabled: false,
        ),
      );
      await provider.loadSettings('u1');
      await _settle();

      await provider.updateNotificationSettings(enabled: true);
    await _settle();

      expect(notifications.permissionRequests, 1);
      expect(notifications.scheduled, 1);
    },
  );

  test(
    'with server push available the local reminder is cancelled, not duplicated',
    () async {
      final (provider, _, notifications) = await _build(serverPush: true);
      await provider.loadSettings('u1');
      await _settle();

      await provider.updateReminderChannels(pushEnabled: true);
    await _settle();

      expect(notifications.scheduled, 0);
      expect(notifications.cancelled, greaterThan(0));
    },
  );

  test(
    'a device in another time zone is written back to the reminder settings',
    () async {
      final (provider, repo, _) = await _build(deviceZone: 'Europe/Paris');

      await provider.loadSettings('u1');
      await _settle();

      expect(repo.updates.single.reminderTimezone, 'Europe/Paris');
      expect(provider.settings?.reminderTimezone, 'Europe/Paris');
    },
  );

  test('a matching or unknown device zone writes nothing', () async {
    final (provider, repo, _) = await _build(deviceZone: 'Asia/Ho_Chi_Minh');

    await provider.loadSettings('u1');
    await _settle();

    expect(repo.updates, isEmpty);
  });

  test('a failed zone sync leaves the stored zone as it was', () async {
    final (provider, repo, _) = await _build(deviceZone: 'Europe/Paris');
    repo.updateResult = Left(ServerFailure('offline'));

    await provider.loadSettings('u1');
    await _settle();

    expect(provider.settings?.reminderTimezone, 'Asia/Ho_Chi_Minh');
  });

  test('a rejected reminder save rolls the toggle back', () async {
    final (provider, repo, _) = await _build();
    await provider.loadSettings('u1');
    await _settle();
    repo.updateResult = Left(ServerFailure('boom'));

    await provider.updateReminderChannels(emailEnabled: true);

    expect(provider.settings?.emailReminderEnabled, isFalse);
    expect(provider.error, 'boom');
  });
}
