import '../../features/auth/data/datasources/token_storage.dart';
import '../utils/app_logger.dart';

const _tag = 'BackendAuthHeaderProvider';

/// Provides Authorization header using backend JWT token
class BackendAuthHeaderProvider {
  final TokenStorage tokenStorage;

  BackendAuthHeaderProvider({required this.tokenStorage});

  Future<Map<String, String>> call() async {
    try {
      final tokens = await tokenStorage.getTokens();
      if (tokens == null || tokens.accessToken.isEmpty) {
        logWarn(_tag, 'No tokens available');
        return const {};
      }

      logDebug(_tag, 'Token available (length: ${tokens.accessToken.length})');
      return {'Authorization': 'Bearer ${tokens.accessToken}'};
    } catch (e) {
      logError(_tag, 'Error getting tokens: $e');
      return const {};
    }
  }
}
