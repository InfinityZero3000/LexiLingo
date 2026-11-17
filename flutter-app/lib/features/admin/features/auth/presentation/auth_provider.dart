import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import '../../../core/network/admin_api_error.dart';
import '../data/auth_repository.dart';

enum AuthState { unknown, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository, GoogleSignInService? googleSignIn})
    : _repo = repository ?? AuthRepository(),
      _googleSignIn = googleSignIn ?? GoogleSignInService();

  final AuthRepository _repo;
  final GoogleSignInService _googleSignIn;

  AuthState _state = AuthState.unknown;
  AdminUser? _user;
  UiText? _error;

  AuthState get state => _state;
  AdminUser? get user => _user;
  UiText? get errorText => _error;
  String? get error => _error?.resolve();
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isSuperAdmin => _user?.isSuperAdmin ?? false;
  bool get hasUserZoneAccess => _user?.hasUserZoneAccess ?? false;

  Future<void> init() async {
    _user = await _repo.getMe();
    _state = _user != null
        ? AuthState.authenticated
        : AuthState.unauthenticated;
    notifyListeners();
  }

  Future<bool> loginWithGoogle() async {
    _error = null;
    _state = AuthState.loading;
    notifyListeners();
    try {
      final idToken = await _googleSignIn.signIn();
      if (idToken == null) {
        _error = const UiText.key('admin.errors.googleCancelled');
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
      if (idToken == GoogleSignInService.redirectInProgressMarker) {
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
      _user = await _repo.loginWithGoogle(idToken);
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestOtp(String email) async {
    _error = null;
    _state = AuthState.loading;
    notifyListeners();
    try {
      await _repo.requestOtp(email);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp(String email, String otp) async {
    _error = null;
    _state = AuthState.loading;
    notifyListeners();
    try {
      _user = await _repo.verifyOtp(email, otp);
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    _user = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  UiText _parseError(Object e) {
    if (_mentionsMissingOAuth(e)) {
      return const UiText.key('admin.errors.oauthMissing');
    }
    final error = AdminApiError.from(e);
    switch (error.kind) {
      case AdminErrorKind.unauthorized:
        return const UiText.key('admin.errors.notVerified');
      case AdminErrorKind.forbidden:
        return const UiText.key('admin.errors.notAdmin');
      case AdminErrorKind.network:
      case AdminErrorKind.server:
        return error.message;
      default:
        return error.message;
    }
  }

  bool _mentionsMissingOAuth(Object e) {
    final body = e is DioException ? e.response?.data : null;
    return '$body $e'.contains('Admin Google OAuth not configured');
  }
}
