import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/streak_service.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_course_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_featured_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';

void registerHomeModule() {
  sl.registerFactoryParam<HomeProvider, UserProvider, void>(
    (userProvider, _) => HomeProvider(
      getFeaturedCoursesUseCase: sl<GetFeaturedCoursesUseCase>(),
      getEnrolledCoursesUseCase: sl<GetEnrolledCoursesUseCase>(),
      enrollCourseUseCase: sl<EnrollCourseUseCase>(),
      streakService: sl<StreakService>(),
      userProvider: userProvider,
    ),
  );
}
