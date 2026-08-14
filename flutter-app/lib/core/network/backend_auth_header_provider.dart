import 'dart:convert';

import '../../features/auth/data/datasources/token_storage.dart';
import '../utils/app_logger.dart';

const _tag = 'BackendAuthHeaderProvider';

/// Refresh this long before the token actually expires, so a request never
/// travels with a token the server is about to reject.
const _refreshLeeway = Duration(minutes: 1);

/// True when [accessToken] is already expired or expires within
/// [_refreshLeeway]. Anything unparseable returns false — the 401 retry path
/// stays the fallback.
// ponytail: the leeway only absorbs small clock skew; a device clock that is
// hours off still lands on the 401 path.
bool isAccessTokenExpiring(String accessToken, {DateTime? now}) {
  final parts = accessToken.split('.');
  if (parts.length != 3) return false;

  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return false;

    final exp = payload['exp'];
    if (exp is! int) return false;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      exp * 1000,
      isUtc: true,
    );
    return expiresAt.isBefore(
      (now?.toUtc() ?? DateTime.now().toUtc()).add(_refreshLeeway),
    );
  } catch (_) {
    return false;
  }
}

/// Provides Authorization header using backend JWT token
class BackendAuthHeaderProvider {
  final TokenStorage tokenStorage;

  /// Shared token refresh (deduplicated across concurrent callers). Without it
  /// an expired token is only discovered through a 401, which paths like the
  /// voice WebSocket and multipart upload cannot retry.
  final Future<bool> Function()? refreshTokens;

  BackendAuthHeaderProvider({required this.tokenStorage, this.refreshTokens});

  Future<Map<String, String>> call() async {
    try {
      var tokens = await tokenStorage.getTokens();
      if (tokens == null || tokens.accessToken.isEmpty) {
        logWarn(_tag, 'No tokens available');
        return const {};
      }

      if (refreshTokens != null && isAccessTokenExpiring(tokens.accessToken)) {
        logInfo(_tag, 'Access token expiring — refreshing before request');
        if (await refreshTokens!()) {
          tokens = await tokenStorage.getTokens();
          if (tokens == null || tokens.accessToken.isEmpty) {
            return const {};
          }
        }
      }

      logDebug(_tag, 'Token available (length: ${tokens.accessToken.length})');
      return {'Authorization': 'Bearer ${tokens.accessToken}'};
    } catch (e) {
      logError(_tag, 'Error getting tokens: $e');
      return const {};
    }
  }
}
