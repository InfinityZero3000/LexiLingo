import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';

void registerHomeModule() {
  sl.registerFactory<HomeProvider>(
    () => HomeProvider(
      getCoursesUseCase: sl<GetCoursesUseCase>(),
      getEnrolledCoursesUseCase: sl<GetEnrolledCoursesUseCase>(),
      getWeeklyProgressUseCase: sl.isRegistered<GetWeeklyProgressUseCase>() 
          ? sl<GetWeeklyProgressUseCase>() 
          : null,
    ),
  );
}
