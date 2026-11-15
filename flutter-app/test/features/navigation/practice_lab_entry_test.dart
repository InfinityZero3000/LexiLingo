import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Practice Lab has exactly one entry: the fourth bottom-nav tab', () {
    final home = File(
      'lib/features/home/presentation/widgets/home_page/quick_actions_grid.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/profile/presentation/pages/profile_page.dart',
    ).readAsStringSync();
    final mainScreen = File(
      'lib/features/home/presentation/pages/main_screen.dart',
    ).readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();

    expect(home, isNot(contains('practiceLab.shortTitle')));
    expect(home, isNot(contains("'/practice-lab'")));
    expect(profile, isNot(contains("'/practice-lab'")));
    expect(profile, isNot(contains('Icons.science_rounded')));
    expect(profile, isNot(contains('VoicePracticeScreen')));

    expect(mainScreen, contains("label: 'home.navPracticeLab'"));
    expect(mainScreen, contains('return const PracticeLabPage();'));
    expect(mainScreen, isNot(contains('StorySelectionPage')));
    // The named route still resolves, but to the tab, not a pushed page.
    expect(
      app,
      contains(
        "'/practice-lab': LearnerRoute.builder(\n"
        '                (context) => const MainScreen(initialIndex: 3),',
      ),
    );
  });
}
