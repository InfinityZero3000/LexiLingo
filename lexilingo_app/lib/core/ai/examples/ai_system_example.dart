import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../context/context_manager.dart';
import '../orchestrator/ai_orchestrator.dart';
import '../stt/stt_service.dart';
import '../tts/tts_service.dart';
import '../pronunciation/pronunciation_service.dart';
import '../models/ai_task.dart';

/// Example usage of the LexiLingo AI system
/// 
/// This demonstrates how to:
/// 1. Initialize the AI pipeline
/// 2. Process text input
/// 3. Process audio input (with pronunciation)
/// 4. Handle responses
/// 5. Generate audio output
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('═══════════════════════════════════════════════════════════');
  print('    LexiLingo AI System - Example Usage');
  print('═══════════════════════════════════════════════════════════\n');

  // ============================================================
  // STEP 1: Initialize AI Components
  // ============================================================
  print('📦 Initializing AI components...\n');

  final contextManager = ContextManager();
  final orchestrator = AIOrchestrator(
    contextManager: contextManager,
    sttService: MockSTTService(),
    ttsService: MockTTSService(),
    pronunciationService: MockPronunciationService(),
  );

  await orchestrator.initialize();

  print('AI pipeline ready!\n');
  print('Loaded models: ${orchestrator.loadedModels}\n');

  // ============================================================
  // STEP 2: Set Learner Profile
  // ============================================================
  print('👤 Setting learner profile...\n');

  contextManager.setLearnerProfile(LearnerProfile(
    userId: 'user123',
    level: LearnerLevel.a2, // Elementary learner
    commonErrors: ['past_tense', 'articles', 'verb_forms'],
    totalSessions: 10,
  ));

  print('Profile: Level ${contextManager.learnerLevel.displayName}\n');

  // ============================================================
  // STEP 3: Process Text Input (Grammar Check)
  // ============================================================
  print('══════════════════════════════════════════════════════════');
  print('EXAMPLE 1: Text Processing (Grammar Check)');
  print('══════════════════════════════════════════════════════════\n');

  final userInput1 = 'I am go to the kitchen for coffee';
  print('User says: "$userInput1"\n');

  final response1 = await orchestrator.processText(userText: userInput1);

  print('AI Analysis:');
  print('  - Fluency Score: ${response1.analysis.fluencyScore}');
  print('  - Vocabulary Level: ${response1.analysis.vocabularyLevel}');
  print('  - Grammar Errors: ${response1.analysis.grammarErrors.length}');
  
  if (response1.analysis.grammarErrors.isNotEmpty) {
    print('\n  Errors found:');
    for (final error in response1.analysis.grammarErrors) {
      print('    ❌ "${error.incorrect}" → "${error.correction}"');
      print('       Type: ${error.errorType}');
      print('       Explanation: ${error.explanation}');
    }
  }

  print('\n📢 Tutor Response (English):');
  print('  "${response1.responseEn}"\n');

  if (response1.responseVi != null) {
    print('🇻🇳 Vietnamese Explanation:');
    print('  "${response1.responseVi}"\n');
  }

  print('⏱️  Processing Time: ${response1.latencyMs}ms');
  print('🎯 Confidence: ${(response1.confidence * 100).toStringAsFixed(1)}%');
  print('🔧 Components Used: ${response1.componentUsage}\n');

  // ============================================================
  // STEP 4: Process Audio Input (with Pronunciation)
  // ============================================================
  print('══════════════════════════════════════════════════════════');
  print('EXAMPLE 2: Audio Processing (Pronunciation Check)');
  print('══════════════════════════════════════════════════════════\n');

  // Simulate audio input (in real app, this would be from microphone)
  final mockAudio = Uint8List.fromList(
    List.generate(44100, (i) => (i % 256)), // 1 second mock audio
  );

  print('🎤 User speaks (audio)...\n');

  final response2 = await orchestrator.processAudio(audioBytes: mockAudio);

  print('AI Analysis:');
  print('  - Transcribed: "${response2.analysis.fluencyScore}"');
  print('  - Fluency Score: ${response2.analysis.fluencyScore}');
  print('  - Grammar Errors: ${response2.analysis.grammarErrors.length}');

  if (response2.analysis.pronunciation != null) {
    final pronResult = response2.analysis.pronunciation!;
    print('\n  🗣️ Pronunciation:');
    print('    - Accuracy: ${(pronResult.accuracy * 100).toStringAsFixed(1)}%');
    print('    - Prosody Score: ${(pronResult.prosodyScore * 100).toStringAsFixed(1)}%');
    
    if (pronResult.errors.isNotEmpty) {
      print('\n    Pronunciation errors:');
      for (final error in pronResult.errors) {
        print('      ❌ Phoneme ${error.phoneme} in "${error.word}"');
        print('         Pronounced as: ${error.pronouncedAs}');
      }
    }
  }

  print('\n📢 Tutor Response:');
  print('  "${response2.responseEn}"\n');

  print('⏱️  Processing Time: ${response2.latencyMs}ms');
  print('🎯 Confidence: ${(response2.confidence * 100).toStringAsFixed(1)}%\n');

  // ============================================================
  // STEP 5: Synthesize Response to Audio (TTS)
  // ============================================================
  print('══════════════════════════════════════════════════════════');
  print('EXAMPLE 3: Text-to-Speech Synthesis');
  print('══════════════════════════════════════════════════════════\n');

  final textToSpeak = 'Great job! Your pronunciation is improving.';
  print('Text to synthesize: "$textToSpeak"\n');

  final audioOutput = await orchestrator.synthesizeResponse(textToSpeak);

  print('🔊 Audio synthesized:');
  print('  - Size: ${audioOutput.length} bytes');
  print('  - Format: WAV (22kHz)');
  print('  - Ready to play!\n');

  // ============================================================
  // STEP 6: Conversation History
  // ============================================================
  print('══════════════════════════════════════════════════════════');
  print('EXAMPLE 4: Conversation History');
  print('══════════════════════════════════════════════════════════\n');

  print('📝 Conversation History (${contextManager.history.length} turns):\n');

  for (var i = 0; i < contextManager.history.length; i++) {
    final turn = contextManager.history[i];
    print('Turn ${i + 1}:');
    print('  User: "${turn.userMessage}"');
    if (turn.aiResponse != null) {
      print('  AI:   "${turn.aiResponse}"');
    }
    print('  Time: ${turn.timestamp}\n');
  }

  // ============================================================
  // STEP 7: Performance Metrics
  // ============================================================
  print('══════════════════════════════════════════════════════════');
  print('EXAMPLE 5: Performance Metrics');
  print('══════════════════════════════════════════════════════════\n');

  print('📊 System Status:');
  print('  - Initialized: ${orchestrator.isReady}');
  print('  - Loaded Models: ${orchestrator.loadedModels}');
  print('  - Conversation Turns: ${contextManager.history.length}');
  print('  - Learner Level: ${contextManager.learnerLevel.displayName}\n');

  // ============================================================
  // STEP 8: Cleanup
  // ============================================================
  print('══════════════════════════════════════════════════════════');
  print('Cleanup');
  print('══════════════════════════════════════════════════════════\n');

  await orchestrator.dispose();
  print('Resources released\n');

  print('═══════════════════════════════════════════════════════════');
  print('    Example completed successfully!');
  print('═══════════════════════════════════════════════════════════');
}

