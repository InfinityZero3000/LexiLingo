import 'dart:async';
import 'dart:typed_data';
import 'package:lexilingo_app/core/l10n/ui_text.dart';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/deep_link_service.dart';
import 'package:lexilingo_app/core/services/firebase_messaging_service.dart';
import 'package:lexilingo_app/core/services/google_sign_in_service.dart';
import 'package:lexilingo_app/core/services/purchases_service.dart';
import 'package:lexilingo_app/core/services/session_expired_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';

import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_facebook_usecase.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';

/// What opening an email verification link did.
enum VerifyEmailOutcome { signedIn, verified, failed }

class AuthProvider extends ChangeNotifier {
  final SignInWithGoogleUseCase signInWithGoogleUseCase;
  final SignInWithFacebookUseCase signInWithFacebookUseCase;
  final SignInWithEmailPasswordUseCase signInWithEmailPasswordUseCase;
  final SignOutUseCase signOutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  final RegisterUseCase registerUseCase;
  final AuthRepository authRepository;
  final GoogleSignInService googleSignInService;
  final FacebookSignInService facebookSignInService;

  /// The learner this device last confirmed with the server. With it a cold
  /// start opens the app at once, offline included, and the network only
  /// confirms; without it every start waits on the network and any hiccup lands
  /// a signed-in learner on the login page.
  final Future<UserEntity?> Function()? loadCachedUser;

  UserEntity? _user;
  Future<void>? _userRefresh;
  final Freshness _userFreshness = Freshness();
  String? _userFreshFor;
  bool _isLoading = false;
  bool _isCheckingAuth = true;
  bool _isJustLoggedIn = false;
  UiText? _errorMessage;
  FacebookLinkRequired? _pendingFacebookLink;
  late final StreamSubscription<void> _sessionExpiredSub;

  AuthProvider({
    required this.signInWithGoogleUseCase,
    required this.signInWithFacebookUseCase,
    required this.signInWithEmailPasswordUseCase,
    required this.signOutUseCase,
    required this.getCurrentUserUseCase,
    required this.registerUseCase,
    required this.authRepository,
    required this.googleSignInService,
    required this.facebookSignInService,
    this.loadCachedUser,
  }) {
    _checkCurrentUser();
    _sessionExpiredSub = SessionExpiredService.instance.onSessionExpired.listen(
      (_) => _onSessionExpired(),
    );
  }

  void _onSessionExpired() {
    final ended = _user?.id;
    _user = null;
    _pendingFacebookLink = null;
    _errorMessage = null;
    _isJustLoggedIn = false;
    UserScopeService.clearActiveUserId(expected: ended);
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _sessionExpiredSub.cancel();
    super.dispose();
  }

  /// The session check and the sign-in flows finish after awaits; the learner
  /// may have left by then, and notifying a disposed notifier throws.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // Getters
  UserEntity? get user => _user;
  UserEntity? get currentUser => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isJustLoggedIn => _isJustLoggedIn;
  String? get errorMessage => _errorMessage?.resolve();
  String? get facebookLinkEmail => _pendingFacebookLink?.email;

  void dismissFacebookLink() => _pendingFacebookLink = null;

  // Clear just logged in flag (call after welcome screen)
  void clearJustLoggedIn() {
    _isJustLoggedIn = false;
    notifyListeners();
  }

  /// Concurrent calls share one `/users/me`. [maxAge] lets passive callers skip
  /// a reload for the same user fetched that recently.
  Future<void> refreshCurrentUser({Duration? maxAge}) {
    final current = _user;
    if (current != null &&
        current.id == _userFreshFor &&
        _userFreshness.isFresh(maxAge)) {
      return Future<void>.value();
    }
    final inFlight = _userRefresh;
    if (inFlight != null) return inFlight;
    final run = _refreshCurrentUser();
    _userRefresh = run;
    return run.whenComplete(() {
      if (identical(_userRefresh, run)) _userRefresh = null;
    });
  }

  Future<void> _refreshCurrentUser() async {
    final result = await getCurrentUserUseCase(NoParams());
    result.fold((failure) => _errorMessage = _getFailureMessage(failure), (
      user,
    ) {
      _user = user;
      _errorMessage = null;
      _markUserFresh(user);
    });
    notifyListeners();
  }

