# LexiLingo AI Core System

Complete AI pipeline implementation following the architecture in `/docs/architecture.md`.

## 📁 Structure

```
lib/core/ai/
├── models/               # Data models
│   ├── ai_task.dart     # Task types, complexity, learner levels
│   └── ai_response.dart # Response formats, analysis results
├── context/             # Context management
│   └── context_manager.dart  # Conversation history, learner profile
├── stt/                 # Speech-to-Text
│   └── stt_service.dart      # Faster-Whisper v3 interface
├── tts/                 # Text-to-Speech
│   └── tts_service.dart      # Piper VITS interface
├── pronunciation/       # Pronunciation analysis
│   └── pronunciation_service.dart  # HuBERT interface
└── orchestrator/        # Core coordinator
    └── ai_orchestrator.dart   # Main AI pipeline
```

## 🎯 Core Components

### 1. AI Orchestrator

Central coordinator managing the entire AI pipeline.

**Key Features:**
- Task analysis and planning
- Resource allocation (lazy loading)
- Parallel execution (Grammar + Pronunciation)
- Error handling with graceful degradation
- State management

**Architecture Phases:**
1. **Task Analysis** - Detect task type, complexity, learner level
2. **Resource Allocation** - Load required models on-demand
3. **Execution Coordination** - Sequential + parallel processing
4. **Error Handling** - Fallback strategies
5. **State Management** - Track loaded models, metrics

### 2. Context Manager

Manages conversation history and learner profile.

**Features:**
- Sliding window history (last 5 turns)
- Learner profile caching (Redis - TODO)
- Context embedding (all-MiniLM-L6-v2 - TODO)
- Knowledge graph integration (TODO)

### 3. STT Service (Speech-to-Text)

Interface for Faster-Whisper v3 model.

**Specs:**
- Model: openai/whisper-small (244MB)
- Latency: 50-100ms
- WER: <10% (ESL)
- Features: VAD, streaming, word timestamps

### 4. TTS Service (Text-to-Speech)

Interface for Piper VITS model.

**Specs:**
- Model: en_US-lessac-medium
- Size: 30-60MB
- Latency: 100-300ms
- Features: Natural prosody, offline capable, caching

### 5. Pronunciation Service

Interface for HuBERT-large model.

**Specs:**
- Model: hubert-large-ls960
- Size: 960MB
- Latency: 100-200ms
- Features: Phoneme recognition, forced alignment

## 🚀 Usage

### Basic Text Processing

```dart
import 'package:lexilingo_app/core/ai/orchestrator/ai_orchestrator.dart';
import 'package:lexilingo_app/core/ai/context/context_manager.dart';
import 'package:lexilingo_app/core/ai/stt/stt_service.dart';
import 'package:lexilingo_app/core/ai/tts/tts_service.dart';
import 'package:lexilingo_app/core/ai/pronunciation/pronunciation_service.dart';

// Initialize
final contextManager = ContextManager();
final orchestrator = AIOrchestrator(
  contextManager: contextManager,
  sttService: MockSTTService(),      // Replace with real implementation
  ttsService: MockTTSService(),      // Replace with real implementation
  pronunciationService: MockPronunciationService(), // Replace with real
);

await orchestrator.initialize();

// Set learner profile
contextManager.setLearnerProfile(LearnerProfile(
  userId: 'user123',
  level: LearnerLevel.a2,
  commonErrors: ['past_tense', 'articles'],
  totalSessions: 10,
));

// Process text input
final response = await orchestrator.processText(
  userText: 'I am go to the kitchen for coffee',
);

print('Analysis: ${response.analysis}');
print('Response (EN): ${response.responseEn}');
print('Response (VI): ${response.responseVi}');
print('Confidence: ${response.confidence}');
print('Latency: ${response.latencyMs}ms');
```

### Audio Processing (with Pronunciation)

```dart
// Assume we have audio bytes from microphone
final audioBytes = Uint8List.fromList([...]); // Your audio data

// Process audio (includes STT + Pronunciation analysis)
final response = await orchestrator.processAudio(
  audioBytes: audioBytes,
);

// Check pronunciation
if (response.analysis.pronunciation != null) {
  final pronResult = response.analysis.pronunciation!;
  print('Pronunciation accuracy: ${pronResult.accuracy}');
  print('Errors: ${pronResult.errors}');
  print('Prosody: ${pronResult.prosodyScore}');
}

// Synthesize response to audio
final responseAudio = await orchestrator.synthesizeResponse(
  response.responseEn,
);

// Play responseAudio...
```

