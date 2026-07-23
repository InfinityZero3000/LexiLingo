import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/api_config.dart';
import '../network/backend_auth_header_provider.dart';
import 'pcm_frame_chunker.dart';
import 'voice_audio_normalizer.dart';

class DuplexVoiceClient {
  DuplexVoiceClient({
    required this.authHeaders,
    String? baseUrl,
    AudioRecorder? recorder,
  }) : baseUrl = baseUrl ?? ApiConfig.aiServiceUrl,
       _recorder = recorder ?? AudioRecorder();

  final BackendAuthHeaderProvider authHeaders;
  final String baseUrl;
  final AudioRecorder _recorder;
  final _chunker = PcmFrameChunker();
  final _normalizer = VoiceAudioNormalizer();
  final _soloud = SoLoud.instance;
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
  bool _stopping = false;

  final events = StreamController<Map<String, dynamic>>.broadcast();

  Future<void> start({required String sessionId}) async {
    _stopping = false;
    _clock
      ..reset()
      ..start();
    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits) ||
        !await _recorder.hasPermission()) {
      throw StateError('PCM microphone capture is unavailable');
    }
    try {
      final headers = await authHeaders.call();
      final response = await http.post(
        Uri.parse('$baseUrl/voice/ticket'),
        headers: headers,
      );
      if (response.statusCode != 200) {
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
      _socketSubscription = _channel!.stream.listen((data) {
        final previous = _incoming;
        _incoming = () async {
          try {
            await previous;
          } catch (_) {
            // A malformed server frame must not poison later event handling.
          }
          if (!_stopping) await _onSocketData(data);
        }();
      });
      _channel!.sink.add(
        jsonEncode({
          'type': 'start',
          'session_id': sessionId,
          'sample_rate': 16000,
          'channels': 1,
          'format': 'pcm16',
          'duplex': true,
          'tts_enabled': true,
        }),
      );

      await _startCapture();
    } catch (_) {
      await stop();
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

  Future<void> stop() async {
    _stopping = true;
    _clock.stop();
    _channel?.sink.add(jsonEncode({'type': 'stop'}));
    await _stopCapture();
    await _socketSubscription?.cancel();
    await _channel?.sink.close();
    try {
      await _incoming;
    } catch (_) {
      // Cleanup must continue after a malformed or failed inbound event.
    }
    await _resetPlayback();
    _normalizer.reset();
    _chunker.reset();
    _channel = null;
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
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
        _activeTurnSeq = event['turn_seq'] as int?;
        _expectedAudioSeq = 0;
      }
      if (type == 'tts.audio.start') {
        await _ensurePlayback(event['sample_rate'] as int);
      }
      if (type == 'turn.cancelled' || type == 'voice.error') {
        await _resetPlayback();
        _activeTurnSeq = null;
      }
      if (type == 'turn.done' ||
          type == 'turn.cancelled' ||
          type == 'voice.error') {
        await _startCapture();
      }
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

  Future<void> _resetPlayback() async {
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