  /// The next passive [refreshCurrentUser] refetches; call after learning activity.
  void invalidateFreshness() => _userFreshness.invalidate();

  void _markUserFresh(UserEntity user) {
    _userFreshFor = user.id;
    _userFreshness.mark();
  }

  // Check current user on app start
  Future<void> _checkCurrentUser() async {
    try {
      _isCheckingAuth = true;
      notifyListeners();

      // Web redirect flow: if we just came back from Google, finish backend
      // sign-in before checking stored session.
      final pendingGoogleIdToken = await googleSignInService
          .consumePendingWebRedirectIdToken();
      if (pendingGoogleIdToken != null) {
        await _authenticateWithGoogleIdToken(pendingGoogleIdToken);
        return;
      }

      // Fast-path: if there are no local tokens, skip network call completely.
      final hasStoredSession = await authRepository.isAuthenticated();
      if (!hasStoredSession) {
        _user = null;
        _errorMessage = null;
        UserScopeService.clearActiveUserId();
        return;
      }

      final cached = await _readCachedUser();
      if (cached != null) {
        await UserScopeService.setActiveUserId(cached.id);
        _user = cached;
        _errorMessage = null;
        unawaited(_confirmCachedSession(cached.id));
        return;
      }

      // Nothing cached yet (first start after an update): the refresh inside
      // this call can take up to 15 s on a slow link, so wait longer than that
      // rather than send a learner with a valid session to the login page.
      final result = await getCurrentUserUseCase(NoParams()).timeout(
        const Duration(seconds: 20),
        onTimeout: () => Left(AuthFailure('Auth check timed out')),
      );
      result.fold(
        (failure) {
          // Don't show error for AuthFailure (401) - user just not logged in
          if (failure is AuthFailure || failure is UnauthorizedFailure) {
            _errorMessage = null; // Silent - normal state when not logged in
          } else {
            _errorMessage = _getFailureMessage(failure);
          }
          _user = null;
          UserScopeService.clearActiveUserId();
        },
        (user) {
          _user = user;
          _errorMessage = null;
          _markUserFresh(user);
          if (sl.isRegistered<ApiClient>()) {
            unawaited(
              FirebaseMessagingService.instance.registerTokenWithBackend(
                sl<ApiClient>(),
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint("Check current user error: $e");
      // Don't show error for auth check failures - user just not logged in
      _errorMessage = null;
      _user = null;
      UserScopeService.clearActiveUserId();
    } finally {
      _isCheckingAuth = false;
      notifyListeners();
    }
  }

  Future<UserEntity?> _readCachedUser() async {
    try {
      return await loadCachedUser?.call();
    } catch (e) {
      debugPrint('Cached session user unreadable: $e');
      return null;
    }
  }

  /// Confirms, behind an already open app, that the cached learner still has a
  /// session. The session ends only when the server refuses the refresh token:
  /// that clears the tokens and reaches [_onSessionExpired] through
  /// [SessionExpiredService]. Being offline, a restarting server or a timeout
  /// prove nothing about the session, so they change nothing.
  Future<void> _confirmCachedSession(String userId) async {
    final result = await getCurrentUserUseCase(NoParams()).timeout(
      const Duration(seconds: 30),
      onTimeout: () => const Left(NetworkFailure('Session check timed out')),
    );
    // Signed out, expired or switched account while the request was in flight.
    if (_user?.id != userId) return;

    final confirmed = result.fold((_) => null, (user) => user);
    if (confirmed != null) {
      _user = confirmed;
      _errorMessage = null;
      _markUserFresh(confirmed);
      notifyListeners();
      if (sl.isRegistered<ApiClient>()) {
        unawaited(
          FirebaseMessagingService.instance.registerTokenWithBackend(
            sl<ApiClient>(),
          ),
        );
      }
      return;
    }
    if (!await authRepository.isAuthenticated() && _user?.id == userId) {
      _onSessionExpired();
    }
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    _pendingFacebookLink = null;
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Get real ID token from Google Sign-In
      final idToken = await googleSignInService.signIn();
      if (idToken == GoogleSignInService.redirectInProgressMarker) {
        // Redirect flow has started, browser will navigate away.
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (idToken == null) {
        final signInError = googleSignInService.lastError?.toLowerCase();
        if (signInError == null || signInError.contains('cancelled')) {
          _errorMessage = UiText.key('auth.googleSignInCancelled');
        } else {
          _errorMessage = _parseErrorMessage(googleSignInService.lastError!);
        }
        _isLoading = false;
        notifyListeners();
        return;
      }

      await _authenticateWithGoogleIdToken(idToken);
    } catch (e) {
      debugPrint("Google sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _authenticateWithGoogleIdToken(String idToken) async {
    debugPrint('Google ID token obtained (length: ${idToken.length})');

    final result = await signInWithGoogleUseCase(
      SignInWithGoogleParams(idToken: idToken),
    );

    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _user = null;
        _isJustLoggedIn = false;
      },
      (user) {
        _user = user;
        _errorMessage = null;
        _isJustLoggedIn = true;
        FirebaseMessagingService.instance.registerTokenWithBackend(
          sl<ApiClient>(),
        );
        unawaited(_claimPendingReferral());
      },
    );
  }

  // Sign in with Facebook
  Future<void> signInWithFacebook() {
    _pendingFacebookLink = null;
    // Get Firebase ID token via Facebook authentication
    return _completeFacebookSignIn(facebookSignInService.signIn);
  }

  /// Finishes a sign-in that stopped on [facebookLinkEmail]. Call it from a tap.
  Future<void> linkFacebookWithGoogle() {
    final request = _pendingFacebookLink;
    if (request == null) return Future<void>.value();
    _pendingFacebookLink = null;
    return _completeFacebookSignIn(
      () => facebookSignInService.linkWithGoogle(request),
    );
  }

  Future<void> _completeFacebookSignIn(
    Future<String?> Function() obtainIdToken,
  ) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final idToken = await obtainIdToken();
      if (idToken == null) {
        _errorMessage = UiText.key('auth.facebookSignInCancelled');
        _isLoading = false;
        notifyListeners();
        return;
      }

      final result = await signInWithFacebookUseCase(
        SignInWithFacebookParams(idToken: idToken),
      );

      result.fold(
        (failure) {
          _errorMessage =
              FacebookSignInService.isExistingAccountRefusal(failure.message)
              ? const UiText.key('auth.errUseExistingSignIn')
              : _getFailureMessage(failure);
          _user = null;
          _isJustLoggedIn = false;
        },
        (user) {
          _user = user;
          _errorMessage = null;
          _isJustLoggedIn = true;
          FirebaseMessagingService.instance.registerTokenWithBackend(
            sl<ApiClient>(),
          );
          unawaited(_claimPendingReferral());
        },
      );
    } on FacebookLinkRequired catch (link) {
      _pendingFacebookLink = link;
    } catch (e) {
      debugPrint("Facebook sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in with email and password
  Future<void> signInWithEmailPassword(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final params = SignInWithEmailPasswordParams(
        email: email,
        password: password,
      );

      final result = await signInWithEmailPasswordUseCase(params);

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _user = null;
          _isJustLoggedIn = false;
        },
        (user) {
          _user = user;
          _errorMessage = null;
          _isJustLoggedIn = true;
          FirebaseMessagingService.instance.registerTokenWithBackend(
            sl<ApiClient>(),
          );
          unawaited(_claimPendingReferral());
        },
      );
    } catch (e) {
      debugPrint("Email sign in error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Request password reset link/email.
  Future<bool> requestPasswordReset(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.requestPasswordReset(email);

      return result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          return false;
        },
        (_) {
          _errorMessage = null;
          return true;
        },
      );
    } catch (e) {
      _errorMessage = _parseErrorMessage(e.toString());
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resend verification email.
  Future<bool> resendVerificationEmail(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.resendVerificationEmail(email);

      return result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          return false;
        },
        (_) {
          _errorMessage = null;
          return true;
        },
      );
    } catch (e) {
      _errorMessage = _parseErrorMessage(e.toString());
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Verify the mailed link. Signed in when it is the first verification.
  Future<VerifyEmailOutcome> verifyEmailLink(String token) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.verifyEmailAndSignIn(token);
      return result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          return VerifyEmailOutcome.failed;
        },
        (user) {
          if (user == null) return VerifyEmailOutcome.verified;
          _user = user;
          _isJustLoggedIn = true;
          FirebaseMessagingService.instance.registerTokenWithBackend(
            sl<ApiClient>(),
          );
          unawaited(_claimPendingReferral());
          return VerifyEmailOutcome.signedIn;
        },
      );
    } catch (e) {
      _errorMessage = _parseErrorMessage(e.toString());
      return VerifyEmailOutcome.failed;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset password with token from email link.
  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.resetPassword(
        token: token,
        newPassword: newPassword,
      );

      return result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          return false;
        },
        (_) {
          _errorMessage = null;
          return true;
        },
      );
    } catch (e) {
      _errorMessage = _parseErrorMessage(e.toString());
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Claim a pending referral code stored by DeepLinkService before sign-in.
  Future<void> _claimPendingReferral() async {
    final code = DeepLinkService.instance.pendingReferralCode;
    if (code == null) return;
    DeepLinkService.instance.pendingReferralCode = null;
    try {
      await sl<ApiClient>().post('/referral/claim/$code', body: {});
      debugPrint('Referral code $code claimed successfully');
    } catch (e) {
      debugPrint('Referral claim failed (non-blocking): $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Needs the live session, so it goes before the sign-out request.
      await FirebaseMessagingService.instance.unregisterFromBackend(
        sl<ApiClient>(),
      );
      await googleSignInService.signOut();
      await signOutUseCase(NoParams());
      // Clear stored FCM token so it gets re-registered on next login
      await FirebaseMessagingService.instance.clearRegisteredToken();
      await PurchasesService.instance.logout();
      _user = null;
    } catch (e) {
      debugPrint("Sign out error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Permanently delete current user account (GDPR hard delete)
  Future<void> deleteAccount() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final apiClient = sl<ApiClient>();
      await apiClient.delete('/users/me/permanent');

      await googleSignInService.signOut();
      await signOutUseCase(NoParams());
      await FirebaseMessagingService.instance.clearRegisteredToken();
      _user = null;
    } catch (e) {
      debugPrint("Delete account error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Register new user
  Future<void> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final params = RegisterParams(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
      );

      final result = await registerUseCase(params);

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _user = null;
          _isJustLoggedIn = false;
        },
        (_) {
          _user = null;
          _errorMessage = null;
          _isJustLoggedIn = false;
        },
      );
    } catch (e) {
      debugPrint("Register error: $e");
      _errorMessage = _parseErrorMessage(e.toString());
      _user = null;
      _isJustLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user profile (display name, avatar)
  Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.updateProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
      );

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          throw Exception(_errorMessage);
        },
        (updatedUser) {
          _user = updatedUser;
          _errorMessage = null;
        },
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves which language Lexi explains in. The choice shows at once and is
  /// put back if the server refuses it.
  Future<bool> updateLexiReplyLanguage(String value) async {
    final previous = _user;
    if (previous == null) return false;
    if (previous.lexiReplyLanguage == value) return true;
    _user = previous.copyWith(lexiReplyLanguage: value);
    notifyListeners();

    final result = await authRepository.updateProfile(lexiReplyLanguage: value);
    return result.fold(
      (failure) {
        _user = previous;
        _errorMessage = _getFailureMessage(failure);
        notifyListeners();
        return false;
      },
      (updatedUser) {
        _user = updatedUser;
        notifyListeners();
        return true;
      },
    );
  }

  /// Upload a picked image as the avatar; throws on failure.
  Future<void> uploadAvatar(Uint8List bytes, String filename) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final result = await authRepository.uploadAvatar(
        bytes: bytes,
        filename: filename,
      );

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          throw Exception(_errorMessage);
        },
        (updatedUser) {
          _user = updatedUser;
          _errorMessage = null;
        },
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit onboarding payload once at the end of onboarding flow.
  ///
  /// [displayName] and [nativeLanguage] are optional overrides from the
  /// pre-auth questions page. If not provided, sensible defaults are used.
  Future<void> submitOnboarding(
    Map<String, dynamic> payload, {
    String? displayName,
    String? nativeLanguage,
  }) async {
    final selectedLevel = (payload['level'] as String?)?.toUpperCase();

    final result = await authRepository.updateProfile(
      displayName: displayName,
      level: selectedLevel,
      goal: payload['goal'] as String?,
      interest: payload['interest'] as String?,
      nativeLanguage: nativeLanguage ?? 'vi',
      targetLanguage: 'en',
      isOnboardingCompleted: true,
    );

    result.fold(
      (_) {
        // Keep onboarding non-blocking on backend issues.
      },
      (updatedUser) {
        _user = updatedUser;
      },
    );
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Parse error messages to user-friendly format
  UiText _parseErrorMessage(String error) {
    final normalized = error.toLowerCase();

    if (normalized.contains('timeoutexception') ||
        normalized.contains('timed out')) {
      return const UiText.key('auth.errServerTimeout');
    }
    if (normalized.contains('/users/me failed')) {
      return const UiText.key('auth.errProfileLoad');
    }
    if (normalized.contains('internal server error')) {
      return const UiText.key('auth.errServer');
    }
    if (normalized.contains('google_server_client_id')) {
      return const UiText.key('auth.errGoogleConfig');
    }
    if (normalized.contains('google sign-in android config mismatch') ||
        normalized.contains('developer_error') ||
        normalized.contains('sha-1') ||
        normalized.contains('sha/client id')) {
      return const UiText.key('auth.errGoogleConfig');
    }

    if (normalized.contains(FacebookSignInService.emailMismatchCode)) {
      return const UiText.key('auth.errFacebookLinkMismatch');
    }
    if (normalized.contains('account-exists-with-different-credential')) {
      return const UiText.key('auth.errAccountExists');
    }
    if (normalized.contains('access-control-allow-origin') ||
        normalized.contains('blocked by cors')) {
      return const UiText.key('auth.errCors');
    }
    if (normalized.contains('network')) {
      return const UiText.key('errors.networkRetry');
    } else if (normalized.contains('cancelled') ||
        normalized.contains('canceled')) {
      return const UiText.key('auth.errCancelled');
    } else if (normalized.contains('email')) {
      return const UiText.key('auth.invalidEmail');
    } else if (normalized.contains('password')) {
      return const UiText.key('auth.errInvalidPassword');
    } else if (normalized.contains('user-not-found')) {
      return const UiText.key('auth.errUserNotFound');
    } else if (normalized.contains('wrong-password')) {
      return const UiText.key('auth.errWrongPassword');
    } else if (normalized.contains('too-many-requests')) {
      return const UiText.key('auth.errRateLimited');
    } else {
      return const UiText.key('errors.genericRetry');
    }
  }

  // Convert Failure to user-friendly message
  UiText _getFailureMessage(Failure failure) {
    if (failure is AuthFailure) {
      final normalized = failure.message.toLowerCase();
      if (normalized.contains('invalid google id token')) {
        return const UiText.key('auth.errGoogleConfig');
      }
      return UiText.failure(failure);
    } else if (failure is ServerFailure) {
      final normalized = failure.message.toLowerCase();
      if (normalized.contains('timeoutexception') ||
          normalized.contains('timed out')) {
        return const UiText.key('auth.errServerTimeout');
      }
      if (normalized.contains('/users/me failed')) {
        return const UiText.key('auth.errProfileLoad');
      }
      return UiText.failure(failure);
    } else if (failure is NetworkFailure) {
      return const UiText.key('errors.networkRetry');
    } else if (failure is CacheFailure) {
      return const UiText.key('errors.localStorage');
    } else if (failure is ValidationFailure) {
      return UiText.failure(failure);
    } else if (failure is ConflictFailure) {
      return UiText.failure(failure);
    } else if (failure is RateLimitFailure) {
      return const UiText.key('auth.errRateLimited');
    } else if (failure is PermissionFailure) {
      return UiText.failure(failure);
    } else if (failure is NotFoundFailure) {
      return UiText.failure(failure);
    } else if (failure is UnauthorizedFailure) {
      return const UiText.key('errors.sessionExpired');
    } else {
      return failure.message.isNotEmpty
          ? UiText.failure(failure)
          : const UiText.key('errors.genericRetry');
    }
  }
}
