import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app themes use the bundled CJK fallback', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        contains('NotoSansCJK'),
      );
      expect(
        theme.textTheme.titleMedium?.fontFamilyFallback,
        contains('NotoSansCJK'),
      );
    }
  });
}
