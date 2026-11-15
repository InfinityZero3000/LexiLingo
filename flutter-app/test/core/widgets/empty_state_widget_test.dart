import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: child),
    ),
  );

  testWidgets('the entrance runs once and settles, so screens can settle', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        EmptyStateWidget(
          icon: Icons.people_outline,
          title: 'Nothing yet',
          description: 'Follow someone',
          actionLabel: 'Find friends',
          onAction: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.people_outline), findsOneWidget);
    await tester.tap(find.text('Find friends'));
    expect(taps, 1);
  });

  testWidgets('without an icon it is text only', (tester) async {
    await tester.pumpWidget(host(const EmptyStateWidget(title: 'No results')));
    await tester.pumpAndSettle();

    expect(find.byType(Icon), findsNothing);
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final state on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const EmptyStateWidget(icon: Icons.search_off, title: 'No results'),
        reduceMotion: true,
      ),
    );

    expect(tester.hasRunningAnimations, isFalse);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('No results'),
        matching: find.byType(FadeTransition),
      ).first,
    );
    expect(fade.opacity.value, 1);
  });
}
