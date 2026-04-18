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
  final GoogleSignIn _googleSignIn;
  String? _lastError;

  String? get lastError => _lastError;

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
      _lastError = null;
      logInfo(_tag, 'Starting Google Sign In...');

      if (kIsWeb) {
        return await _signInWeb();
      } else {
        return await _signInMobile();
      }
    } catch (e) {
      logError(_tag, 'Google Sign In error: $e');
      _lastError = e.toString();
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

    final userCredential = await FirebaseAuth.instance.signInWithPopup(
      provider,
    );

    // Extract the Google ID token from the OAuth credential
    final oauthCredential = userCredential.credential as OAuthCredential?;
    final googleIdToken = oauthCredential?.idToken;

    if (googleIdToken == null) {
      logError(_tag, 'Failed to get Google ID token from Firebase popup (web)');
      return null;
    }

    // Sign out from Firebase immediately — the app manages its own session.
    await FirebaseAuth.instance.signOut();

    logInfo(_tag, 'Google Sign In successful (web)');
    return googleIdToken;
  }

  /// Mobile: use google_sign_in package to get the Google id_token.
  Future<String?> _signInMobile() async {
    // Sign out first to ensure account picker is shown
    await _googleSignIn.signOut();

    final GoogleSignInAccount? account = await _googleSignIn.signIn();
    if (account == null) {
      logWarn(_tag, 'Google Sign In cancelled by user');
      _lastError = 'cancelled';
      return null;
    }

    logDebug(_tag, 'Google account obtained: ${account.email}');

    final GoogleSignInAuthentication auth = await account.authentication;
    if (auth.idToken == null) {
      logError(_tag, 'Failed to get ID token from Google (mobile)');
      _lastError =
          'Unable to get Google ID token. Check GOOGLE_SERVER_CLIENT_ID configuration.';
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
