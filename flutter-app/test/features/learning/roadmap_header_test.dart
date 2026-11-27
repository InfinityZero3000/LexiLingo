import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/roadmap_header_widget.dart';

void main() {
  testWidgets('0% progress looks empty and the CEFR badge is readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: RoadmapHeaderWidget(
            onBack: () {},
            roadmap: const CourseRoadmap(
              courseId: 'c',
              courseTitle: 'English for Travel',
              level: 'A2',
              totalUnits: 1,
              completedUnits: 0,
              totalLessons: 3,
              completedLessons: 0,
              completionPercentage: 0,
              totalXpEarned: 0,
              currentStreak: 1,
              units: [],
            ),
          ),
        ),
      ),
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.backgroundColor, isNot(bar.valueColor!.value));
    expect(bar.backgroundColor!.a, lessThan(0.5));
    expect(
      tester.widget<Text>(find.text('A2')).style!.color,
      isNot(AppTheme.lightTheme.primaryColor),
    );
  });
}
