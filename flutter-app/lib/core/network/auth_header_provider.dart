import 'package:firebase_auth/firebase_auth.dart';

/// Provides Authorization header using Firebase ID token.
class FirebaseAuthHeaderProvider {
  final FirebaseAuth _auth;

  FirebaseAuthHeaderProvider({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  Future<Map<String, String>> call() async {
    final user = _auth.currentUser;
    if (user == null) return const {};

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return const {};

    return {'Authorization': 'Bearer $token'};
  }
}
