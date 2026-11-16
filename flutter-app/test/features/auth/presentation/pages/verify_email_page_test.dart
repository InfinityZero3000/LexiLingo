import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/verify_email_page.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';

Widget _app(Widget page) => MaterialApp(
  routes: {'/': (_) => const Text('root')},
  initialRoute: '/verify',
  onGenerateRoute: (settings) =>
      MaterialPageRoute(settings: settings, builder: (_) => page),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => EasyLocalization.logger.enableLevels = []);

  testWidgets('a first verification signs in and leaves for the root route', (
    tester,
  ) async {
    String? used;
    await tester.pumpWidget(
      _app(
        VerifyEmailPage(
          token: 'tok',
          verify: (t) async {
            used = t;
            return VerifyEmailOutcome.signedIn;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(used, 'tok');
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('an already-used link offers the login form', (tester) async {
    await tester.pumpWidget(
      _app(
        VerifyEmailPage(
          token: 'tok',
          verify: (_) async => VerifyEmailOutcome.verified,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a dead link asks for the email to send a new one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        VerifyEmailPage(
          token: 'tok',
          verify: (_) async => VerifyEmailOutcome.failed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a missing token is treated as a dead link', (tester) async {
    var called = false;
    await tester.pumpWidget(
      _app(
        VerifyEmailPage(
          token: null,
          verify: (_) async {
            called = true;
            return VerifyEmailOutcome.signedIn;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });
}
