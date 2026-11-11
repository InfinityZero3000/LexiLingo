import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';

typedef _Row = (DuplexVoicePhase, Map<String, dynamic>, DuplexVoicePhase);

void main() {
  const connecting = DuplexVoicePhase.connecting;
  const listening = DuplexVoicePhase.listening;
  const hearing = DuplexVoicePhase.hearing;
  const thinking = DuplexVoicePhase.thinking;
  const speaking = DuplexVoicePhase.speaking;
  const error = DuplexVoicePhase.error;

  final rows = <_Row>[
    (connecting, {'type': 'session_started'}, listening),
    (listening, {'type': 'session_started'}, listening),
    (listening, {'type': 'stt.partial', 'text': 'what is'}, hearing),
    (listening, {'type': 'stt.partial', 'text': '  '}, listening),
    (hearing, {'type': 'stt.final', 'text': 'What is it?'}, thinking),
    (hearing, {'type': 'stt.final', 'text': ''}, listening),
    (thinking, {'type': 'stt.final', 'text': 'late'}, thinking),
    (thinking, {'type': 'tts.audio.start'}, speaking),
    (hearing, {'type': 'tts.audio.start'}, hearing),
    (thinking, {'type': 'turn.done'}, listening),
    (speaking, {'type': 'turn.done'}, listening),
    (speaking, {'type': 'turn.cancelled'}, listening),
    (listening, {'type': 'turn.done'}, listening),
    (speaking, {'type': 'voice.error', 'code': 'SERVER_BUSY'}, listening),
    (
      thinking,
      {'type': 'voice.error', 'code': 'PERSISTENCE_FAILED'},
      listening,
    ),
    (speaking, {'type': 'voice.error', 'code': 'QUOTA_EXCEEDED'}, error),
    (thinking, {'type': 'voice.error', 'code': 'TURN_FAILED'}, error),
    (speaking, {'type': 'voice.error', 'code': 'PLAYBACK_FAILED'}, error),
    (connecting, {'type': 'stt.error', 'code': 'SERVER_BUSY'}, error),
    (listening, {'type': 'ack'}, listening),
  ];

  for (final (from, event, to) in rows) {
    test(
      '${from.name} + ${event['type']} ${event['code'] ?? ''} -> ${to.name}',
      () => expect(reduceVoicePhase(from, event), to),
    );
  }

  test('events never revive a stopped, failed or unavailable session', () {
    for (final dead in [
      DuplexVoicePhase.idle,
      DuplexVoicePhase.error,
      DuplexVoicePhase.unavailable,
    ]) {
      expect(reduceVoicePhase(dead, {'type': 'session_started'}), dead);
      expect(reduceVoicePhase(dead, {'type': 'turn.done'}), dead);
    }
  });

  test('only thinking and speaking can be interrupted', () {
    final interruptible = DuplexVoicePhase.values.where((p) => p.canInterrupt);
    expect(interruptible, [thinking, speaking]);
  });

  group('pcm16Level', () {
    Uint8List tone(int amplitude, int samples) {
      final data = ByteData(samples * 2);
      for (var i = 0; i < samples; i++) {
        data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    test('is 0 for silence and empty input', () {
      expect(pcm16Level(Uint8List(0)), 0);
      expect(pcm16Level(tone(0, 320)), 0);
    });

    test('rises with loudness and never exceeds 1', () {
      final quiet = pcm16Level(tone(500, 320));
      final speech = pcm16Level(tone(4000, 320));
      expect(quiet, lessThan(speech));
      expect(pcm16Level(tone(32767, 320)), 1);
    });
  });
}
