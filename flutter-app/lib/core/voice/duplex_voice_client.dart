import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/api_config.dart';
import '../network/backend_auth_header_provider.dart';
import 'duplex_voice_phase.dart';
import 'pcm_frame_chunker.dart';
import 'voice_audio_normalizer.dart';

class DuplexVoiceClient {
  DuplexVoiceClient({
    required this.authHeaders,
    String? baseUrl,
    AudioRecorder? recorder,
  }) : baseUrl = baseUrl ?? ApiConfig.aiServiceUrl,
       _recorder = recorder ?? AudioRecorder();

  static const _replayCapSeconds = 30;

  /// Process-wide capability hint used by the chat UI after a 404 ticket
  /// response proves that duplex voice is disabled on this deployment.
  static bool serverUnavailable = false;

  final BackendAuthHeaderProvider authHeaders;
  final String baseUrl;
  final AudioRecorder _recorder;
  final _chunker = PcmFrameChunker();
  final _normalizer = VoiceAudioNormalizer();
  // SoLoud opens its platform library while resolving the singleton. Keep it
  // lazy so constructing a client (including test doubles) does not require a
  // native audio plugin before playback is actually used.
  late final _soloud = SoLoud.instance;
  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;
  StreamSubscription<Uint8List>? _captureSubscription;
  AudioSource? _source;
  SoundHandle? _handle;
  int _audioSeq = 0;
  int? _activeTurnSeq;
  int _expectedAudioSeq = 0;
  final _clock = Stopwatch();
  Future<void> _incoming = Future.value();
  Future<void> _captureTransition = Future.value();
  Completer<void>? _drainAbort;
  bool _stopping = false;
  bool _replaying = false;
  final _replay = BytesBuilder(copy: false);
  int _replayRate = 22050;

  final events = StreamController<Map<String, dynamic>>.broadcast();
  final phase = ValueNotifier<DuplexVoicePhase>(DuplexVoicePhase.idle);
  final inputLevel = ValueNotifier<double>(0);
  String? lastErrorCode;

  bool get canReplay =>
      phase.value == DuplexVoicePhase.listening && _replay.length > 0;

  Future<void> start({
    required String sessionId,
    String learnerLevel = 'B1',
    String nativeLanguage = 'vi',
    double ttsSpeed = 1.0,
  }) async {
    if (_channel != null) await stop();
    phase.value = DuplexVoicePhase.connecting;
    lastErrorCode = null;
    _stopping = false;
    _clock
      ..reset()
      ..start();
    try {
      if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits) ||
          !await _recorder.hasPermission()) {
        lastErrorCode = 'MIC_PERMISSION';
        throw StateError('PCM microphone capture is unavailable');
      }
      final headers = await authHeaders.call();
      final response = await http.post(
        Uri.parse('$baseUrl/voice/ticket'),
        headers: headers,
      );
      if (response.statusCode == 404) {
        serverUnavailable = true;
        lastErrorCode = 'UNAVAILABLE';
        phase.value = DuplexVoicePhase.unavailable;
        throw StateError('Voice is disabled on the server');
      }
      if (response.statusCode != 200) {
        lastErrorCode = response.statusCode == 429
            ? 'QUOTA_EXCEEDED'
            : 'TICKET_FAILED';
        throw StateError('Voice ticket failed (${response.statusCode})');
      }
      final ticket =
          (jsonDecode(response.body) as Map<String, dynamic>)['ticket']
              as String;
      final httpUri = Uri.parse('$baseUrl/voice/stream');
      final socketUri = httpUri.replace(
        scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      );

      if (!_soloud.isInitialized) await _soloud.init();
      _channel = WebSocketChannel.connect(
        socketUri,
        protocols: ['voice.ticket.$ticket'],
      );
      _socketSubscription = _channel!.stream.listen(
        (data) {
          final previous = _incoming;
          _incoming = () async {
            try {
              await previous;
            } catch (_) {
              // A malformed server frame must not poison later event handling.
            }
            if (!_stopping) await _onSocketData(data);
          }();
        },
        onError: (_) => unawaited(_handleSocketClosed()),
        onDone: () => unawaited(_handleSocketClosed()),
      );
      await _channel!.ready;
      _channel!.sink.add(
        jsonEncode({
          'type': 'start',
          'session_id': sessionId,
          'sample_rate': 16000,
          'channels': 1,
          'format': 'pcm16',
          'duplex': true,
          'tts_enabled': true,
          'learner_level': learnerLevel,
          'native_language': nativeLanguage,
          if (ttsSpeed != 1.0) 'tts_speed': ttsSpeed,
        }),
      );

