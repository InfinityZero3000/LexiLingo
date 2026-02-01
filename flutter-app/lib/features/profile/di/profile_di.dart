import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_weekly_activity_usecase.dart';

void registerProfileModule() {
  // Register ProfileProvider
  sl.registerFactory<ProfileProvider>(
    () => ProfileProvider(
      getUserStatsUseCase: sl<GetUserStatsUseCase>(),
      getWeeklyActivityUseCase: sl<GetWeeklyActivityUseCase>(),
    ),
  );
}
