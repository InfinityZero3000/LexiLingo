import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../utils/app_logger.dart';

const _tag = 'GoogleSignInService';

/// Service for handling Google Sign In
///
/// On Web: uses Firebase Auth [signInWithPopup] with [GoogleAuthProvider].
/// This avoids calling the People API (which requires a separate GCP
/// API enable step) and gets the id_token directly from the GIS popup.
///
/// On Mobile: uses the standard [google_sign_in] package so that the
/// server-client-id / id_token exchange works correctly.
class GoogleSignInService {
  static const String redirectInProgressMarker =
      '__GOOGLE_REDIRECT_IN_PROGRESS__';

  final GoogleSignIn _googleSignIn;

  GoogleSignInService({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            scopes: ['email', 'profile'],
            // serverClientId is only for Android/iOS
            serverClientId: kIsWeb
                ? null
                : dotenv.env['GOOGLE_SERVER_CLIENT_ID'],
          );

  /// Sign in with Google and return the Firebase ID token.
  /// Returns null if sign-in was cancelled or failed.
  Future<String?> signIn() async {
    try {
      logInfo(_tag, 'Starting Google Sign In...');

      if (kIsWeb) {
        return await _signInWeb();
      } else {
        return await _signInMobile();
      }
    } catch (e) {
      logError(_tag, 'Google Sign In error: $e');
      return null;
    }
  }

  /// Web: use Firebase Auth signInWithPopup — no People API call needed.
  /// Extracts the Google ID token from the OAuth credential (not the Firebase
  /// ID token), so the backend's verify_google_token still works.
  Future<String?> _signInWeb() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');

    // If the app has just returned from signInWithRedirect(), consume the
    // pending credential first.
    final pendingRedirectToken = await consumePendingWebRedirectIdToken();
    if (pendingRedirectToken != null) {
      return pendingRedirectToken;
    }

    try {
      final userCredential = await FirebaseAuth.instance.signInWithPopup(
        provider,
      );

      return await _extractGoogleIdTokenAndSignOut(userCredential);
    } on FirebaseAuthException catch (e) {
      if (_shouldFallbackToRedirect(e.code, e.message)) {
        logWarn(
          _tag,
          'Popup sign-in failed (${e.code}), falling back to redirect flow',
        );
        await FirebaseAuth.instance.signInWithRedirect(provider);
        return redirectInProgressMarker;
      }
      rethrow;
    } catch (e) {
      final message = e.toString();
      if (_shouldFallbackToRedirect('unknown', message)) {
        logWarn(
          _tag,
          'Popup sign-in blocked by browser policy, using redirect flow',
        );
        await FirebaseAuth.instance.signInWithRedirect(provider);
        return redirectInProgressMarker;
      }
      rethrow;
    }
  }

  /// Consume pending Google credential after signInWithRedirect().
  /// Returns Google id_token if present.
  Future<String?> consumePendingWebRedirectIdToken() async {
    if (!kIsWeb) return null;

    try {
      final redirectResult = await FirebaseAuth.instance.getRedirectResult();
      return await _extractGoogleIdTokenAndSignOut(redirectResult);
    } catch (e) {
      logWarn(_tag, 'No pending redirect result or failed to consume: $e');
      return null;
    }
  }

  Future<String?> _extractGoogleIdTokenAndSignOut(UserCredential userCredential) async {
    // Extract the Google ID token from the OAuth credential
    final oauthCredential = userCredential.credential as OAuthCredential?;
    final googleIdToken = oauthCredential?.idToken;

    if (googleIdToken == null) {
      logError(_tag, 'Failed to get Google ID token from Firebase credential');
      return null;
    }

    // Sign out from Firebase immediately — the app manages its own session.
    await FirebaseAuth.instance.signOut();

    logInfo(_tag, 'Google Sign In successful (web)');
    return googleIdToken;
  }

  bool _shouldFallbackToRedirect(String code, String? message) {
    const fallbackCodes = {
      'popup-blocked',
      'popup-closed-by-user',
      'cancelled-popup-request',
      'operation-not-supported-in-this-environment',
      'web-storage-unsupported',
    };

    if (fallbackCodes.contains(code)) return true;

    final normalized = (message ?? '').toLowerCase();
    return normalized.contains('cross-origin-opener-policy') ||
        normalized.contains('window.closed') ||
        normalized.contains('popup');
  }

  /// Mobile: use google_sign_in package to get the Google id_token.
  Future<String?> _signInMobile() async {
    // Sign out first to ensure account picker is shown
    await _googleSignIn.signOut();

    final GoogleSignInAccount? account = await _googleSignIn.signIn();
    if (account == null) {
      logWarn(_tag, 'Google Sign In cancelled by user');
      return null;
    }

    logDebug(_tag, 'Google account obtained: ${account.email}');

    final GoogleSignInAuthentication auth = await account.authentication;
    if (auth.idToken == null) {
      logError(_tag, 'Failed to get ID token from Google (mobile)');
      return null;
    }

    logInfo(_tag, 'Google Sign In successful (mobile)');
    return auth.idToken;
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      logInfo(_tag, 'Google Sign Out successful');
    } catch (e) {
      logError(_tag, 'Google Sign Out error: $e');
    }
  }

  /// Check if user is currently signed in
  Future<bool> isSignedIn() async {
    if (kIsWeb) {
      return FirebaseAuth.instance.currentUser != null;
    }
    return await _googleSignIn.isSignedIn();
  }

  /// Get current Google account (mobile only)
  GoogleSignInAccount? get currentUser =>
      kIsWeb ? null : _googleSignIn.currentUser;
}
