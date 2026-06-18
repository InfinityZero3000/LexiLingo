import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
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
  final BackendAuthHeaderProvider authHeaderProvider;

  VoiceRemoteDataSourceImpl({
    http.Client? client,
    String? baseUrl,
    required this.authHeaderProvider,
  }) : client = client ?? http.Client(),
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

      final authHeaders = await authHeaderProvider.call();
      request.headers.addAll(authHeaders);

      // Add audio file
      request.files.add(
        http.MultipartFile.fromBytes('audio', audioData, filename: filename),
      );

      // Add language if provided
      if (language != null) {
        request.fields['language'] = language;
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw ServerException('STT request timed out after 30s'),
      );
      final response = await http.Response.fromStream(streamedResponse).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw ServerException('STT response timed out after 30s'),
      );

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

      final authHeaders = await authHeaderProvider.call();

      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
        body: json.encode({'text': text}),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw ServerException('TTS request timed out after 30s'),
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
