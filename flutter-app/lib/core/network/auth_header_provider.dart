import 'package:firebase_auth/firebase_auth.dart';

/// Provides Authorization header using Firebase ID token.
class FirebaseAuthHeaderProvider {
  FirebaseAuth? _auth;

  FirebaseAuthHeaderProvider({FirebaseAuth? auth}) {
    try {
      // Only initialize if Firebase is already initialized
      _auth = auth ?? FirebaseAuth.instance;
    } catch (e) {
      // Firebase not initialized, will return empty headers
      _auth = null;
    }
  }

  Future<Map<String, String>> call() async {
    try {
      // Return empty if Firebase not initialized
      if (_auth == null) return const {};
      
      final user = _auth!.currentUser;
      if (user == null) return const {};

      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return const {};

      return {'Authorization': 'Bearer $token'};
    } catch (e) {
      // Handle any Firebase errors gracefully
      return const {};
    }
  }
}
