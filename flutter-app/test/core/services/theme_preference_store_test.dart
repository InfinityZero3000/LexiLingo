import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemePreferenceStore', () {
    test('defaults to system when no preference exists', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = ThemePreferenceStore(preferences);

      expect(store.hasPreference, isFalse);
      expect(store.readTheme(), 'system');
    });

    test('reads and persists supported theme values', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.themeModeKey: 'dark',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = ThemePreferenceStore(preferences);

      expect(store.hasPreference, isTrue);
      expect(store.readTheme(), 'dark');

      await store.writeTheme('light');

      expect(store.readTheme(), 'light');
      expect(preferences.getString(AppConstants.themeModeKey), 'light');
    });

    test('normalizes invalid values to system', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.themeModeKey: 'sepia',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = ThemePreferenceStore(preferences);

      expect(store.hasPreference, isTrue);
      expect(store.readTheme(), 'system');

      await store.writeTheme('unknown');

      expect(preferences.getString(AppConstants.themeModeKey), 'system');
    });
  });
}
