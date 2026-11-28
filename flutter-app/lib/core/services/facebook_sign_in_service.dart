import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../utils/app_logger.dart';

const _tag = 'FacebookSignInService';

/// The email already uses another sign-in method: its owner has to prove that
/// before Facebook is added to the account. Firebase promises neither field.
class FacebookLinkRequired implements Exception {
  const FacebookLinkRequired(this.email, this.credential);

  final String? email;
  final AuthCredential? credential;

  @override
  String toString() => 'account-exists-with-different-credential';
}

/// The owner is proven, and Facebook has to be added in one more popup. A
/// browser only opens a popup straight from a tap, so the app asks first.
class FacebookConfirmRequired implements Exception {
  const FacebookConfirmRequired();
}

/// Service for handling Facebook Sign In
class FacebookSignInService {
  FacebookSignInService({FirebaseAuth? auth}) : _injectedAuth = auth;

  static const emailMismatchCode = 'facebook-link-email-mismatch';

  /// Facebook was added but no token came back: signing in again now works.
  static const linkedRetryCode = 'facebook-linked-sign-in-again';

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
      if (_isDismissedPopup(e.code)) return null;

      final link = linkRequest(e, isWeb: kIsWeb);
      if (link != null) {
        // Presence only: which of the two Firebase left out decides the flow.
        logInfo(
          _tag,
          'Account exists: email=${link.email != null} '
          'credential=${link.credential != null}',
        );
        throw link;
      }

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

  /// Web only: mobile has no linking flow yet.
  @visibleForTesting
  static FacebookLinkRequired? linkRequest(
    FirebaseAuthException error, {
    required bool isWeb,
  }) {
    if (!isWeb || error.code != 'account-exists-with-different-credential') {
      return null;
    }
    return FacebookLinkRequired(error.email, error.credential);
  }

  /// Proves ownership with Google, then adds Facebook to that account and
  /// returns a Facebook Firebase ID token. Returns null if the popup was closed.
  /// Without the pending credential it throws [FacebookConfirmRequired] and
  /// keeps the owner signed in to Firebase for [attachFacebook]. Must be called
  /// straight from a tap, or the browser blocks the popup.
  Future<String?> linkWithGoogle(FacebookLinkRequired request) async {
    final email = request.email;
    final google = GoogleAuthProvider()
      ..setCustomParameters({
        if (email != null) 'login_hint': email,
        'prompt': 'select_account',
      });

    var awaitingFacebook = false;
    try {
      final owner = (await _auth.signInWithPopup(google)).user;
      if (owner == null) return null;
      if (email != null && owner.email?.toLowerCase() != email.toLowerCase()) {
        throw Exception(emailMismatchCode);
      }

      final credential = request.credential;
      if (credential == null) {
        awaitingFacebook = true;
        throw const FacebookConfirmRequired();
      }
      try {
        await owner.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'provider-already-linked') rethrow;
      }
      return await _facebookIdToken(credential);
    } on FirebaseAuthException catch (e) {
      return _linkingFailed(e);
    } finally {
      if (!awaitingFacebook) await _auth.signOut();
    }
  }

  /// The second step after [FacebookConfirmRequired]: a Facebook popup that adds
  /// Facebook to the proven account. Must be called straight from a tap.
  Future<String?> attachFacebook() async {
    try {
      final owner = _auth.currentUser;
      if (owner == null) return null;
      final linked = await owner.linkWithPopup(_facebookProvider());
      final credential = linked.credential;
      if (credential == null) throw Exception(linkedRetryCode);
      return await _facebookIdToken(credential);
    } on FirebaseAuthException catch (e) {
      return _linkingFailed(e);
    } finally {
      await _auth.signOut();
    }
  }

  /// The learner gave up between the two steps.
  Future<void> cancelLink() => _auth.signOut();

  /// The backend accepts only a token whose sign-in method is Facebook.
  Future<String?> _facebookIdToken(AuthCredential credential) async {
    final signedIn = await _auth.signInWithCredential(credential);
    return await signedIn.user?.getIdToken(true);
  }

  String? _linkingFailed(FirebaseAuthException e) {
    logError(_tag, 'Facebook linking Firebase error: ${e.code}');
    if (_isDismissedPopup(e.code)) return null;
    throw Exception(e.code);
  }

  static bool _isDismissedPopup(String code) =>
      code == 'popup-closed-by-user' ||
      code == 'cancelled-popup-request' ||
      code == 'user-cancelled';

  static FacebookAuthProvider _facebookProvider() => FacebookAuthProvider()
    ..addScope('email')
    ..addScope('public_profile');

  /// The email a Firebase ID token names, or null if it cannot be read.
  static String? emailOf(String idToken) {
    try {
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(idToken.split('.')[1])),
        ),
      );
      return (payload as Map)['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Web: use Firebase Auth signInWithPopup
  Future<String?> _signInWeb() async {
    await _auth.signInWithPopup(_facebookProvider());
    // The app keeps its own session with the backend, so Firebase is signed out.
    try {
      final idToken = await _auth.currentUser?.getIdToken();
      if (idToken == null) {
        logError(_tag, 'Failed to get Firebase ID token after popup');
      }
      return idToken;
    } finally {
      await _auth.signOut();
    }
  }

  /// Mobile: use flutter_facebook_auth package to authenticate, then Firebase Auth to exchange.
  Future<String?> _signInMobile() async {
    // Check if the user is already logged in with Facebook
    final rawNonce = _randomNonce();
    final LoginResult result = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );

    if (result.status != LoginStatus.success) {
      logWarn(
        _tag,
        'Facebook Sign In failed or cancelled. Status: ${result.status}',
      );
      return null;
    }

    final facebookAuthCredential = firebaseCredential(
      result.accessToken!,
      rawNonce,
    );

    final userCredential = await _auth.signInWithCredential(
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
    await _auth.signOut();
    await FacebookAuth.instance.logOut();

    logInfo(_tag, 'Facebook Sign In successful (mobile)');
    return idToken;
  }

  /// iOS Limited Login returns an OIDC token, which Firebase only accepts with the raw nonce.
  @visibleForTesting
  static AuthCredential firebaseCredential(AccessToken token, String rawNonce) {
    if (token.type == AccessTokenType.limited) {
      return OAuthProvider(
        'facebook.com',
      ).credential(idToken: token.tokenString, rawNonce: rawNonce);
    }
    return FacebookAuthProvider.credential(token.tokenString);
  }

  static String _randomNonce() {
    final random = Random.secure();
    return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
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
