import 'dart:async';

/// Broadcasts a signal when the user's session has permanently expired
/// (i.e. both access token and refresh token are invalid/expired).
///
/// Callers that detect an unrecoverable 401 (e.g. the token-refresh callback
/// in core_di.dart) call [notifyExpired]. Listeners (e.g. AuthProvider) clear
/// the local user state and redirect to the login screen.
class SessionExpiredService {
  static final _instance = SessionExpiredService._();
  static SessionExpiredService get instance => _instance;
  SessionExpiredService._();

  final _controller = StreamController<void>.broadcast();

  Stream<void> get onSessionExpired => _controller.stream;

  void notifyExpired() {
    if (!_controller.isClosed) _controller.add(null);
  }
}
