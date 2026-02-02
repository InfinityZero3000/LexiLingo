import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_local_datasource.dart';
import 'package:lexilingo_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';

/// Registers all notification-related dependencies
void registerNotificationModule() {
  // Data sources - Singleton
  sl.registerLazySingleton<NotificationLocalDataSource>(
    () => NotificationLocalDataSourceImpl(),
  );

  // Repository - Singleton
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(sl<NotificationLocalDataSource>()),
  );

  // Provider - Factory for fresh instances
  sl.registerFactory<NotificationProvider>(
    () => NotificationProvider(
      repository: sl<NotificationRepository>(),
    ),
  );
}
