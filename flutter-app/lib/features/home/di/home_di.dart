import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/data/repositories/promo_banner_repository.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/promo_banner_provider.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

void registerHomeModule() {
  sl.registerFactory<HomeProvider>(
    () => HomeProvider(
      getCoursesUseCase: sl<GetCoursesUseCase>(),
      getEnrolledCoursesUseCase: sl<GetEnrolledCoursesUseCase>(),
      getWeeklyProgressUseCase: sl.isRegistered<GetWeeklyProgressUseCase>()
          ? sl<GetWeeklyProgressUseCase>()
          : null,
      vocabularyRepository: sl.isRegistered<VocabularyRepository>()
          ? sl<VocabularyRepository>()
          : null,
    ),
  );

  if (!sl.isRegistered<PromoBannerProvider>()) {
    sl.registerLazySingleton<PromoBannerProvider>(
      () => PromoBannerProvider(PromoBannerRepository(sl<ApiClient>())),
    );
  }
}
