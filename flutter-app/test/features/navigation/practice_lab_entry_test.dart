import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Practice Lab is available from Profile, not Home quick actions', () {
    final home = File(
      'lib/features/home/presentation/widgets/home_page/quick_actions_grid.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/profile/presentation/pages/profile_page.dart',
    ).readAsStringSync();

    expect(home, isNot(contains('practiceLab.shortTitle')));
    expect(home, isNot(contains("'/practice-lab'")));
    expect(profile, contains('Icons.science_rounded'));
    expect(profile, contains("'practiceLab.shortTitle'.tr()"));
    expect(profile, contains("Navigator.pushNamed(context, '/practice-lab')"));
    expect(profile, isNot(contains('VoicePracticeScreen')));
    expect(profile, isNot(contains('voice_practice_screen.dart')));
  });
}