## 🔄 Architecture Flow

### Text Input Flow

```
User Text
    ↓
Task Analysis → Determine tasks, complexity, learner level
    ↓
Context Retrieval → Get conversation history, learner profile
    ↓
Grammar Analysis (Qwen) → Fluency, vocabulary, errors
    ↓
Vietnamese Explanation? → If A2 or low confidence
    ↓
Tutor Response → Generate feedback
    ↓
Response Aggregation → Final AIResponse
```

### Audio Input Flow

```
Audio Bytes
    ↓
STT (Faster-Whisper) → Transcribe to text
    ↓
Task Analysis
    ↓
┌────────────────┬────────────────┐
│ Grammar        │ Pronunciation  │ (Parallel)
│ Analysis       │ Analysis       │
│ (Qwen)         │ (HuBERT)       │
└────────────────┴────────────────┘
    ↓
Wait for all tasks
    ↓
Vietnamese Explanation? → If needed
    ↓
Tutor Response
    ↓
Response Aggregation
```

## 📊 Task Types

- **Grammar** - Correction and analysis
- **Fluency** - Natural flow assessment
- **Vocabulary** - Level detection (A2/B1/B2)
- **Dialogue** - Conversation practice
- **Pronunciation** - Phoneme accuracy (audio only)
- **Vietnamese Explanation** - For A2 learners

## 🎓 Learner Levels

- **A2** - Elementary (needs more hand-holding, Vietnamese)
- **B1** - Intermediate (gentle corrections)
- **B2** - Upper-Intermediate (minimal assistance)

## 🛡️ Error Handling

The orchestrator implements graceful degradation:

**Level 1: Component Failure**
- If Qwen fails → Use cached response or rule-based
- If HuBERT fails → Skip pronunciation
- If LLaMA3-VI fails → Use English only

**Level 2: Timeout Management**
- Task timeout: 500ms per component
- Total timeout: 2s for full pipeline
- If timeout → Return partial results

**Level 3: Resource Exhaustion**
- GPU OOM → Offload to CPU
- CPU overload → Queue request, return cached

## 📈 Performance Metrics

Track and monitor:
- Latency per component
- Resource usage (GPU%, RAM)
- Error rates by component
- Cache hit rates

```dart
// Get metrics
final metrics = orchestrator.performanceMetrics;
print(metrics);

// Check loaded models
final loaded = orchestrator.loadedModels;
print('Loaded: $loaded');
```

## 🔧 TODO: Integration Checklist

- [ ] Replace MockSTTService with real Faster-Whisper integration
- [ ] Replace MockTTSService with real Piper VITS integration
- [ ] Replace MockPronunciationService with real HuBERT integration
- [ ] Integrate Qwen2.5-1.5B + Unified LoRA adapter
- [ ] Integrate LLaMA3-8B-VI for Vietnamese explanations
- [ ] Integrate all-MiniLM-L6-v2 for context embeddings
- [ ] Setup Redis cache for learner profiles
- [ ] Integrate Knowledge Graph (NetworkX / KuzuDB)
- [ ] Add comprehensive unit tests
- [ ] Add integration tests
- [ ] Performance benchmarking
- [ ] Add monitoring and logging

## 📝 Notes

**Current Status:**
- Complete architecture skeleton implemented
- All core interfaces defined
- Mock implementations for testing
- ⏳ Waiting for actual AI model integrations

**Mock Services:**
All services currently use mock implementations that simulate the behavior and latency of real models. These should be replaced with actual model integrations for production.

**Design Principles:**
- Hybrid Models: Qwen (English) + LLaMA3 (Vietnamese)
- Unified Adapter: 1 adapter for 4 tasks
- Lazy Loading: Load models only when needed
- Parallel Processing: Grammar + Pronunciation simultaneously
- Caching: Common responses, learner profiles
- Fallback: Graceful degradation on errors

## 🔗 Related Documentation

- [Architecture Document](/docs/architecture.md) - Full AI architecture v2.0
- [Phase 1 Completion](/docs/phase1_ui_completion.md) - UI implementation status
- [Tasks](/docs/tasks.md) - Development tasks and timeline

---

**Author:** Nguyen Huu Thang  
**Version:** 1.0  
**Last Updated:** January 2026
