import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/theme/admin_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminThemeController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to light mode and persists updates', () async {
      final controller = AdminThemeController();
      await controller.load();
      expect(controller.mode, ThemeMode.light);

      await controller.setMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);

      final reloaded = AdminThemeController();
      await reloaded.load();
      expect(reloaded.mode, ThemeMode.dark);
    });

    test('toggle switches between light and dark', () async {
      final controller = AdminThemeController();
      await controller.toggle(Brightness.light);
      expect(controller.mode, ThemeMode.dark);

      await controller.toggle(Brightness.dark);
      expect(controller.mode, ThemeMode.light);
    });
  });
}
