import 'package:flutter/material.dart';
import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/get_current_user_new_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/login_with_google_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/register_usecase.dart';

/// Auth provider using backend API with proper error handling
class AuthBackendProvider extends ChangeNotifier {
  final RegisterUseCase registerUseCase;
  final LoginUseCase loginUseCase;
  final LoginWithGoogleUseCase loginWithGoogleUseCase;
  final LogoutUseCase logoutUseCase;
  final GetCurrentUserNewUseCase getCurrentUserUseCase;

  UserEntity? _user;
  bool _isLoading = false;
  String? _errorMessage;

  AuthBackendProvider({
    required this.registerUseCase,
    required this.loginUseCase,
    required this.loginWithGoogleUseCase,
    required this.logoutUseCase,
    required this.getCurrentUserUseCase,
  }) {
    _checkCurrentUser();
  }

  UserEntity? get user => _user;
  UserEntity? get currentUser => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Check if user is already logged in
  Future<void> _checkCurrentUser() async {
    _isLoading = true;
    notifyListeners();

    final result = await getCurrentUserUseCase(const NoParams());
    
    result.fold(
      (failure) {
        // User not authenticated, that's okay
        _user = null;
      },
      (user) {
        _user = user;
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  /// Register new user
  Future<bool> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await registerUseCase(RegisterParams(
      email: email,
      username: username,
      password: password,
      displayName: displayName,
    ));

    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        _isLoading = false;
        notifyListeners();
        return false;
      },
      (user) {
        _user = user;
        _isLoading = false;
        notifyListeners();
        return true;
      },
    );
  }

  /// Login with email and password
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await loginUseCase(LoginParams(
      email: email,
      password: password,
    ));

    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        _isLoading = false;
        notifyListeners();
        return false;
      },
      (user) {
        _user = user;
        _isLoading = false;
        notifyListeners();
        return true;
      },
    );
  }

  /// Login with Google
  Future<bool> loginWithGoogle(String idToken) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await loginWithGoogleUseCase(
      GoogleLoginParams(idToken: idToken),
    );

    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        _isLoading = false;
        notifyListeners();
        return false;
      },
      (user) {
        _user = user;
        _isLoading = false;
        notifyListeners();
        return true;
      },
    );
  }

  /// Logout current user
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await logoutUseCase(const NoParams());
    
    _user = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Refresh current user data
  Future<void> refreshUser() async {
    final result = await getCurrentUserUseCase(const NoParams());
    
    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (user) {
        _user = user;
      },
    );
    
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get user-friendly error message
  String getUserFriendlyError(String? error) {
    if (error == null) return '';
    
    if (error.toLowerCase().contains('invalid credentials')) {
      return 'Email hoặc mật khẩu không đúng';
    } else if (error.toLowerCase().contains('already exists')) {
      return 'Email hoặc username đã được sử dụng';
    } else if (error.toLowerCase().contains('validation')) {
      return 'Thông tin không hợp lệ. Vui lòng kiểm tra lại';
    } else if (error.toLowerCase().contains('network') || 
               error.toLowerCase().contains('connection')) {
      return 'Không có kết nối mạng. Vui lòng thử lại';
    } else if (error.toLowerCase().contains('rate limit')) {
      return 'Bạn đã thử quá nhiều lần. Vui lòng đợi một chút';
    }
    
    return error;
  }
}
