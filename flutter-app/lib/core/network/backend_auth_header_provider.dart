import '../../features/auth/data/datasources/token_storage.dart';

/// Provides Authorization header using backend JWT token
class BackendAuthHeaderProvider {
  final TokenStorage tokenStorage;

  BackendAuthHeaderProvider({required this.tokenStorage});

  Future<Map<String, String>> call() async {
    try {
      final tokens = await tokenStorage.getTokens();
      if (tokens == null || tokens.accessToken.isEmpty) {
        print('[WARN] BackendAuthHeaderProvider: No tokens available');
        return const {};
      }

      print('[DEBUG] BackendAuthHeaderProvider: Token available (length: ${tokens.accessToken.length})');
      return {'Authorization': 'Bearer ${tokens.accessToken}'};
    } catch (e) {
      print('[ERROR] BackendAuthHeaderProvider: Error getting tokens: $e');
      return const {};
    }
  }
}
