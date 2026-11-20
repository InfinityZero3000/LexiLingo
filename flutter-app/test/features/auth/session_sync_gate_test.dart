import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/presentation/user_session_sync.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/session_sync_gate.dart';

class _Auth extends ChangeNotifier {
  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  bool get attached => listeners > 0;

  bool checking = false;
  bool authenticated = false;
  String? userId;

  void signIn(String id) {
    authenticated = true;
    userId = id;
    notifyListeners();
  }

  void signOut() {
    authenticated = false;
    userId = null;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

class _Recorded extends SessionActions {
  _Recorded(this.log);
  final List<String> log;

  @override
  Future<void> signedOut(BuildContext context) async => log.add('signedOut');

  @override
  Future<void> beforeSignIn(
    BuildContext context,
    SessionChange change,
    String? userId,
  ) async => log.add('beforeSignIn:${change.name}:$userId');

  @override
  Future<void> afterSignIn(BuildContext context) async =>
      log.add('afterSignIn');
}

void main() {
  late _Auth auth;
  late List<String> log;

  Future<void> pump(WidgetTester tester, {Listenable? listenable}) =>
      tester.pumpWidget(
        SessionSyncGate(
          listenable: listenable ?? auth,
          read: () => SessionSnapshot(
            checking: auth.checking,
            authenticated: auth.authenticated,
            userId: auth.userId,
          ),
          actions: _Recorded(log),
          onSignedOut: () => log.add('shell:signedOut'),
          onSignedIn: () => log.add('shell:signedIn'),
          onSessionStart: (_) => log.add('start'),
          onSessionStarted: () => log.add('started'),
          child: const SizedBox(),
        ),
      );

  setUp(() {
    auth = _Auth();
    log = [];
  });

  testWidgets('signing out resets at once, in the notification itself', (
    tester,
  ) async {
    await pump(tester);
    auth.signIn('a');
    await tester.pump();
    log.clear();

    auth.signOut();

    expect(log, ['signedOut', 'shell:signedOut'], reason: 'before any frame');
  });

  testWidgets('an account switch resets before the new learner loads', (
    tester,
  ) async {
    await pump(tester);
    auth.signIn('a');
    await tester.pump();
    log.clear();

    auth.signIn('b');
    expect(log, ['beforeSignIn:accountSwitched:b', 'shell:signedIn']);

    await tester.pump();
    await tester.pump();
    expect(log, [
      'beforeSignIn:accountSwitched:b',
      'shell:signedIn',
      'start',
      'afterSignIn',
      'started',
    ]);
    expect(
      log.indexOf('beforeSignIn:accountSwitched:b'),
      lessThan(log.indexOf('afterSignIn')),
    );
  });

  testWidgets('a first sign-in is not a switch', (tester) async {
    await pump(tester);

    auth.signIn('a');
    await tester.pump();
    await tester.pump();

    expect(log.first, 'beforeSignIn:signedIn:a');
    expect(log, contains('afterSignIn'));
  });

  testWidgets('a refresh of the same user does nothing', (tester) async {
    await pump(tester);
    auth.signIn('a');
    await tester.pump();
    await tester.pump();
    log.clear();

    auth.refresh();
    auth.refresh();
    await tester.pump();

    expect(log, isEmpty);
  });

  testWidgets('nothing happens while the app is still checking', (
    tester,
  ) async {
    auth.checking = true;
    await pump(tester);

    auth.authenticated = true;
    auth.userId = 'a';
    auth.refresh();
    await tester.pump();

    expect(log, isEmpty);
  });

  testWidgets('disposing removes the listener', (tester) async {
    await pump(tester);
    expect(auth.attached, isTrue);

    await tester.pumpWidget(const SizedBox());

    expect(auth.attached, isFalse);
    auth.signIn('a'); // must not reach a disposed gate
    expect(log, isEmpty);
  });

  testWidgets('replacing the listenable moves the listener', (tester) async {
    await pump(tester);
    final other = _Auth();

    await pump(tester, listenable: other);

    expect(auth.attached, isFalse);
    expect(other.attached, isTrue);
  });
}
