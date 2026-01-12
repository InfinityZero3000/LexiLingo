import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';

class AuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  /// Sign in with Google using Firebase Authentication
  Future<UserEntity?> signIn() async {
    try {
      // Trigger the Google Sign In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = 
          await _firebaseAuth.signInWithCredential(credential);

      final User? firebaseUser = userCredential.user;
      
      if (firebaseUser != null) {
        return UserEntity(
          id: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName ?? '',
          photoUrl: firebaseUser.photoURL,
        );
      }
      
      return null;
    } catch (e) {
      throw Exception('Google Sign In Failed: $e');
    }
  }

  /// Sign in with email and password
  Future<UserEntity?> signInWithEmailPassword(String email, String password) async {
    try {
      final UserCredential userCredential = 
          await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? firebaseUser = userCredential.user;
      
      if (firebaseUser != null) {
        return UserEntity(
          id: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName ?? email.split('@')[0],
          photoUrl: firebaseUser.photoURL,
        );
      }
      
      return null;
    } on FirebaseAuthException catch (e) {
      throw Exception('Email Sign In Failed: ${e.message}');
    } catch (e) {
      throw Exception('Email Sign In Failed: $e');
    }
  }

  /// Sign out from both Google and Firebase
  Future<void> signOut() async {
    await Future.wait([
      _firebaseAuth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  /// Get current Firebase user
  Future<UserEntity?> getCurrentUser() async {
    final User? firebaseUser = _firebaseAuth.currentUser;
    
    if (firebaseUser != null) {
      return UserEntity(
        id: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        displayName: firebaseUser.displayName ?? '',
        photoUrl: firebaseUser.photoURL,
      );
    }
    
    return null;
  }

  /// Stream of auth state changes
  Stream<UserEntity?> get authStateChanges {
    return _firebaseAuth.authStateChanges().map((User? firebaseUser) {
      if (firebaseUser != null) {
        return UserEntity(
          id: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName ?? '',
          photoUrl: firebaseUser.photoURL,
        );
      }
      return null;
    });
  }
}
