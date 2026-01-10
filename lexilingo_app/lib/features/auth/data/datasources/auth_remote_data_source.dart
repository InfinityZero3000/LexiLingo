import 'package:google_sign_in/google_sign_in.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';

class AuthRemoteDataSource {
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  Future<UserEntity?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        return UserEntity(
          id: account.id,
          email: account.email,
          displayName: account.displayName ?? '',
          photoUrl: account.photoUrl,
        );
      }
      return null;
    } catch (e) {
      throw Exception('Google Sign In Failed: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.disconnect();
  }

  Future<UserEntity?> getCurrentUser() async {
    final account = _googleSignIn.currentUser;
     if (account != null) {
      return UserEntity(
        id: account.id,
        email: account.email,
        displayName: account.displayName ?? '',
        photoUrl: account.photoUrl,
      );
    }
    // Try silent sign in
    final accountSilent = await _googleSignIn.signInSilently();
    if (accountSilent != null) {
      return UserEntity(
        id: accountSilent.id,
        email: accountSilent.email,
        displayName: accountSilent.displayName ?? '',
        photoUrl: accountSilent.photoUrl,
      );
    }
    return null;
  }
}
