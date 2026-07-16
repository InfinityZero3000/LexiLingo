import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_list_screen.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_models.dart';
import 'package:lexilingo_app/features/voice/presentation/screens/voice_practice_screen.dart';

void openTodayPlanTask(BuildContext context, TodayPlanTask task) {
  switch (task.destination) {
    case TodayPlanDestination.vocabularyReview:
      Navigator.of(context).pushNamed('/vocabulary/review');
      return;
    case TodayPlanDestination.courseList:
      LearnerRoute.push(context, (_) => const CourseListScreen());
      return;
    case TodayPlanDestination.games:
      Navigator.of(context).pushNamed('/games');
      return;
    case TodayPlanDestination.lexi:
      Navigator.of(context).pushNamed('/lexi');
      return;
    case TodayPlanDestination.voice:
      LearnerRoute.push(context, (_) => const VoicePracticeScreen());
      return;
    case TodayPlanDestination.news:
      Navigator.of(context).pushNamed('/news');
      return;
    case TodayPlanDestination.podcast:
      Navigator.of(context).pushNamed('/podcast');
      return;
  }
}
