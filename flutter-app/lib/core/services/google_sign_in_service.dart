import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/app_logger.dart';

const _tag = 'GoogleSignInService';

/// Service for handling Google Sign In
class GoogleSignInService {
  final GoogleSignIn _googleSignIn;

  GoogleSignInService({
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: [
                'email',
                'profile',
              ],
              // Note: serverClientId is only for Android/iOS, not for Web
              // Web uses clientId from firebase config automatically
              serverClientId: kIsWeb 
                  ? null 
                  : '432329288238-xxxxxxxxxxxxxxxxx.apps.googleusercontent.com',
            );

  /// Sign in with Google and return ID token
  /// Returns null if sign in was cancelled or failed
  Future<String?> signIn() async {
    try {
      logInfo(_tag, 'Starting Google Sign In...');
      
      // Sign out first to ensure account picker is shown
      await _googleSignIn.signOut();
      
      // Trigger the authentication flow
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      
      if (account == null) {
        logWarn(_tag, 'Google Sign In cancelled by user');
        return null;
      }

      logDebug(_tag, 'Google account obtained: ${account.email}');

      // Obtain the auth details from the request
      final GoogleSignInAuthentication auth = await account.authentication;

      if (auth.idToken == null) {
        logError(_tag, 'Failed to get ID token from Google');
        return null;
      }

      logInfo(_tag, 'Google Sign In successful');
      return auth.idToken;
    } catch (e) {
      logError(_tag, 'Google Sign In error: $e');
      return null;
    }
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      logInfo(_tag, 'Google Sign Out successful');
    } catch (e) {
      logError(_tag, 'Google Sign Out error: $e');
    }
  }

  /// Check if user is currently signed in
  Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  /// Get current Google account
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;
}
