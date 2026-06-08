import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/services/language_flag_cache.dart';

void main() {
  test('preload URLs cover every supported locale', () {
    expect(
      LanguageFlagCache.imageUrls,
      hasLength(AppLocales.supportedLocales.length),
    );
    expect(
      LanguageFlagCache.imageUrls,
      containsAll(<String>[
        'https://flagcdn.com/w320/vn.png',
        'https://flagcdn.com/w320/us.png',
        'https://flagcdn.com/w320/jp.png',
        'https://flagcdn.com/w320/kr.png',
        'https://flagcdn.com/w320/cn.png',
        'https://flagcdn.com/w320/fr.png',
        'https://flagcdn.com/w320/es.png',
      ]),
    );
  });
}
