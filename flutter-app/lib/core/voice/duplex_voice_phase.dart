import 'dart:typed_data';

enum DuplexVoicePhase {
  idle,
  connecting,
  listening,
  hearing,
  thinking,
  speaking,
  error,
  unavailable,
}

extension DuplexVoicePhaseX on DuplexVoicePhase {
  bool get isLive => switch (this) {
    DuplexVoicePhase.idle ||
    DuplexVoicePhase.error ||
    DuplexVoicePhase.unavailable => false,
    _ => true,
  };

  bool get canInterrupt =>
      this == DuplexVoicePhase.thinking || this == DuplexVoicePhase.speaking;
}

const _recoverableCodes = {'SERVER_BUSY', 'PERSISTENCE_FAILED'};

bool isRecoverableVoiceError(Object? code) => _recoverableCodes.contains(code);

DuplexVoicePhase reduceVoicePhase(
  DuplexVoicePhase phase,
  Map<String, dynamic> event,
) {
  if (!phase.isLive) return phase;
  final hasText = (event['text']?.toString().trim() ?? '').isNotEmpty;
  switch (event['type']) {
    case 'session_started':
      return phase == DuplexVoicePhase.connecting
          ? DuplexVoicePhase.listening
          : phase;
    case 'stt.partial':
      return hasText && phase == DuplexVoicePhase.listening
          ? DuplexVoicePhase.hearing
          : phase;
    case 'stt.final':
      if (phase != DuplexVoicePhase.listening &&
          phase != DuplexVoicePhase.hearing) {
        return phase;
      }
      return hasText ? DuplexVoicePhase.thinking : DuplexVoicePhase.listening;
    case 'tts.audio.start':
      return phase == DuplexVoicePhase.thinking
          ? DuplexVoicePhase.speaking
          : phase;
    case 'turn.done' || 'turn.cancelled':
      return phase.canInterrupt ? DuplexVoicePhase.listening : phase;
    case 'voice.error':
      return isRecoverableVoiceError(event['code'])
          ? DuplexVoicePhase.listening
          : DuplexVoicePhase.error;
    case 'stt.error':
      return DuplexVoicePhase.error;
    default:
      return phase;
  }
}

double pcm16Level(Uint8List pcm) {
  final samples = pcm.lengthInBytes ~/ 2;
  if (samples == 0) return 0;
  final view = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = view.getInt16(i * 2, Endian.little) / 32768;
    sum += s * s;
  }
  final rms = (sum / samples);
  return (rms * 16).clamp(0.0, 1.0).toDouble();
}
