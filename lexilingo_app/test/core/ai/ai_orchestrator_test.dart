import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/ai/ai_core.dart';
import 'dart:typed_data';

void main() {
  group('AI Orchestrator Tests', () {
    late AIOrchestrator orchestrator;
    late ContextManager contextManager;

    setUp(() async {
      contextManager = ContextManager();
      orchestrator = AIOrchestrator(
        contextManager: contextManager,
        sttService: MockSTTService(),
        ttsService: MockTTSService(),
        pronunciationService: MockPronunciationService(),
      );

      await orchestrator.initialize();
    });

    tearDown(() async {
      await orchestrator.dispose();
    });

    test('Orchestrator initializes successfully', () {
      expect(orchestrator.isReady, isTrue);
      expect(orchestrator.loadedModels, isNotEmpty);
      expect(orchestrator.loadedModels.contains('STT'), isTrue);
      expect(orchestrator.loadedModels.contains('TTS'), isTrue);
      expect(orchestrator.loadedModels.contains('Pronunciation'), isTrue);
    });

    test('Process text input with grammar error', () async {
      final response = await orchestrator.processText(
        userText: 'I am go to the kitchen for coffee',
      );

      expect(response.responseEn, isNotEmpty);
      expect(response.analysis.grammarErrors, isNotEmpty);
      expect(response.analysis.grammarErrors.first.incorrect, contains('am go'));
      expect(response.analysis.grammarErrors.first.correction,
          contains('am going'));
      expect(response.confidence, lessThan(1.0));
      expect(response.latencyMs, greaterThan(0));
    });

    test('Process text input without errors', () async {
      final response = await orchestrator.processText(
        userText: 'I am going to the kitchen for coffee',
      );

      expect(response.responseEn, contains('Great'));
      expect(response.analysis.grammarErrors, isEmpty);
      expect(response.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Process audio input', () async {
      final mockAudio = Uint8List.fromList(
        List.generate(44100, (i) => (i % 256)),
      );

      final response = await orchestrator.processAudio(
        audioBytes: mockAudio,
      );

      expect(response.responseEn, isNotEmpty);
      expect(response.analysis.pronunciation, isNotNull);
      expect(response.analysis.pronunciation!.accuracy, greaterThan(0.0));
      expect(response.componentUsage.usedSTT, isTrue);
      expect(response.componentUsage.usedHuBERT, isTrue);
    });

    test('Vietnamese explanation for A2 learner', () async {
      contextManager.setLearnerProfile(LearnerProfile(
        userId: 'test',
        level: LearnerLevel.a2,
        commonErrors: [],
        totalSessions: 1,
      ));

      final response = await orchestrator.processText(
        userText: 'I am go to the kitchen',
      );

      expect(response.responseVi, isNotNull);
      expect(response.responseVi, isNotEmpty);
    });

    test('No Vietnamese explanation for B2 learner', () async {
      contextManager.setLearnerProfile(LearnerProfile(
        userId: 'test',
        level: LearnerLevel.b2,
        commonErrors: [],
        totalSessions: 1,
      ));

      final response = await orchestrator.processText(
        userText: 'I am going to the kitchen',
      );

      // B2 with no errors should not get Vietnamese
      expect(response.responseVi, isNull);
    });

    test('TTS synthesis', () async {
      final audio = await orchestrator.synthesizeResponse('Hello');

      expect(audio, isNotEmpty);
      expect(audio.length, greaterThan(0));
    });
  });

  group('Context Manager Tests', () {
    late ContextManager contextManager;

    setUp(() {
      contextManager = ContextManager();
    });

    test('Add conversation turns', () {
      contextManager.addTurn(ConversationTurn(
        userMessage: 'Hello',
        aiResponse: 'Hi there!',
      ));

      expect(contextManager.history.length, equals(1));
      expect(contextManager.history.first.userMessage, equals('Hello'));
    });

    test('Sliding window keeps only 5 turns', () {
      for (int i = 0; i < 10; i++) {
        contextManager.addTurn(ConversationTurn(
          userMessage: 'Message $i',
          aiResponse: 'Response $i',
        ));
      }

      expect(contextManager.history.length, equals(5));
      expect(contextManager.history.first.userMessage, equals('Message 5'));
      expect(contextManager.history.last.userMessage, equals('Message 9'));
    });

    test('Learner profile', () {
      final profile = LearnerProfile(
        userId: 'test123',
        level: LearnerLevel.b1,
        commonErrors: ['past_tense'],
        totalSessions: 5,
      );

      contextManager.setLearnerProfile(profile);

      expect(contextManager.learnerProfile, isNotNull);
      expect(contextManager.learnerProfile!.userId, equals('test123'));
      expect(contextManager.learnerLevel, equals(LearnerLevel.b1));
    });

    test('Context summary generation', () {
      contextManager.addTurn(ConversationTurn(
        userMessage: 'I like coffee',
        aiResponse: 'Great!',
      ));

      final summary = contextManager.getContextSummary();

      expect(summary, contains('I like coffee'));
      expect(summary, contains('Great!'));
    });

    test('Vietnamese needed for A2', () {
      contextManager.setLearnerProfile(LearnerProfile(
        userId: 'test',
        level: LearnerLevel.a2,
        commonErrors: [],
        totalSessions: 1,
      ));

      expect(contextManager.needsVietnameseExplanation(), isTrue);
    });

    test('Vietnamese needed for low confidence', () {
      contextManager.setLearnerProfile(LearnerProfile(
        userId: 'test',
        level: LearnerLevel.b1,
        commonErrors: [],
        totalSessions: 1,
      ));

      expect(
          contextManager.needsVietnameseExplanation(confidenceScore: 0.7),
          isTrue);
      expect(
          contextManager.needsVietnameseExplanation(confidenceScore: 0.9),
          isFalse);
    });
  });

  group('STT Service Tests', () {
    late MockSTTService sttService;

    setUp(() async {
      sttService = MockSTTService();
      await sttService.initialize();
    });

    tearDown(() async {
      await sttService.dispose();
    });

    test('STT initialization', () {
      expect(sttService.isReady, isTrue);
      expect(sttService.modelInfo.name, contains('Faster-Whisper'));
    });

    test('Transcribe audio', () async {
      final mockAudio = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final result = await sttService.transcribe(audioBytes: mockAudio);

      expect(result.text, isNotEmpty);
      expect(result.confidence, greaterThan(0.0));
      expect(result.processingTimeMs, greaterThan(0));
    });

    test('Transcribe with timestamps', () async {
      final mockAudio = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final result = await sttService.transcribe(
        audioBytes: mockAudio,
        withTimestamps: true,
      );

      expect(result.wordTimestamps, isNotNull);
      expect(result.wordTimestamps, isNotEmpty);
    });
  });

  group('TTS Service Tests', () {
    late MockTTSService ttsService;

    setUp(() async {
      ttsService = MockTTSService();
      await ttsService.initialize();
    });

    tearDown(() async {
      await ttsService.dispose();
    });

    test('TTS initialization', () {
      expect(ttsService.isReady, isTrue);
      expect(ttsService.modelInfo.name, contains('Piper'));
    });

    test('Synthesize text', () async {
      final audio = await ttsService.synthesize(text: 'Hello world');

      expect(audio, isNotEmpty);
      expect(audio.length, greaterThan(0));
    });

    test('Cache common phrases', () async {
      await ttsService.synthesize(text: 'Great job!', cacheKey: 'great_job');

      final cached = ttsService.getCached('great_job');
      expect(cached, isNotNull);
      expect(cached, isNotEmpty);
    });

    test('Pre-generate common phrases', () async {
      // Already done in initialization
      final cached1 = ttsService.getCached('Great job!');
      final cached2 = ttsService.getCached('Try again');

      expect(cached1, isNotNull);
      expect(cached2, isNotNull);
    });
  });

  group('Pronunciation Service Tests', () {
    late MockPronunciationService pronunciationService;

    setUp(() async {
      pronunciationService = MockPronunciationService();
      await pronunciationService.initialize();
    });

    tearDown(() async {
      await pronunciationService.dispose();
    });

    test('Pronunciation initialization', () {
      expect(pronunciationService.isReady, isTrue);
      expect(pronunciationService.modelInfo.name, contains('HuBERT'));
    });

    test('Analyze pronunciation', () async {
      final mockAudio = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final result = await pronunciationService.analyze(
        audioBytes: mockAudio,
        transcribedText: 'I think the weather is nice',
      );

      expect(result.accuracy, greaterThan(0.0));
      expect(result.accuracy, lessThanOrEqualTo(1.0));
      expect(result.prosodyScore, greaterThan(0.0));
    });

    test('Detect pronunciation errors', () async {
      final mockAudio = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final result = await pronunciationService.analyze(
        audioBytes: mockAudio,
        transcribedText: 'I think this is the best',
      );

      // Mock service detects /θ/ and /ð/ errors
      expect(result.errors, isNotEmpty);
    });
  });
}
