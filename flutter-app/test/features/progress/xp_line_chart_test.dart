import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/xp_line_chart.dart';

WeeklyProgressEntity _week(List<int> xp) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final days = [
    for (var i = 0; i < xp.length; i++)
      DailyProgressEntity(
        day: names[i],
        date: DateTime(2026, 11, 9 + i),
        xpEarned: xp[i],
        lessonsCompleted: xp[i] > 0 ? 1 : 0,
        studyTimeMinutes: 0,
        vocabularyReviewed: 0,
        goalMet: false,
        isToday: i == xp.length - 1,
      ),
  ];
  return WeeklyProgressEntity(
    weekProgress: days,
    totalXP: xp.fold(0, (a, b) => a + b),
    totalLessons: 3,
    totalStudyTime: 0,
    daysActive: 3,
    currentStreak: 1,
    longestStreak: 1,
    weekGoalProgress: 0,
  );
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: 360, height: 220, child: child),
  ),
);

void main() {
  testWidgets('XP line keeps zero days above the edge and never overshoots', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(XpLineChart(weeklyProgress: _week([0, 40, 0, 64, 0, 0, 0]))),
    );

    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.minY, lessThan(0));
    expect(data.maxY, greaterThan(64));
    expect(data.minX, lessThan(0));
    expect(data.maxX, greaterThan(6));
    expect(data.lineBarsData.single.preventCurveOverShooting, isTrue);
    expect(data.titlesData.bottomTitles.sideTitles.interval, 1);
    expect(data.titlesData.leftTitles.sideTitles.showTitles, isFalse);
  });

  testWidgets('every weekday is labelled exactly once', (tester) async {
    await tester.pumpWidget(
      _host(XpLineChart(weeklyProgress: _week([0, 40, 0, 64, 0, 0, 10]))),
    );
    await tester.pumpAndSettle();

    for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(day), findsOneWidget, reason: day);
    }
  });

  testWidgets('lessons bars are labelled exactly once per day', (tester) async {
    await tester.pumpWidget(
      _host(LessonsBarChart(weeklyProgress: _week([0, 40, 0, 64, 0, 0, 10]))),
    );
    await tester.pumpAndSettle();

    for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(day), findsOneWidget, reason: day);
    }
  });
}