      await _startCapture();
    } catch (_) {
      if (phase.value != DuplexVoicePhase.unavailable) {
        lastErrorCode ??= 'CONNECT_FAILED';
        phase.value = DuplexVoicePhase.error;
      }
      await stop(failed: true);
      rethrow;
    }
  }

  Future<void> _startCapture() async {
    await _serializeCaptureTransition(() async {
      if (_stopping || _captureSubscription != null) return;
      _normalizer.reset();
      _chunker.reset();
      final capture = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 48000,
          numChannels: 1,
        ),
      );
      _captureSubscription = capture.listen((bytes) {
        final normalized = _normalizer.normalize(
          bytes,
          sampleRate: 48000,
          channels: 1,
        );
        inputLevel.value = pcm16Level(normalized);
        for (final pcm in _chunker.add(normalized)) {
          _channel?.sink.add(
            packMicrophoneFrame(
              sequence: _audioSeq++,
              clientTimestampMs: _clock.elapsedMilliseconds,
              pcm: pcm,
            ),
          );
        }
      });
    });
  }

  Future<void> _stopCapture() async {
    await _serializeCaptureTransition(() async {
      final subscription = _captureSubscription;
      _captureSubscription = null;
      await subscription?.cancel();
      await _recorder.stop();
      _normalizer.reset();
      _chunker.reset();
      inputLevel.value = 0;
    });
  }

  Future<void> _serializeCaptureTransition(Future<void> Function() action) {
    final previous = _captureTransition;
    final next = () async {
      try {
        await previous;
      } catch (_) {
        // A failed transition must not permanently block later cleanup.
      }
      await action();
    }();
    _captureTransition = next;
    return next;
  }

  Future<void> cancelTurn() async {
    _channel?.sink.add(jsonEncode({'type': 'cancel_turn'}));
    await _resetPlayback();
    _activeTurnSeq = null;
    await _startCapture();
  }

  Future<void> interrupt() async {
    if (!phase.value.canInterrupt) return;
    if (_replaying) {
      await _resetPlayback();
      return;
    }
    await cancelTurn();
    phase.value = DuplexVoicePhase.listening;
  }

  Future<void> replayLast() async {
    if (!canReplay || _stopping) return;
    final pcm = _replay.toBytes();
    await _stopCapture();
    _replaying = true;
    phase.value = DuplexVoicePhase.speaking;
    try {
      await _ensurePlayback(_replayRate);
      _soloud.addAudioDataStream(_source!, pcm);
      await _drainPlayback();
    } catch (_) {
      // _drainPlayback has already moved the client to an error state.
    } finally {
      _replaying = false;
      if (!_stopping) {
        phase.value = DuplexVoicePhase.listening;
        await _startCapture();
      }
    }
  }

  Future<void> stop({bool failed = false}) async {
    _stopping = true;
    _clock.stop();
    if (!failed && phase.value != DuplexVoicePhase.unavailable) {
      phase.value = DuplexVoicePhase.idle;
    }
    // Abort any TTS drain before waiting for the serialized inbound handler.
    // Otherwise stop() can wait for the full playback timeout.
    await _resetPlayback();
    final channel = _channel;
    final socketSubscription = _socketSubscription;
    _channel = null;
    _socketSubscription = null;
    try {
      channel?.sink.add(jsonEncode({'type': 'stop'}));
    } catch (_) {
      // The remote peer may already have closed the sink.
    }
    await _stopCapture();
    await socketSubscription?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {
      // Closing an already-closed sink is harmless during cleanup.
    }
    try {
      await _incoming;
    } catch (_) {
      // Cleanup must continue after a malformed or failed inbound event.
    }
    await _resetPlayback();
    _replay.clear();
    _normalizer.reset();
    _chunker.reset();
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
    phase.dispose();
    inputLevel.dispose();
    await events.close();
  }

  Future<void> _onSocketData(Object? data) async {
    if (data is String) {
      final event = jsonDecode(data) as Map<String, dynamic>;
      final type = event['type'];
      if (type == 'stt.final' || type == 'tts.audio.start') {
        await _stopCapture();
      }
      if (type == 'turn_started') {
        _replay.clear();
        _activeTurnSeq = event['turn_seq'] as int?;
        _expectedAudioSeq = 0;
      }
      if (type == 'tts.audio.start') {
        _replayRate = event['sample_rate'] as int;
        await _ensurePlayback(_replayRate);
      }
      if (type == 'tts.audio.end') {
        await _drainPlayback();
      }
      if (type == 'turn.cancelled' || type == 'voice.error') {
        await _resetPlayback();
        _activeTurnSeq = null;
      }
      if (type == 'voice.error' || type == 'stt.error') {
        lastErrorCode = event['code']?.toString();
      }
      if (type == 'voice.error') {
        if (isRecoverableVoiceError(lastErrorCode)) {
          await _startCapture();
        } else {
          _stopping = true;
          await _stopCapture();
          await _channel?.sink.close();
        }
      } else if (type == 'stt.error') {
        _stopping = true;
        await _stopCapture();
        await _channel?.sink.close();
      } else if (type == 'turn.done' || type == 'turn.cancelled') {
        await _startCapture();
      }
      phase.value = reduceVoicePhase(phase.value, event);
      events.add(event);
      return;
    }
    final bytes = data is Uint8List
        ? data
        : Uint8List.fromList(data as List<int>);
    final frame = unpackTtsFrame(bytes);
    if (frame.turnSeq != _activeTurnSeq ||
        frame.audioSeq != _expectedAudioSeq) {
      return;
    }
    _expectedAudioSeq++;
    if (_replay.length < _replayRate * 2 * _replayCapSeconds) {
      _replay.add(frame.pcm);
    }
    if (_source != null) _soloud.addAudioDataStream(_source!, frame.pcm);
  }

  Future<void> _ensurePlayback(int sampleRate) async {
    if (_source != null) return;
    _source = _soloud.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.08,
      sampleRate: sampleRate,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    _handle = await _soloud.play(_source!);
  }

  Future<void> _drainPlayback() async {
    final source = _source;
    if (source == null) return;
    final abort = _drainAbort = Completer<void>();
    try {
      _soloud.setDataIsEnded(source);
      await Future.any([
        source.allInstancesFinished.first,
        abort.future,
      ]).timeout(const Duration(seconds: 30));
    } catch (_) {
      _stopping = true;
      await _stopCapture();
      lastErrorCode = 'PLAYBACK_FAILED';
      phase.value = DuplexVoicePhase.error;
      if (!events.isClosed) {
        events.add({
          'type': 'voice.error',
          'code': 'PLAYBACK_FAILED',
          'message': 'Voice playback failed',
        });
      }
      rethrow;
    } finally {
      await _resetPlayback();
    }
  }

  Future<void> _handleSocketClosed() async {
    if (_stopping) return;
    _stopping = true;
    await _stopCapture();
    await _resetPlayback();
    lastErrorCode = 'CONNECTION_CLOSED';
    phase.value = DuplexVoicePhase.error;
    if (!events.isClosed) {
      events.add({
        'type': 'voice.error',
        'code': 'CONNECTION_CLOSED',
        'message': 'Voice connection closed',
      });
    }
  }

  Future<void> _resetPlayback() async {
    final abort = _drainAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    if (_handle != null) await _soloud.stop(_handle!);
    if (_source != null) _soloud.disposeSource(_source!);
    _handle = null;
    _source = null;
  }
}

