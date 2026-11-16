import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:lexilingo_app/core/services/firebase_messaging_service.dart';
import 'package:lexilingo_app/features/notifications/domain/services/push_permission_gateway.dart';

import 'firebase_messaging_service_test.mocks.dart';

NotificationSettings _settings(AuthorizationStatus s) => NotificationSettings(
  alert: AppleNotificationSetting.enabled,
  announcement: AppleNotificationSetting.notSupported,
  authorizationStatus: s,
  badge: AppleNotificationSetting.enabled,
  carPlay: AppleNotificationSetting.notSupported,
  lockScreen: AppleNotificationSetting.enabled,
  notificationCenter: AppleNotificationSetting.enabled,
  showPreviews: AppleShowPreviewSetting.always,
  timeSensitive: AppleNotificationSetting.notSupported,
  criticalAlert: AppleNotificationSetting.notSupported,
  sound: AppleNotificationSetting.enabled,
  providesAppNotificationSettings: AppleNotificationSetting.notSupported,
);

void main() {
  late MockFirebaseMessaging messaging;
  late FirebaseMessagingService service;

  setUp(() {
    messaging = MockFirebaseMessaging();
    when(messaging.onTokenRefresh).thenAnswer((_) => const Stream.empty());
    when(messaging.getInitialMessage()).thenAnswer((_) async => null);
    when(
      messaging.getToken(vapidKey: anyNamed('vapidKey')),
    ).thenAnswer((_) async => 'tok');
    service = FirebaseMessagingService.forTesting(messaging: messaging);
  });

  test('initialize never shows the permission prompt', () async {
    when(
      messaging.getNotificationSettings(),
    ).thenAnswer((_) async => _settings(AuthorizationStatus.notDetermined));
    await service.initialize();
    verifyNever(
      messaging.requestPermission(
        alert: anyNamed('alert'),
        badge: anyNamed('badge'),
        sound: anyNamed('sound'),
      ),
    );
    verifyNever(messaging.getToken(vapidKey: anyNamed('vapidKey')));
    expect(service.token, isNull);
  });

  test(
    'initialize loads the token when permission was already granted',
    () async {
      when(
        messaging.getNotificationSettings(),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      await service.initialize();
      expect(service.token, 'tok');
    },
  );

  test('requestPermission prompts, then loads the token on grant', () async {
    when(
      messaging.requestPermission(
        alert: anyNamed('alert'),
        badge: anyNamed('badge'),
        sound: anyNamed('sound'),
      ),
    ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
    final result = await service.requestPermission();
    expect(result, PushPermission.granted);
    expect(service.token, 'tok');
  });

  test('requestPermission reports a refusal and fetches no token', () async {
    when(
      messaging.requestPermission(
        alert: anyNamed('alert'),
        badge: anyNamed('badge'),
        sound: anyNamed('sound'),
      ),
    ).thenAnswer((_) async => _settings(AuthorizationStatus.denied));
    expect(await service.requestPermission(), PushPermission.denied);
    expect(service.token, isNull);
  });
}
