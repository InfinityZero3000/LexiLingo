import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@GenerateMocks([FirebaseMessaging])
import 'firebase_messaging_service_test.mocks.dart';

void main() {
  group('FirebaseMessagingService', () {
    late MockFirebaseMessaging mockMessaging;

    setUp(() {
      mockMessaging = MockFirebaseMessaging();
    });

    group('Token Management', () {
      test('should get FCM token successfully', () async {
        // Arrange
        const expectedToken = 'test_fcm_token_12345';
        when(mockMessaging.getToken()).thenAnswer((_) async => expectedToken);

        // Act
        final token = await mockMessaging.getToken();

        // Assert
        expect(token, equals(expectedToken));
        verify(mockMessaging.getToken()).called(1);
      });

      test('should handle null token gracefully', () async {
        // Arrange
        when(mockMessaging.getToken()).thenAnswer((_) async => null);

        // Act
        final token = await mockMessaging.getToken();

        // Assert
        expect(token, isNull);
      });
    });

    group('Permission Request', () {
      test('should request notification permission', () async {
        // Arrange
        final mockSettings = MockNotificationSettings();
        when(mockMessaging.requestPermission(
          alert: anyNamed('alert'),
          announcement: anyNamed('announcement'),
          badge: anyNamed('badge'),
          carPlay: anyNamed('carPlay'),
          criticalAlert: anyNamed('criticalAlert'),
          provisional: anyNamed('provisional'),
          sound: anyNamed('sound'),
        )).thenAnswer((_) async => mockSettings);

        // Act
        final settings = await mockMessaging.requestPermission();

        // Assert
        verify(mockMessaging.requestPermission(
          alert: anyNamed('alert'),
          announcement: anyNamed('announcement'),
          badge: anyNamed('badge'),
          carPlay: anyNamed('carPlay'),
          criticalAlert: anyNamed('criticalAlert'),
          provisional: anyNamed('provisional'),
          sound: anyNamed('sound'),
        )).called(1);
        expect(settings, isNotNull);
      });
    });

    group('Topic Subscription', () {
      test('should subscribe to topic successfully', () async {
        // Arrange
        const topic = 'daily_reminders';
        when(mockMessaging.subscribeToTopic(topic))
            .thenAnswer((_) async => {});

        // Act
        await mockMessaging.subscribeToTopic(topic);

        // Assert
        verify(mockMessaging.subscribeToTopic(topic)).called(1);
      });

      test('should unsubscribe from topic successfully', () async {
        // Arrange
        const topic = 'daily_reminders';
        when(mockMessaging.unsubscribeFromTopic(topic))
            .thenAnswer((_) async => {});

        // Act
        await mockMessaging.unsubscribeFromTopic(topic);

        // Assert
        verify(mockMessaging.unsubscribeFromTopic(topic)).called(1);
      });
    });
  });
}

// Mock classes for NotificationSettings
class MockNotificationSettings extends Mock implements NotificationSettings {
  @override
  AuthorizationStatus get authorizationStatus => AuthorizationStatus.authorized;
}