/// Example of error handling
Future<void> errorHandlingExample() async {
  final contextManager = ContextManager();
  final orchestrator = AIOrchestrator(
    contextManager: contextManager,
    // Deliberately not providing services to trigger errors
  );

  await orchestrator.initialize();

  try {
    // This will fail gracefully
    final response = await orchestrator.processText(
      userText: 'Hello',
    );
    
    // Orchestrator will return fallback response
    print('Fallback response: ${response.responseEn}');
    print('Confidence: ${response.confidence}'); // Will be 0.0
  } catch (e) {
    print('Error caught: $e');
  }
}

/// Example of level-based adaptation
void levelAdaptationExample() {
  print('\n══════════════════════════════════════════════════════════');
  print('Learner Level Adaptation');
  print('══════════════════════════════════════════════════════════\n');

  final levels = [LearnerLevel.a2, LearnerLevel.b1, LearnerLevel.b2];

  for (final level in levels) {
    print('${level.displayName}:');
    
    switch (level) {
      case LearnerLevel.a2:
        print('  - Simple words, short sentences');
        print('  - More Vietnamese explanations');
        print('  - Detailed guidance');
        break;
      
      case LearnerLevel.b1:
        print('  - Natural conversation');
        print('  - Some complexity');
        print('  - Gentle corrections');
        break;
      
      case LearnerLevel.b2:
        print('  - Near-native interaction');
        print('  - Minimal hand-holding');
        print('  - Brief corrections');
        break;
    }
    print('');
  }
}
