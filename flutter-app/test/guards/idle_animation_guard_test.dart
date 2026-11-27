import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An endless `repeat()` keeps a screen repainting for as long as it is open,
/// even when nothing is happening (the Home avatar ring did, for the whole
/// session). A new one has to be listed here with the reason it is allowed.
const _allowed = <String, String>{
  'lib/core/widgets/animated_components.dart':
      'spinner, dots, heartbeat: shown only while loading or active',
  'lib/core/widgets/custom_animations.dart':
      'library widgets, switched on by their callers while something runs',
  'lib/core/widgets/glassmorphic_components.dart':
      'flame and shimmer: shown only while active or loading',
  'lib/features/games/presentation/widgets/level_up_dialog.dart':
      'short-lived dialog',
  'lib/features/gamification/presentation/screens/league_ceremony_screen.dart':
      'short-lived ceremony',
  'lib/features/gamification/presentation/widgets/boost_purchase_animation.dart':
      'short-lived overlay',
  'lib/features/gamification/presentation/widgets/rank_up_dialog.dart':
      'short-lived dialog',
  'lib/features/home/presentation/widgets/home_ui_components.dart':
      'SkeletonLoader: only while content loads',
  'lib/features/lexi_chat/presentation/widgets/duplex_voice_panel.dart':
      'live voice session',
  'lib/features/lexi_chat/presentation/widgets/lexi_typing_indicator.dart':
      'only while Lexi is replying',
  'lib/features/profile/presentation/widgets/profile_ui_components.dart':
      'AnimatedProfileBackground has no caller',
  'lib/features/progress/presentation/widgets/daily_reward_dialog.dart':
      'short-lived dialog',
  'lib/features/voice/presentation/widgets/record_button.dart':
      'only while recording',
};

void main() {
  test('no long-lived screen starts an endless repeat() on its own', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      if (_allowed.containsKey(path)) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\brepeat\((?!count:)').allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$path:$line');
      }
    }
    expect(offenders, isEmpty);
  });

  test('every allowed file still repeats, so the list stays honest', () {
    final stale = _allowed.keys.where((path) {
      final source = File(path).readAsStringSync();
      return !RegExp(r'\brepeat\((?!count:)').hasMatch(source);
    });
    expect(stale, isEmpty);
  });
}
