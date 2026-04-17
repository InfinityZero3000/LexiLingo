import 'package:shared_preferences/shared_preferences.dart';

/// Stores and resolves active authenticated user scope for local cache/sync.
class UserScopeService {
  UserScopeService._();

  static const String _activeUserIdKey = 'active_user_id';

  static Future<void> setActiveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeUserIdKey, userId);
  }

  static Future<String?> getActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeUserIdKey);
  }

  static Future<void> clearActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeUserIdKey);
  }

  static Future<String> getScopeOrDefault() async {
    return (await getActiveUserId()) ?? 'anonymous';
  }
}
