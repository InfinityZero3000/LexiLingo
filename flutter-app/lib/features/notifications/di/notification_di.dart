import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_local_datasource.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_remote_datasource.dart';
import 'package:lexilingo_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/notifications/domain/services/review_reminder_notification_sync_service.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Registers all notification-related dependencies
void registerNotificationModule() {
  // Data sources - Singleton
  sl.registerLazySingleton<NotificationLocalDataSource>(
    () => NotificationLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<NotificationRemoteDataSource>(
    () => NotificationRemoteDataSource(apiClient: sl<ApiClient>()),
  );

  // Repository - Singleton
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(
      sl<NotificationLocalDataSource>(),
      remoteDataSource: sl<NotificationRemoteDataSource>(),
    ),
  );
  sl.registerLazySingleton<ReviewReminderNotificationSyncService>(
    () => ReviewReminderNotificationSyncService(
      notificationRepository: sl<NotificationRepository>(),
      vocabularyRepository: sl<VocabularyRepository>(),
    ),
  );

  // Provider - Factory for fresh instances
  sl.registerFactory<NotificationProvider>(
    () => NotificationProvider(
      repository: sl<NotificationRepository>(),
      reviewReminderSyncService: sl<ReviewReminderNotificationSyncService>(),
    ),
  );
}
