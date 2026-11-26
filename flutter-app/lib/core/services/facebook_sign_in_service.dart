import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../utils/app_logger.dart';

const _tag = 'FacebookSignInService';

/// The email already uses another sign-in method: its owner has to prove that
/// before Facebook is added to the account.
class FacebookLinkRequired implements Exception {
  const FacebookLinkRequired(this.email, this.credential);

  final String email;
  final AuthCredential credential;

  @override
  String toString() => 'account-exists-with-different-credential';
}

/// Service for handling Facebook Sign In
class FacebookSignInService {
  FacebookSignInService({FirebaseAuth? auth}) : _injectedAuth = auth;

  static const emailMismatchCode = 'facebook-link-email-mismatch';

  final FirebaseAuth? _injectedAuth;

  /// Resolved late: Firebase may not be initialised when this is constructed.
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  /// Sign in with Facebook and return the Firebase ID token.
  /// Returns null if sign-in was cancelled or failed.
  Future<String?> signIn() async {
    try {
      logInfo(_tag, 'Starting Facebook Sign In...');

      if (kIsWeb) {
        return await _signInWeb();
      } else {
        return await _signInMobile();
      }
    } on FirebaseAuthException catch (e) {
      logError(_tag, 'Facebook Sign In Firebase error: ${e.code} ${e.message}');

      // Treat user-driven popup cancellation as non-fatal.
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }

      final link = linkRequest(e, isWeb: kIsWeb);
      if (link != null) throw link;

      // Let provider map this to a user-friendly message.
      throw Exception(e.code);
    } catch (e) {
      logError(_tag, 'Facebook Sign In error: $e');

      final message = e.toString().toLowerCase();
      if (message.contains('cancel') || message.contains('closed by user')) {
        return null;
      }

      rethrow;
    }
  }

  /// The backend's wording when the email already belongs to an account that
  /// Facebook may not open; it arrives in English whatever the app language is.
  static bool isExistingAccountRefusal(String message) =>
      message.contains('login with your existing method');

  /// Web only: mobile has no linking flow yet.
  @visibleForTesting
  static FacebookLinkRequired? linkRequest(
    FirebaseAuthException error, {
    required bool isWeb,
  }) {
    final email = error.email;
    final credential = error.credential;
    if (!isWeb ||
        error.code != 'account-exists-with-different-credential' ||
        email == null ||
        credential == null) {
      return null;
    }
    return FacebookLinkRequired(email, credential);
  }

  /// Proves ownership with Google, adds Facebook to that account and returns a
  /// Facebook Firebase ID token. Returns null if the popup was closed. Must be
  /// called straight from a tap, or the browser blocks the popup.
  Future<String?> linkWithGoogle(FacebookLinkRequired request) async {
    final google = GoogleAuthProvider()
      ..setCustomParameters({
        'login_hint': request.email,
        'prompt': 'select_account',
      });

    try {
      final owner = (await _auth.signInWithPopup(google)).user;
      if (owner == null) return null;
      if (owner.email?.toLowerCase() != request.email.toLowerCase()) {
        throw Exception(emailMismatchCode);
      }

      try {
        await owner.linkWithCredential(request.credential);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'provider-already-linked') rethrow;
      }

      // The backend accepts only a token whose sign-in method is Facebook.
      final linked = await _auth.signInWithCredential(request.credential);
      return await linked.user?.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      logError(_tag, 'Facebook linking Firebase error: ${e.code}');
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      throw Exception(e.code);
    } finally {
      await _auth.signOut();
    }
  }

  /// Web: use Firebase Auth signInWithPopup
  Future<String?> _signInWeb() async {
    final provider = FacebookAuthProvider()
      ..addScope('email')
      ..addScope('public_profile');

    await FirebaseAuth.instance.signInWithPopup(provider);

    // With Firebase Auth, get the Firebase ID Token to send to our backend
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      logError(_tag, 'Failed to get Firebase User after popup');
      return null;
    }

    final idToken = await user.getIdToken();
    if (idToken == null) {
      logError(_tag, 'Failed to get Firebase ID token from User');
      return null;
    }

    // Sign out from Firebase immediately since the app manages its own session to the backend
    await FirebaseAuth.instance.signOut();

    logInfo(_tag, 'Facebook Sign In successful (web)');
    return idToken;
  }

  /// Mobile: use flutter_facebook_auth package to authenticate, then Firebase Auth to exchange.
  Future<String?> _signInMobile() async {
    // Check if the user is already logged in with Facebook
    final LoginResult result = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
    );

    if (result.status != LoginStatus.success) {
      logWarn(
        _tag,
        'Facebook Sign In failed or cancelled. Status: ${result.status}',
      );
      return null;
    }

    final facebookAuthCredential = FacebookAuthProvider.credential(
      result.accessToken!.tokenString,
    );

    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      facebookAuthCredential,
    );
    final user = userCredential.user;

    if (user == null) {
      logError(_tag, 'Firebase signInWithCredential returned null user');
      return null;
    }

    final idToken = await user.getIdToken();
    if (idToken == null) {
      logError(_tag, 'Failed to get Firebase ID token');
      return null;
    }

    // Sign out from Firebase immediately
    await FirebaseAuth.instance.signOut();
    await FacebookAuth.instance.logOut();

    logInfo(_tag, 'Facebook Sign In successful (mobile)');
    return idToken;
  }

  /// Sign out from Facebook
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await FacebookAuth.instance.logOut();
      }
      logInfo(_tag, 'Facebook Sign Out successful');
    } catch (e) {
      logError(_tag, 'Facebook Sign Out error: $e');
    }
  }
}
