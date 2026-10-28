import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/points_calendar_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const streak = StreakEntity(
    currentStreak: 3,
    longestStreak: 5,
    totalDaysActive: 10,
    freezeCount: 0,
    isActiveToday: true,
    streakAtRisk: false,
  );

  // Short phone, phone, and a desktop-width browser window (the three shapes
  // that overflowed or ballooned the calendar cells).
  for (final size in const [Size(393, 560), Size(393, 852), Size(1280, 800)]) {
    testWidgets('calendar dialog does not overflow at $size', (tester) async {
      SharedPreferences.setMockInitialValues({
        'checkin_reminder_enabled': true,
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPointsCalendarDialog(context, streak),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Bottom only: Ahem + untranslated keys make horizontal overflow noise.
      expect(
        tester.takeException()?.toString() ?? '',
        isNot(contains('bottom')),
      );
      expect(
        tester.getSize(find.byType(ClipRRect).first).width,
        lessThanOrEqualTo(420),
      );
    });
  }
}
