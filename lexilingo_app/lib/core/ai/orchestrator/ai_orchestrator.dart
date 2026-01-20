import 'dart:typed_data';
import '../models/ai_task.dart';
import '../models/ai_response.dart';
import '../context/context_manager.dart';
import '../stt/stt_service.dart';
import '../tts/tts_service.dart';
import '../pronunciation/pronunciation_service.dart';

/// AI Orchestrator - Central coordinator for the AI pipeline
/// 
/// This is the core engine that manages:
/// - Task analysis and planning
/// - Resource allocation (model loading)
/// - Execution coordination (sequential + parallel)
/// - Error handling and fallback
/// - State management
/// 
/// Following the architecture diagram in docs/architecture.md
class AIOrchestrator {
  final ContextManager contextManager;
  final STTService? sttService;
  final TTSService? ttsService;
  final PronunciationService? pronunciationService;

  // State tracking
  final Set<String> _loadedModels = {};
  bool _isInitialized = false;
  final Map<String, dynamic> _performanceMetrics = {};

  AIOrchestrator({
    required this.contextManager,
    this.sttService,
    this.ttsService,
    this.pronunciationService,
  });

  /// Initialize all required services
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('[Orchestrator] Initializing AI pipeline...');
    final startTime = DateTime.now();

    try {
      // Initialize services in parallel where possible
      final futures = <Future>[];

      if (sttService != null) {
        futures.add(_initService('STT', () => sttService!.initialize()));
      }

      if (ttsService != null) {
        futures.add(_initService('TTS', () => ttsService!.initialize()));
      }

      if (pronunciationService != null) {
        futures.add(_initService('Pronunciation', 
            () => pronunciationService!.initialize()));
      }

      await Future.wait(futures);

      _isInitialized = true;
      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      print('[Orchestrator] Initialized in ${totalTime}ms');
    } catch (e) {
      print('[Orchestrator] Initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _initService(String name, Future<void> Function() init) async {
    try {
      await init();
      _loadedModels.add(name);
      print('[Orchestrator] ✓ $name service ready');
    } catch (e) {
      print('[Orchestrator] ✗ $name service failed: $e');
    }
  }

  /// Process text input (no audio)
  /// 
  /// Flow:
  /// 1. Task analysis
  /// 2. Context retrieval
  /// 3. Grammar/fluency analysis (Qwen)
  /// 4. Vietnamese explanation (if needed)
  /// 5. Response aggregation
  Future<AIResponse> processText({
    required String userText,
    String? sessionId,
  }) async {
    if (!_isInitialized) {
      throw StateError('Orchestrator not initialized. Call initialize() first.');
    }

    print('[Orchestrator] Processing text: "$userText"');
    final pipelineStart = DateTime.now();

    try {
      // Phase 1: Task Analysis
      final taskAnalysis = _analyzeTask(
        userText: userText,
        hasAudio: false,
      );
      print('[Orchestrator] Task analysis: $taskAnalysis');

      // Phase 2: Context Retrieval
      final contextSummary = contextManager.getContextSummary();

      // Phase 3: Execute primary tasks (Qwen analysis)
      final analysisResult = await _executeGrammarAnalysis(
        userText: userText,
        context: contextSummary,
        learnerLevel: taskAnalysis.learnerLevel,
      );

      // Phase 4: Conditional Vietnamese explanation
      String? vietnameseResponse;
      if (taskAnalysis.needVietnamese) {
        vietnameseResponse = await _generateVietnameseExplanation(
          userText: userText,
          analysisResult: analysisResult,
        );
      }

      // Phase 5: Generate tutor response
      final englishResponse = _generateTutorResponse(
        analysisResult: analysisResult,
        strategy: taskAnalysis.strategy,
        learnerLevel: taskAnalysis.learnerLevel,
      );

      // Update conversation history
      contextManager.addTurn(ConversationTurn(
        userMessage: userText,
        aiResponse: englishResponse,
      ));

      // Calculate total latency
      final totalLatency = DateTime.now().difference(pipelineStart).inMilliseconds;

      return AIResponse(
        analysis: analysisResult,
        responseEn: englishResponse,
        responseVi: vietnameseResponse,
        confidence: _calculateConfidence(analysisResult),
        latencyMs: totalLatency,
        componentUsage: const ComponentUsage(
          usedQwen: true,
          usedLLaMA: false, // TODO: implement when LLaMA is integrated
          usedHuBERT: false,
          usedSTT: false,
          usedTTS: false,
          usedCache: false, // TODO: implement Redis cache
        ),
      );
    } catch (e, stackTrace) {
      print('[Orchestrator] Error processing text: $e');
      print(stackTrace);
      return _handleError(e);
    }
  }

  /// Process audio input (with pronunciation analysis)
  /// 
  /// Flow:
  /// 1. STT (transcribe audio)
  /// 2. Task analysis
  /// 3. Parallel execution:
  ///    - Grammar/fluency analysis
  ///    - Pronunciation analysis
  /// 4. Wait for all tasks
  /// 5. Vietnamese explanation (if needed)
  /// 6. Response aggregation
  Future<AIResponse> processAudio({
    required Uint8List audioBytes,
    String? sessionId,
  }) async {
    if (!_isInitialized) {
      throw StateError('Orchestrator not initialized. Call initialize() first.');
    }

    if (sttService == null || pronunciationService == null) {
      throw StateError('Audio processing requires STT and Pronunciation services');
    }

    print('[Orchestrator] Processing audio (${audioBytes.length} bytes)');
    final pipelineStart = DateTime.now();

    try {
      // Step 1: STT
      final transcription = await sttService!.transcribe(
        audioBytes: audioBytes,
        withTimestamps: true,
      );
      print('[Orchestrator] Transcribed: "${transcription.text}"');

      // Step 2: Task analysis
      final taskAnalysis = _analyzeTask(
        userText: transcription.text,
        hasAudio: true,
      );

      // Step 3 & 4: Parallel execution
      final contextSummary = contextManager.getContextSummary();

      final results = await Future.wait([
        // Task 1: Grammar/fluency analysis
        _executeGrammarAnalysis(
          userText: transcription.text,
          context: contextSummary,
          learnerLevel: taskAnalysis.learnerLevel,
        ),
        // Task 2: Pronunciation analysis
        pronunciationService!.analyze(
          audioBytes: audioBytes,
          transcribedText: transcription.text,
        ),
      ]);

      final analysisResult = results[0] as AnalysisResult;
      final pronunciationResult = results[1] as PronunciationResult;

      // Merge pronunciation result into analysis
      final completeAnalysis = AnalysisResult(
        fluencyScore: analysisResult.fluencyScore,
        vocabularyLevel: analysisResult.vocabularyLevel,
        grammarErrors: analysisResult.grammarErrors,
        pronunciation: pronunciationResult,
      );

      // Step 5: Vietnamese explanation (if needed)
      String? vietnameseResponse;
      if (taskAnalysis.needVietnamese) {
        vietnameseResponse = await _generateVietnameseExplanation(
          userText: transcription.text,
          analysisResult: completeAnalysis,
        );
      }

      // Step 6: Generate tutor response
      final englishResponse = _generateTutorResponse(
        analysisResult: completeAnalysis,
        strategy: taskAnalysis.strategy,
        learnerLevel: taskAnalysis.learnerLevel,
      );

      // Update conversation history
      contextManager.addTurn(ConversationTurn(
        userMessage: transcription.text,
        aiResponse: englishResponse,
      ));

      final totalLatency = DateTime.now().difference(pipelineStart).inMilliseconds;

      return AIResponse(
        analysis: completeAnalysis,
        responseEn: englishResponse,
        responseVi: vietnameseResponse,
        confidence: _calculateConfidence(completeAnalysis),
        latencyMs: totalLatency,
        componentUsage: const ComponentUsage(
          usedQwen: true,
          usedLLaMA: false,
          usedHuBERT: true,
          usedSTT: true,
          usedTTS: false,
          usedCache: false,
        ),
      );
    } catch (e, stackTrace) {
      print('[Orchestrator] Error processing audio: $e');
      print(stackTrace);
      return _handleError(e);
    }
  }

  /// Synthesize response to audio (TTS)
  Future<Uint8List> synthesizeResponse(String text) async {
    if (ttsService == null) {
      throw StateError('TTS service not available');
    }

    return await ttsService!.synthesize(text: text);
  }

  // ============ Private Methods ============

  /// Phase 1: Task Analysis
  TaskAnalysis _analyzeTask({
    required String userText,
    required bool hasAudio,
  }) {
    final learnerLevel = contextManager.learnerLevel;
    final wordCount = userText.split(' ').length;

    // Determine complexity
    final complexity = wordCount < 5
        ? TaskComplexity.simple
        : wordCount < 15
            ? TaskComplexity.medium
            : TaskComplexity.complex;

    // Determine primary tasks
    final primaryTasks = <AITaskType>[
      AITaskType.grammar,
      AITaskType.fluency,
      AITaskType.vocabulary,
    ];

    // Determine parallel tasks
    final parallelTasks = <AITaskType>[];
    if (hasAudio) {
      parallelTasks.add(AITaskType.pronunciation);
    }

    // Check if Vietnamese explanation needed
    final needVietnamese = contextManager.needsVietnameseExplanation();

    // Determine feedback strategy (simplified for now)
    final strategy = learnerLevel == LearnerLevel.a2
        ? FeedbackStrategy.explain
        : FeedbackStrategy.correct;

    return TaskAnalysis(
      primaryTasks: primaryTasks,
      parallelTasks: parallelTasks,
      needVietnamese: needVietnamese,
      strategy: strategy,
      complexity: complexity,
      learnerLevel: learnerLevel,
    );
  }

  /// Execute grammar and fluency analysis
  /// TODO: Integrate with actual Qwen2.5 + LoRA model
  Future<AnalysisResult> _executeGrammarAnalysis({
    required String userText,
    required String context,
    required LearnerLevel learnerLevel,
  }) async {
    // Simulate analysis latency
    await Future.delayed(const Duration(milliseconds: 120));

    // Mock analysis
    final errors = <GrammarError>[];

    // Example: detect "I am go" error (must be exact match to avoid false positives)
    final lowerText = userText.toLowerCase();
    if (lowerText.contains('i am go ') || lowerText.contains('i am go.')) {
      errors.add(const GrammarError(
        errorType: 'incorrect_verb_form',
        incorrect: 'am go',
        correction: 'am going',
        explanation: 'Use present continuous "am going" for current action',
        startPos: 2,
        endPos: 7,
      ));
    }

    // Mock fluency score
    final fluencyScore = errors.isEmpty ? 0.90 : 0.75;

    // Mock vocabulary level
    final vocabularyLevel = learnerLevel.displayName;

    print('[Orchestrator] Grammar analysis: ${errors.length} errors, fluency: $fluencyScore');

    return AnalysisResult(
      fluencyScore: fluencyScore,
      vocabularyLevel: vocabularyLevel,
      grammarErrors: errors,
      pronunciation: null, // Will be added later if audio input
    );
  }

  /// Generate Vietnamese explanation
  /// TODO: Integrate with LLaMA3-8B-VI model
  Future<String> _generateVietnameseExplanation({
    required String userText,
    required AnalysisResult analysisResult,
  }) async {
    // Simulate LLaMA3-VI processing
    await Future.delayed(const Duration(milliseconds: 200));

    if (analysisResult.grammarErrors.isNotEmpty) {
      final firstError = analysisResult.grammarErrors.first;
      return 'Bạn cần sửa "${firstError.incorrect}" thành "${firstError.correction}". '
          '${firstError.explanation} (dùng thì hiện tại tiếp diễn cho hành động đang xảy ra).';
    }

    return 'Bạn làm tốt lắm! Câu của bạn rất tự nhiên.';
  }

  /// Generate tutor response in English
  String _generateTutorResponse({
    required AnalysisResult analysisResult,
    required FeedbackStrategy strategy,
    required LearnerLevel learnerLevel,
  }) {
    if (analysisResult.grammarErrors.isEmpty) {
      // No errors - praise
      return 'Great job! Your sentence is correct and natural. Keep up the good work!';
    }

    // Has errors - provide correction
    final firstError = analysisResult.grammarErrors.first;
    
    switch (strategy) {
      case FeedbackStrategy.praise:
        return 'Good effort! ${_formatCorrection(firstError)}';
      
      case FeedbackStrategy.correct:
        return 'Almost there! ${_formatCorrection(firstError)} Try: "${firstError.correction}"';
      
      case FeedbackStrategy.explain:
        return 'Let me help you. ${_formatCorrection(firstError)} '
            '${firstError.explanation}. The correct form is: "${firstError.correction}"';
      
      case FeedbackStrategy.drill:
        return 'Let\'s practice this again. ${_formatCorrection(firstError)} '
            'Try to use "${firstError.correction}" in a new sentence.';
    }
  }

  String _formatCorrection(GrammarError error) {
    return 'I noticed "${error.incorrect}" should be "${error.correction}".';
  }

  /// Calculate overall confidence score
  double _calculateConfidence(AnalysisResult analysis) {
    double confidence = 0.9; // Base confidence

    // Reduce confidence for grammar errors
    if (analysis.grammarErrors.isNotEmpty) {
      confidence -= analysis.grammarErrors.length * 0.1;
    }

    // Factor in fluency
    if (analysis.fluencyScore != null && analysis.fluencyScore! < 0.7) {
      confidence -= 0.1;
    }

    // Factor in pronunciation
    if (analysis.pronunciation != null && analysis.pronunciation!.accuracy < 0.7) {
      confidence -= 0.1;
    }

    return confidence.clamp(0.0, 1.0);
  }

  /// Error handling with graceful degradation
  AIResponse _handleError(Object error) {
    print('[Orchestrator] Handling error with fallback...');

    // Fallback response
    return AIResponse(
      analysis: AnalysisResult(
        grammarErrors: [],
        fluencyScore: null,
        vocabularyLevel: null,
      ),
      responseEn: 'I\'m sorry, I encountered an issue analyzing your message. '
          'Could you please try again?',
      responseVi: null,
      confidence: 0.0,
      latencyMs: 0,
      componentUsage: const ComponentUsage(
        usedQwen: false,
        usedLLaMA: false,
        usedHuBERT: false,
        usedSTT: false,
        usedTTS: false,
        usedCache: false,
      ),
    );
  }

  /// Get performance metrics
  Map<String, dynamic> get performanceMetrics => Map.unmodifiable(_performanceMetrics);

  /// Check if orchestrator is ready
  bool get isReady => _isInitialized;

  /// Get loaded models
  Set<String> get loadedModels => Set.unmodifiable(_loadedModels);

  /// Clean up all resources
  Future<void> dispose() async {
    print('[Orchestrator] Disposing...');
    
    await Future.wait([
      if (sttService != null) sttService!.dispose(),
      if (ttsService != null) ttsService!.dispose(),
      if (pronunciationService != null) pronunciationService!.dispose(),
    ]);

    _loadedModels.clear();
    _performanceMetrics.clear();
    _isInitialized = false;
    
    print('[Orchestrator] Disposed');
  }
}
