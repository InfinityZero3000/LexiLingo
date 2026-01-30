import 'dart:typed_data';
import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/voice/data/datasources/voice_remote_datasource.dart';
import 'package:lexilingo_app/features/voice/domain/entities/audio_synthesis.dart';
import 'package:lexilingo_app/features/voice/domain/entities/transcription.dart';
import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';
import 'package:lexilingo_app/features/voice/domain/repositories/voice_repository.dart';

/// Voice Repository Implementation
/// Handles voice operations with proper error handling
class VoiceRepositoryImpl implements VoiceRepository {
  final VoiceRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  VoiceRepositoryImpl({
    required this.remoteDataSource,
    required this.networkInfo,
  });

  @override
  Future<Either<Failure, Transcription>> transcribeAudio({
    required Uint8List audioData,
    required String filename,
    String? language,
  }) async {
    if (await networkInfo.isConnected == false) {
      return const Left(NetworkFailure());
    }
    
    try {
      final result = await remoteDataSource.transcribeAudio(
        audioData: audioData,
        filename: filename,
        language: language,
      );
      
      return Right(Transcription(
        text: result['text'] ?? '',
        language: result['language'],
      ));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to transcribe: $e'));
    }
  }

  @override
  Future<Either<Failure, AudioSynthesis>> synthesizeSpeech({
    required String text,
  }) async {
    if (await networkInfo.isConnected == false) {
      return const Left(NetworkFailure());
    }
    
    try {
      final audioBytes = await remoteDataSource.synthesizeSpeech(text: text);
      
      return Right(AudioSynthesis(
        audioData: audioBytes,
        mimeType: 'audio/wav',
      ));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to synthesize: $e'));
    }
  }

  @override
  Future<Either<Failure, PronunciationScore>> assessPronunciation({
    required Uint8List audioData,
    required String filename,
    required String targetText,
    String? language,
  }) async {
    if (await networkInfo.isConnected == false) {
      return const Left(NetworkFailure());
    }
    
    try {
      // First, transcribe the audio
      final transcriptionResult = await remoteDataSource.transcribeAudio(
        audioData: audioData,
        filename: filename,
        language: language,
      );
      
      final userTranscript = transcriptionResult['text'] ?? '';
      
      // Calculate scores based on text comparison
      // This is a basic implementation - can be enhanced with AI
      final score = _calculatePronunciationScore(userTranscript, targetText);
      
      return Right(score);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to assess pronunciation: $e'));
    }
  }

  /// Calculate pronunciation score based on text similarity
  /// This is a basic implementation comparing words
  PronunciationScore _calculatePronunciationScore(
    String userTranscript,
    String targetText,
  ) {
    final userWords = _normalizeText(userTranscript).split(' ');
    final targetWords = _normalizeText(targetText).split(' ');
    
    int matchedWords = 0;
    final wordScores = <WordScore>[];
    
    for (int i = 0; i < targetWords.length; i++) {
      if (i < userWords.length) {
        final target = targetWords[i];
        final user = userWords[i];
        
        if (target == user) {
          matchedWords++;
          wordScores.add(WordScore(word: target, score: 100));
        } else if (_levenshteinDistance(target, user) <= 2) {
          matchedWords++;
          wordScores.add(WordScore(
            word: target,
            score: 70,
            issue: 'mispronunciation',
          ));
        } else {
          wordScores.add(WordScore(
            word: target,
            score: 30,
            issue: 'mispronunciation',
          ));
        }
      } else {
        wordScores.add(WordScore(
          word: targetWords[i],
          score: 0,
          issue: 'omission',
        ));
      }
    }
    
    // Check for extra words (insertions)
    if (userWords.length > targetWords.length) {
      for (int i = targetWords.length; i < userWords.length; i++) {
        wordScores.add(WordScore(
          word: userWords[i],
          score: 0,
          issue: 'insertion',
        ));
      }
    }
    
    // Calculate overall scores
    final accuracyScore = targetWords.isEmpty 
        ? 0 
        : ((matchedWords / targetWords.length) * 100).round();
    
    final completenessScore = targetWords.isEmpty
        ? 0
        : ((wordScores.where((w) => w.issue != 'omission').length / 
            targetWords.length) * 100).round().clamp(0, 100);
    
    final fluencyScore = userTranscript.isEmpty ? 0 : 80; // Basic assumption
    
    final overallScore = ((accuracyScore + completenessScore + fluencyScore) / 3).round();
    
    String feedback;
    if (overallScore >= 90) {
      feedback = 'Excellent pronunciation! Keep up the great work!';
    } else if (overallScore >= 70) {
      feedback = 'Good job! A few words need improvement.';
    } else if (overallScore >= 50) {
      feedback = 'Keep practicing! Focus on the highlighted words.';
    } else {
      feedback = 'Try again slowly. Listen to the example first.';
    }
    
    return PronunciationScore(
      overallScore: overallScore.clamp(0, 100),
      accuracyScore: accuracyScore.clamp(0, 100),
      fluencyScore: fluencyScore.clamp(0, 100),
      completenessScore: completenessScore.clamp(0, 100),
      userTranscript: userTranscript,
      targetText: targetText,
      wordScores: wordScores,
      feedback: feedback,
    );
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    
    List<int> v0 = List.generate(s2.length + 1, (i) => i);
    List<int> v1 = List.filled(s2.length + 1, 0);
    
    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      
      for (int j = 0; j < s2.length; j++) {
        int cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      
      final temp = v0;
      v0 = v1;
      v1 = temp;
    }
    
    return v0[s2.length];
  }
}
