import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/facebook_sign_in.dart';
import 'package:mockito/mockito.dart';

/// An account that can be proven with Google or with a password.
class _Auth extends Mock with ChangeNotifier implements AuthProvider {
  _Auth({this.methods = const ['google', 'password']});

  final List<String> methods;
  var step = FacebookMergeStep.none;
  var dismissed = 0;
  var googleSignIns = 0;

  @override
  Future<void> signInWithFacebook() async =>
      step = FacebookMergeStep.signInToMerge;

  @override
  FacebookMergeStep get facebookMergeStep => step;

  @override
  String? get facebookMergeEmail =>
      'a.very.long.address.of.a.learner@example.com';

  @override
  bool get facebookMergeAllowsGoogle => methods.contains('google');

  @override
  bool get facebookMergeAllowsPassword => methods.contains('password');

  @override
  Future<void> signInWithGoogle() async => googleSignIns++;

  @override
  void dismissFacebookLink() {
    dismissed++;
    step = FacebookMergeStep.none;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => EasyLocalization.logger.enableLevels = []);

  var toPassword = 0;

  Future<void> open(WidgetTester tester, _Auth auth) async {
    toPassword = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => signInWithFacebookOrLink(
              context,
              auth,
              toPasswordForm: () => toPassword++,
            ),
            child: const Text('facebook'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('facebook'));
    await tester.pumpAndSettle();
  }

  testWidgets('choosing the password keeps the merge waiting', (tester) async {
    final auth = _Auth();
    await open(tester, auth);

    await tester.tap(find.text('auth.fbMergeUsePassword'));
    await tester.pumpAndSettle();

    expect(auth.dismissed, 0);
    expect(auth.step, FacebookMergeStep.signInToMerge);
    expect(toPassword, 1);
  });

  testWidgets('"not now" on a Google-only account drops the merge', (
    tester,
  ) async {
    final auth = _Auth(methods: ['google']);
    await open(tester, auth);

    await tester.tap(find.text('auth.fbMergeNotNow'));
    await tester.pumpAndSettle();

    expect(auth.dismissed, 1);
    expect(toPassword, 0);
  });

  testWidgets('the question fits a small phone with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await open(tester, _Auth());

    expect(tester.takeException(), isNull);
  });

  testWidgets('both answers are the same height when one label wraps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await open(tester, _Auth(methods: ['google']));

    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      tester.getSize(find.byType(FilledButton)).height,
    );
  });
}
