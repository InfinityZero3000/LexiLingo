import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../utils/app_logger.dart';

const _tag = 'FacebookSignInService';

/// Service for handling Facebook Sign In
class FacebookSignInService {
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
    } catch (e) {
      logError(_tag, 'Facebook Sign In error: $e');
      return null;
    }
  }

  /// Web: use Firebase Auth signInWithPopup
  Future<String?> _signInWeb() async {
    final provider = FacebookAuthProvider()
      ..addScope('email')
      ..addScope('public_profile');

    final userCredential = await FirebaseAuth.instance.signInWithPopup(
      provider,
    );
    
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
      permissions: ['email', 'public_profile']
    );

    if (result.status != LoginStatus.success) {
      logWarn(_tag, 'Facebook Sign In failed or cancelled. Status: ${result.status}');
      return null;
    }

    final facebookAuthCredential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
    
    final userCredential = await FirebaseAuth.instance.signInWithCredential(facebookAuthCredential);
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
