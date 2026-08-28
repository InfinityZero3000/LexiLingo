import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_course_suggestions.dart';

void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: child),
      );

  const courses = [
    LexiCourseSuggestion(
      courseId: 'c-1',
      title: 'Pre-Intermediate English',
      level: 'B1',
      totalLessons: 20,
    ),
    LexiCourseSuggestion(
      courseId: 'c-2',
      title: 'A course title long enough that it has to wrap onto a second line',
      level: 'B2',
      totalLessons: 12,
    ),
  ];

  testWidgets('renders one tappable card per suggested course', (tester) async {
    await tester.pumpWidget(wrap(const LexiCourseSuggestions(courses: courses)));

    expect(find.text('Pre-Intermediate English'), findsOneWidget);
    expect(find.text('B1'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('takes no space at all when there is nothing to suggest', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LexiCourseSuggestions(courses: [])));

    expect(find.byType(SizedBox), findsOneWidget);
    expect(tester.getSize(find.byType(SizedBox)), Size.zero);
  });

  testWidgets('a long title does not overflow the card', (tester) async {
    await tester.pumpWidget(wrap(const LexiCourseSuggestions(courses: courses)));
    await tester.pumpAndSettle();

    // An overflow paints as the yellow-and-black banner and records an
    // exception — a chat bubble is narrow, so this is the failure that would
    // actually happen in production.
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LexiCourseSuggestions(courses: courses),
        brightness: Brightness.dark,
      ),
    );

    expect(find.text('Pre-Intermediate English'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the carousel scrolls horizontally', (tester) async {
    await tester.pumpWidget(wrap(const LexiCourseSuggestions(courses: courses)));

    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
