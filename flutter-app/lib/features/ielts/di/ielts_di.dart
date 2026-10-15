import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';

void registerIeltsModule() {
  sl.registerLazySingleton<IeltsDataSource>(
    () => IeltsDataSource(apiClient: sl<ApiClient>()),
  );

  // Factory: one sitting per screen lifecycle, never shared between attempts.
  sl.registerFactory<IeltsProvider>(
    () => IeltsProvider(dataSource: sl<IeltsDataSource>()),
  );
}
