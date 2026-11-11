import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/duplex_voice_panel.dart';

Widget _host(
  DuplexVoicePhase phase, {
  double level = 0,
  String caption = '',
  VoidCallback? onEnd,
  VoidCallback? onOrbTap,
  VoidCallback? onReplay,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: DuplexVoicePanel(
          phase: phase,
          level: level,
          caption: caption,
          onEnd: onEnd ?? () {},
          onOrbTap: onOrbTap ?? () {},
          onReplay: onReplay,
        ),
      ),
    ),
  );
}

void main() {
  const statusKeys = {
    DuplexVoicePhase.connecting: 'lexiChat.voice.statusConnecting',
    DuplexVoicePhase.listening: 'lexiChat.voice.statusListening',
    DuplexVoicePhase.hearing: 'lexiChat.voice.statusHearing',
    DuplexVoicePhase.thinking: 'lexiChat.voice.statusThinking',
    DuplexVoicePhase.speaking: 'lexiChat.voice.statusSpeaking',
    DuplexVoicePhase.error: 'lexiChat.voice.errorGeneric',
  };

  for (final entry in statusKeys.entries) {
    testWidgets('${entry.key.name} shows its status line', (tester) async {
      await tester.pumpWidget(_host(entry.key, disableAnimations: true));
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('shows the live caption', (tester) async {
    await tester.pumpWidget(
      _host(
        DuplexVoicePhase.hearing,
        caption: 'what is the past',
        disableAnimations: true,
      ),
    );
    expect(find.text('what is the past'), findsOneWidget);
  });

  group('orb', () {
    Future<int> tapOrb(WidgetTester tester, DuplexVoicePhase phase) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(phase, onOrbTap: () => taps++, disableAnimations: true),
      );
      await tester.tap(find.byIcon(_orbIcon(phase)));
      return taps;
    }

    testWidgets('interrupts while Lexi thinks or speaks', (tester) async {
      expect(await tapOrb(tester, DuplexVoicePhase.thinking), 1);
      expect(await tapOrb(tester, DuplexVoicePhase.speaking), 1);
    });

    testWidgets('retries from the error state', (tester) async {
      expect(await tapOrb(tester, DuplexVoicePhase.error), 1);
    });

    testWidgets('ignores taps while listening', (tester) async {
      expect(await tapOrb(tester, DuplexVoicePhase.listening), 0);
    });

    testWidgets('is labelled per state for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(DuplexVoicePhase.speaking, disableAnimations: true),
      );
      expect(
        find.bySemanticsLabel('lexiChat.voice.a11yOrbInterrupt'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        _host(DuplexVoicePhase.error, disableAnimations: true),
      );
      expect(
        find.bySemanticsLabel('lexiChat.voice.a11yOrbRetry'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('end fires always; replay only when provided', (tester) async {
    var ended = 0;
    var replayed = 0;
    await tester.pumpWidget(
      _host(
        DuplexVoicePhase.listening,
        onEnd: () => ended++,
        onReplay: () => replayed++,
        disableAnimations: true,
      ),
    );
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.tap(find.byIcon(Icons.replay_rounded));
    expect((ended, replayed), (1, 1));

    await tester.pumpWidget(
      _host(DuplexVoicePhase.listening, disableAnimations: true),
    );
    final replay = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.replay_rounded),
    );
    expect(replay.onPressed, isNull);
  });

  testWidgets('every control meets the 48dp touch target', (tester) async {
    await tester.pumpWidget(
      _host(
        DuplexVoicePhase.listening,
        onReplay: () {},
        disableAnimations: true,
      ),
    );
    for (final icon in [Icons.call_end_rounded, Icons.replay_rounded]) {
      final size = tester.getSize(find.widgetWithIcon(IconButton, icon));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSize(find.byType(GestureDetector).first).shortestSide,
      greaterThanOrEqualTo(48),
    );
  });

  group('motion', () {
    testWidgets('thinking breathes unless the OS asks for reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(_host(DuplexVoicePhase.thinking));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        _host(DuplexVoicePhase.thinking, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the loop stops when the phase no longer needs it', (
      tester,
    ) async {
      await tester.pumpWidget(_host(DuplexVoicePhase.speaking));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(_host(DuplexVoicePhase.listening));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

IconData _orbIcon(DuplexVoicePhase phase) => switch (phase) {
  DuplexVoicePhase.thinking => Icons.more_horiz_rounded,
  DuplexVoicePhase.speaking => Icons.stop_rounded,
  DuplexVoicePhase.error => Icons.refresh_rounded,
  _ => Icons.mic_rounded,
};
