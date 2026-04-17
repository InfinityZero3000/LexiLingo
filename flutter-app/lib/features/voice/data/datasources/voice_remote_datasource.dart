import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'dart:convert';

/// Voice Remote DataSource
/// Handles HTTP communication with AI service for STT and TTS
abstract class VoiceRemoteDataSource {
  /// Transcribe audio to text
  Future<Map<String, dynamic>> transcribeAudio({
    required Uint8List audioData,
    required String filename,
    String? language,
  });

  /// Synthesize text to speech
  Future<Uint8List> synthesizeSpeech({required String text});
}

class VoiceRemoteDataSourceImpl implements VoiceRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  VoiceRemoteDataSourceImpl({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? ApiConfig.aiServiceUrl;

  @override
  Future<Map<String, dynamic>> transcribeAudio({
    required Uint8List audioData,
    required String filename,
    String? language,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/stt/transcribe');

      final request = http.MultipartRequest('POST', uri);

      // Add audio file
      request.files.add(
        http.MultipartFile.fromBytes('audio', audioData, filename: filename),
      );

      // Add language if provided
      if (language != null) {
        request.fields['language'] = language;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        final detail = _extractErrorDetail(response.body);
        throw ServerException(
          'Failed to transcribe audio (${response.statusCode})${detail.isNotEmpty ? ': $detail' : ''}',
        );
      }
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('STT service error: $e');
    }
  }

  @override
  Future<Uint8List> synthesizeSpeech({required String text}) async {
    try {
      final uri = Uri.parse('$baseUrl/tts/synthesize');

      final response = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': text}),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final detail = _extractErrorDetail(response.body);
        throw ServerException(
          'Failed to synthesize speech (${response.statusCode})${detail.isNotEmpty ? ': $detail' : ''}',
        );
      }
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('TTS service error: $e');
    }
  }

  String _extractErrorDetail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';

    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Fall back to plain-text response body below.
    }

    if (trimmed.length <= 220) return trimmed;
    return '${trimmed.substring(0, 220)}...';
  }
}
