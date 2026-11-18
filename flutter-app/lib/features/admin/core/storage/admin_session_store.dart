import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lexilingo_app/core/di/core_di.dart' show refreshBackendToken;
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the admin client gets its credentials. The panel is opened from the
/// signed-in learner's profile, so it borrows the learner session instead of
/// keeping a second one; a fake in tests, since secure storage has no platform
/// channel there.
abstract class AdminSessionStore {
  Future<String?> accessToken();

  /// Renews the session; false when it could not be renewed.
  Future<bool> refresh();
}

class LearnerSessionStore implements AdminSessionStore {
  const LearnerSessionStore();

  @override
  Future<String?> accessToken() => sl<TokenStorage>().getAccessToken();

  /// The learner app's own single-flight refresh. Refresh tokens are
  /// single-use, so the admin client must never spend one on its own; on
  /// failure that function clears the tokens and signals session expiry.
  @override
  Future<bool> refresh() => refreshBackendToken(sl<TokenStorage>());
}

/// Removes the tokens the old admin-only login left behind.
Future<void> purgeLegacyAdminSession() async {
  const keys = ['admin_access_token', 'admin_refresh_token', 'admin_user_json'];
  try {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } else {
      const storage = FlutterSecureStorage();
      for (final key in keys) {
        await storage.delete(key: key);
      }
    }
  } catch (_) {}
}
