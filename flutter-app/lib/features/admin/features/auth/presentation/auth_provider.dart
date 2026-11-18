import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import '../../../core/network/admin_api_error.dart';
import '../data/auth_repository.dart';

/// [forbidden]: signed in, but the account has no admin role.
/// [unauthenticated]: no learner session; the panel closes.
/// [failed]: the account could not be checked (network, server); retry.
enum AuthState { unknown, authenticated, forbidden, unauthenticated, failed }

/// Who is using the panel. There is no admin login: the panel borrows the
/// learner's session and only checks that the account is an admin.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository})
    : _repo = repository ?? AuthRepository();

  final AuthRepository _repo;

  AuthState _state = AuthState.unknown;
  AdminUser? _user;
  UiText? _error;

  AuthState get state => _state;
  AdminUser? get user => _user;
  UiText? get errorText => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isSuperAdmin => _user?.isSuperAdmin ?? false;
  bool get hasUserZoneAccess => _user?.hasUserZoneAccess ?? false;

  Future<void> init() async {
    _error = null;
    try {
      _user = await _repo.getMe();
      if (_user == null) {
        _state = AuthState.unauthenticated;
      } else {
        _state = _user!.mayUsePanel
            ? AuthState.authenticated
            : AuthState.forbidden;
      }
    } catch (e) {
      _user = null;
      _error = AdminApiError.from(e).message;
      _state = AuthState.failed;
    }
    notifyListeners();
  }

  Future<void> retry() {
    _state = AuthState.unknown;
    notifyListeners();
    return init();
  }
}
