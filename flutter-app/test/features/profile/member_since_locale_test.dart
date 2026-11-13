import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/profile_header.dart';

void main() {
  setUpAll(() async {
    for (final locale in ['en', 'vi', 'fr']) {
      await initializeDateFormatting(locale);
    }
  });

  test('member-since month follows the app locale, not the default one', () {
    final joined = DateTime(2026, 11, 3);

    expect(formatMemberSinceDate(joined, 'en'), 'Nov 2026');
    expect(formatMemberSinceDate(joined, 'vi'), 'thg 11 2026');
    expect(formatMemberSinceDate(joined, 'fr'), 'nov. 2026');
  });
}
