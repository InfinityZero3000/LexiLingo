import 'dart:async';

import 'package:flutter/widgets.dart';

import '../user_session_sync.dart';

/// What the gate needs to know about the auth state at one moment.
class SessionSnapshot {
  const SessionSnapshot({
    required this.checking,
    required this.authenticated,
    this.userId,
  });

  final bool checking;
  final bool authenticated;
  final String? userId;
}

/// What the gate does to the app's state; tests replace it to see the order.
class SessionActions {
  const SessionActions();

  Future<void> signedOut(BuildContext context) =>
      UserSessionSync.onSignedOut(context);

  Future<void> beforeSignIn(
    BuildContext context,
    SessionChange change,
    String? userId,
  ) => UserSessionSync.beforeSignIn(context, change, userId: userId);

  Future<void> afterSignIn(BuildContext context) =>
      UserSessionSync.afterSignIn(context);
}

/// Follows the auth state from a listener rather than from build. It runs in
/// the notification itself, before any frame builds for the new state, so the
/// previous learner's data is gone before the next learner's screens can load
/// or paint it. An account switch has no signed-out frame in between: it ends
/// the old session here, synchronously, then signs the new one in.
class SessionSyncGate extends StatefulWidget {
  const SessionSyncGate({
    super.key,
    required this.listenable,
    required this.read,
    required this.child,
    this.actions = const SessionActions(),
    this.onSignedOut,
    this.onSignedIn,
    this.onSessionStart,
    this.onSessionStarted,
  });

  final Listenable listenable;
  final SessionSnapshot Function() read;
  final Widget child;
  final SessionActions actions;

  /// The app shell's own state when the learner signed out.
  final VoidCallback? onSignedOut;

  /// The app shell's own state when a new session begins (sign-in or switch).
  final VoidCallback? onSignedIn;

  /// Runs after the previous session's data is gone, before the new learner's
  /// first loads.
  final void Function(BuildContext context)? onSessionStart;

  /// Runs after the new learner's first loads have been started.
  final VoidCallback? onSessionStarted;

  @override
  State<SessionSyncGate> createState() => _SessionSyncGateState();
}

class _SessionSyncGateState extends State<SessionSyncGate> {
  final SessionTracker _tracker = SessionTracker();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(SessionSyncGate old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_sync);
      widget.listenable.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final snapshot = widget.read();
    if (snapshot.checking) return;
    final change = _tracker.update(
      authenticated: snapshot.authenticated,
      userId: snapshot.userId,
    );
    switch (change) {
      case SessionChange.none:
        return;
      case SessionChange.signedOut:
        unawaited(widget.actions.signedOut(context));
        widget.onSignedOut?.call();
      case SessionChange.signedIn || SessionChange.accountSwitched:
        final cleanup = widget.actions.beforeSignIn(
          context,
          change,
          snapshot.userId,
        );
        widget.onSignedIn?.call();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await cleanup;
          if (!mounted) return;
          widget.onSessionStart?.call(context);
          unawaited(widget.actions.afterSignIn(context));
          widget.onSessionStarted?.call();
        });
        // A listener can fire when nothing else asks for a frame.
        WidgetsBinding.instance.scheduleFrame();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
