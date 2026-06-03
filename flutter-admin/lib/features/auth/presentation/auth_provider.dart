import 'package:flutter/foundation.dart';
import '../data/auth_repository.dart';

enum AuthState { unknown, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  final _repo = AuthRepository();

  AuthState _state = AuthState.unknown;
  AdminUser? _user;
  String? _error;

  AuthState get state => _state;
  AdminUser? get user => _user;
  String? get error => _error;
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

  Future<bool> loginWithPassword(String email, String password) async {
    _error = null;
    _state = AuthState.loading;
    notifyListeners();
    try {
      _user = await _repo.loginWithPassword(email, password);
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

  String _parseError(dynamic e) {
    final str = e.toString();
    if (str.contains('401')) return 'Email hoặc mật khẩu không đúng';
    if (str.contains('403')) return 'Tài khoản không có quyền truy cập admin';
    if (str.contains('400')) return 'Vui lòng nhập đầy đủ email và mật khẩu';
    if (str.contains('404')) {
      return 'API đăng nhập admin chưa sẵn sàng trên server';
    }
    if (str.contains('SocketException') || str.contains('connection')) {
      return 'Không thể kết nối máy chủ';
    }
    return 'Có lỗi xảy ra, vui lòng thử lại';
  }
}
