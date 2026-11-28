import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:lexilingo_app/features/auth/presentation/auth_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<NavigatorState> openOnTop(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('app root')));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Text('sign up')));
    await tester.pumpAndSettle();
    return nav;
  }

  testWidgets('signing in closes the pages stacked over the app', (
    tester,
  ) async {
    final nav = await openOnTop(tester);

    closeAuthPagesWhenSignedIn(nav, signedIn: true);
    await tester.pumpAndSettle();

    expect(find.text('app root'), findsOneWidget);
    expect(find.text('sign up'), findsNothing);
  });

  testWidgets('a sign-in that did not happen keeps the page', (tester) async {
    final nav = await openOnTop(tester);

    closeAuthPagesWhenSignedIn(nav, signedIn: false);
    await tester.pumpAndSettle();

    expect(find.text('sign up'), findsOneWidget);
  });

  testWidgets('going to log in rebuilds the app root, not a bare page, and '
      'skips the first-run welcome', (tester) async {
    final nav = await openOnTop(tester);

    await openLogin(nav);
    await tester.pumpAndSettle();

    expect(find.text('app root'), findsOneWidget);
    expect(nav.canPop(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.firstTimeUserKey), isFalse);
  });
}
