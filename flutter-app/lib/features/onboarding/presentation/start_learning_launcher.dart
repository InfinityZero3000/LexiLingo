import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/injection_container.dart' as di;
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';
import 'package:lexilingo_app/features/onboarding/presentation/pages/start_learning_page.dart';
import 'package:lexilingo_app/features/onboarding/presentation/providers/start_learning_provider.dart';
import 'package:provider/provider.dart';

/// Opens the start-learning step as its own route; on success the route is
/// replaced by the first lesson, so back from the lesson lands where it began.
abstract final class StartLearningLauncher {
  static Widget sessionFor(StartLearningTarget target) => LearningSessionScreen(
    lessonId: target.firstLessonId,
    courseId: target.courseId,
  );

  static Future<void> open(
    BuildContext context, {
    String? courseId,
    StartLearningProvider Function()? providerFactory,
    Widget Function(StartLearningTarget)? sessionBuilder,
  }) {
    return LearnerRoute.push<void>(
      context,
      (_) => ChangeNotifierProvider<StartLearningProvider>(
        create: (_) =>
            (providerFactory ?? () => di.sl<StartLearningProvider>())(),
        child: Builder(
          builder: (inner) => StartLearningPage(
            courseId: courseId,
            onStarted: (target) => LearnerRoute.pushReplacement<void, void>(
              inner,
              (_) => (sessionBuilder ?? sessionFor)(target),
            ),
            onSkip: () => Navigator.of(inner).pop(),
          ),
        ),
      ),
    );
  }
}
