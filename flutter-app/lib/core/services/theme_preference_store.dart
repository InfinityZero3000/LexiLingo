import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceStore {
  final SharedPreferences _preferences;

  ThemePreferenceStore(this._preferences);

  bool get hasPreference => _preferences.containsKey(AppConstants.themeModeKey);

  String readTheme() {
    return normalizeTheme(_preferences.getString(AppConstants.themeModeKey));
  }

  Future<void> writeTheme(String theme) async {
    await _preferences.setString(
      AppConstants.themeModeKey,
      normalizeTheme(theme),
    );
  }

  static String normalizeTheme(String? rawTheme) {
    switch ((rawTheme ?? '').trim().toLowerCase()) {
      case 'light':
        return 'light';
      case 'dark':
        return 'dark';
      case 'system':
        return 'system';
      default:
        return 'system';
    }
  }
}