Uint8List packMicrophoneFrame({
  required int sequence,
  required int clientTimestampMs,
  required Uint8List pcm,
}) {
  final frame = Uint8List(14 + pcm.length);
  final header = ByteData.sublistView(frame, 0, 14);
  header.setUint8(0, 1);
  header.setUint8(1, 0);
  header.setUint32(2, sequence, Endian.big);
  header.setUint64(6, clientTimestampMs, Endian.big);
  frame.setRange(14, frame.length, pcm);
  return frame;
}

final class TtsAudioFrame {
  const TtsAudioFrame({
    required this.turnSeq,
    required this.sentenceSeq,
    required this.audioSeq,
    required this.pcm,
  });

  final int turnSeq;
  final int sentenceSeq;
  final int audioSeq;
  final Uint8List pcm;
}

TtsAudioFrame unpackTtsFrame(Uint8List frame) {
  if (frame.length < 16) throw const FormatException('TTS frame too short');
  final header = ByteData.sublistView(frame, 0, 16);
  if (header.getUint8(0) != 1 || header.getUint8(1) != 2) {
    throw const FormatException('Unsupported TTS frame');
  }
  final length = header.getUint32(12, Endian.big);
  if (length != frame.length - 16) {
    throw const FormatException('Invalid TTS payload length');
  }
  return TtsAudioFrame(
    turnSeq: header.getUint32(2, Endian.big),
    sentenceSeq: header.getUint16(6, Endian.big),
    audioSeq: header.getUint32(8, Endian.big),
    pcm: Uint8List.sublistView(frame, 16),
  );
}
