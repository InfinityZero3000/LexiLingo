# Kế Hoạch Triển Khai Module AI Chat - LexiLingo v2.0

> **Tài liệu**: Danh sách nhiệm vụ chi tiết để hiện thực hóa kiến trúc AI Chat  
> **Kiến trúc**: Clean Architecture + Modular Feature-First  
> **Core Engine**: Flutter App (Phase 1) → Python AI Orchestrator (Phase 2)  
> **Trạng thái**: ⬜ Chưa bắt đầu | Hoàn thành | 🚧 Đang thực hiện  
> **Last Updated**: January 15, 2026

---

## 📊 Tổng Quan Tiến Độ

### Đã Hoàn Thành
- **Chat Feature cơ bản với Google Gemini AI**
  - Clean Architecture implementation
  - Domain Layer: Entities, Repositories, UseCases
  - Data Layer: Models, DataSources (Remote + Local Web)
  - Presentation Layer: ChatProvider, ChatPage UI
  - API Key security với flutter_dotenv
  - Web storage với SharedPreferences

### 🚧 Đang Thực Hiện
- Testing và tối ưu Chat UI
- Voice input/output integration

### 📋 Kế Hoạch Tiếp Theo
- Advanced AI features (Pronunciation, Grammar analysis)
- Python AI Orchestrator backend
- LoRA fine-tuning cho specialized tasks

---

## Phase 0: Flutter Chat MVP (Current Implementation) ✅

**Mục tiêu**: Xây dựng chat feature cơ bản với Google Gemini AI, cho phép user chat và nhận feedback

### 0.1 Infrastructure Setup ✅
- [x] **Environment Configuration**
    - [x] Setup flutter_dotenv cho API key management
    - [x] Tạo .env file với GEMINI_API_KEY và HF_API_KEY
    - [x] Gitignore .env để bảo mật API keys
    - [x] Configure Firebase cho authentication
- [x] **Dependency Injection (GetIt)** 
    - [x] Setup injection_container.dart
    - [x] Register SharedPreferences cho web platform
    - [x] Conditional registration (skipDatabase cho web)

### 0.2 Domain Layer ✅
- [x] **Entities**
    - [x] `ChatMessage`: id, sessionId, content, role, timestamp, status
    - [x] `ChatSession`: id, userId, title, createdAt, lastMessageAt
    - [x] Enums: MessageRole, MessageStatus, AIModel
- [x] **Repositories (Abstract)**
    - [x] `ChatRepository`: interface với methods sendMessage, getAIResponse, createSession, getSessions, getMessages
- [x] **UseCases**
    - [x] `CreateSessionUseCase`: Tạo chat session mới
    - [x] `GetSessionsUseCase`: Lấy danh sách sessions
    - [x] `GetChatHistoryUseCase`: Lấy lịch sử chat của session
    - [x] `SendMessageUseCase`: Gửi message và nhận AI response

### 0.3 Data Layer ✅
- [x] **Models**
    - [x] `ChatMessageModel`: extends Entity, có fromJson/toJson, toMap/fromMap
    - [x] `ChatSessionModel`: extends Entity, có fromJson/toJson, toMap/fromMap
- [x] **Data Sources**
    - [x] `ChatRemoteDataSource`: Integration với Google Gemini API
        - [x] Method sendMessage(String message)
        - [x] Method getAIResponse với conversation history support
        - [x] Error handling và exceptions
    - [x] `ChatLocalDataSource`: Abstract interface cho local storage
        - [x] SQLite implementation cho mobile (`ChatLocalDataSourceImpl`)
        - [x] SharedPreferences implementation cho web (`ChatLocalDataSourceWeb`)
    - [x] `NetworkInfo`: Interface và implementation để check network status
- [x] **Repositories (Implementation)**
    - [x] `ChatRepositoryImpl`: 
        - [x] Kết hợp local + remote data sources
        - [x] Network check logic
        - [x] Error handling với Either<Failure, T> pattern
        - [x] Conversation context management

### 0.4 Presentation Layer ✅
- [x] **State Management**
    - [x] `ChatProvider`: Quản lý chat state với ChangeNotifier
        - [x] Sessions list management
        - [x] Messages list management
        - [x] Loading states
        - [x] Error handling
        - [x] Send message flow
        - [x] Create session flow
- [x] **UI Components**
    - [x] `ChatPage`: Main chat screen
    - [x] Basic message display
    - [x] Input field và send button
    - [x] Session management UI

### 0.5 Integration & Deployment ✅
- [x] **Dependency Registration**
    - [x] Register tất cả dependencies trong injection_container
    - [x] Platform-specific implementations (web vs mobile)
- [x] **Provider Setup**
    - [x] Add ChatProvider vào MultiProvider trong main.dart
- [x] **Web Testing**
    - [x] Test app trên Chrome
    - [x] Verify API connection với Gemini
    - [x] Test SharedPreferences storage

---

## Phase 1: Chat UI Enhancement & Voice Features 🚧

**Mục tiêu**: Cải thiện UI/UX và thêm voice input/output

### 1.1 UI Improvements ✅
- [x] **Enhanced Chat Interface**
    - [x] `MessageBubble`: Widget với styling cho User vs AI messages
    - [x] Avatar icons cho User và AI
    - [x] Timestamp display cho mỗi message
    - [x] Markdown rendering cho AI responses
    - [x] Copy message content feature
    - [x] Message status indicators (sending, sent, error)
- [x] **Session Management UI**
    - [x] Session list sidebar/drawer
    - [x] Create new session button
    - [x] Delete session action (UI ready, backend pending)
    - [x] Rename session dialog (UI ready, backend pending)
    - [ ] Search sessions
- [ ] **Responsive Design**
    - [ ] Mobile layout optimization
    - [ ] Tablet layout
    - [ ] Desktop layout với sidebar
    - [ ] Dark mode support (partial - colors implemented)

### 1.2 Voice Input (Basic STT)
- [ ] **Audio Recording**
    - [ ] `AudioRecorderButton`: Widget với recording animation
    - [ ] Permission handling (microphone)
    - [ ] Audio file recording và storage
- [ ] **Speech-to-Text Integration**
    - [ ] Integrate với Google Cloud Speech-to-Text API (hoặc Web Speech API cho web)
    - [ ] Display transcribed text in input field
    - [ ] Error handling cho STT failures

### 1.3 Voice Output (Basic TTS)
- [ ] **Text-to-Speech**
    - [ ] Play button trên AI messages
    - [ ] Integrate với Flutter TTS package
    - [ ] Playback controls (pause, stop)
    - [ ] Audio streaming cho long responses

---

## Phase 2: Advanced AI Features & Analysis

**Mục tiêu**: Thêm grammar correction, pronunciation analysis, và feedback chi tiết

### 2.1 Grammar & Fluency Analysis
- [ ] **Enhanced AI Prompting**
    - [ ] Update system prompts để request structured feedback
    - [ ] Parse JSON response từ Gemini với grammar errors
    - [ ] Display grammar corrections trong UI
- [ ] **Feedback Widget**
    - [ ] `FeedbackCard`: Widget hiển thị analysis results
    - [ ] Grammar error highlights
    - [ ] Fluency score visualization
    - [ ] Vocabulary level indicator
    - [ ] Suggestions panel

### 2.2 Pronunciation Analysis (Future)
- [ ] **Pronunciation Model Integration**
    - [ ] Research pronunciation analysis APIs
    - [ ] Integrate với pronunciation service
    - [ ] Phoneme comparison logic
- [ ] **Pronunciation Feedback UI**
    - [ ] `PronunciationView`: Popup với phoneme-level feedback
    - [ ] Visual waveform display
    - [ ] Highlight incorrect phonemes
    - [ ] Play reference audio
    - [ ] Practice mode

### 2.3 Knowledge Graph & RAG System
- [ ] **Knowledge Graph Construction**
    - [ ] Design schema cho nodes: Vocab (Word), Grammar (Rule), Topic (Concept)
    - [ ] Design relationships: "is_a", "related_to", "prerequisite_of", "difficulty_level"
    - [ ] Select technology: NetworkX (lightweight) vs KuzuDB (production-ready)
    - [ ] Create base vocabulary graph (CEFR A2-B2 ~3000 words)
    - [ ] Create grammar rules graph (~100 common rules)
    - [ ] Create topic/concept graph (daily life, work, travel, etc.)
- [ ] **Graph Population**
    - [ ] Script để import vocabulary từ CEFR wordlists
    - [ ] Parse grammar rules từ textbooks/resources
    - [ ] Build relationships automatically (word frequency, co-occurrence)
    - [ ] Add metadata: difficulty_level, example_sentences, usage_frequency
- [ ] **Graph RAG Integration**
    - [ ] Query engine cho semantic search
    - [ ] Context retrieval based on user level
    - [ ] Related concepts suggestion
    - [ ] Prerequisite checking for curriculum planning
- [ ] **Curriculum Planning System**
    - [ ] Use graph để suggest next learning topics
    - [ ] Adaptive difficulty based on user progress
    - [ ] Spaced repetition scheduling với graph metadata

### 2.4 Progress Tracking
- [ ] **Learning Analytics**
    - [ ] Track user mistakes over time
    - [ ] Common error patterns
    - [ ] Progress visualization (charts)
    - [ ] Vocabulary growth tracking
- [ ] **Personalization**
    - [ ] User level detection (A2, B1, B2)
    - [ ] Adaptive difficulty
    - [ ] Personalized recommendations

---

## Phase 3: Python AI Orchestrator Backend (Future Enhancement)

**Mục tiêu**: Xây dựng backend AI chuyên biệt với LoRA fine-tuning

### 3.0 MongoDB Integration for AI Learning Loop ✅

**Completed**: January 15, 2026

- [x] **MongoDB Setup**
  - [x] Create `docker-compose.yml` với MongoDB + Redis + Mongo Express
  - [x] Create `scripts/mongo-init.js` với collections & indexes
  - [x] Create `config/mongodb_config.yaml` với dev/prod environments
  - [x] Environment-aware configuration (Local Docker vs Atlas)
  
- [x] **MongoDB Client Implementation**
  - [x] `model/mongodb_client.py`: Singleton client với auto-detection
  - [x] Methods: log_interaction, get_user_interactions, log_model_metrics
  - [x] Connection pooling và retry logic
  - [x] TTL indexes cho auto-cleanup (90 days)
  
- [x] **Logging Middleware**
  - [x] `model/logging_middleware.py`: Automatic logging decorator
  - [x] MetricsCollector cho performance tracking
  - [x] Non-blocking async logging
  
- [x] **Collections Schema**
  - [x] ai_interactions: Full interaction logs + feedback loop
  - [x] model_metrics: Performance tracking over time
  - [x] learning_patterns: Aggregated user error patterns
  - [x] training_queue: Curated examples for LoRA fine-tuning
  
- [x] **Documentation**
  - [x] `docs/MONGODB_ATLAS_SETUP.md`: Step-by-step Atlas setup
  - [x] `docs/MONGODB_SCHEMA.md`: Collections schema reference
  - [x] Update `architecture.md` with MongoDB layer

**Usage**:
```bash
# Start local MongoDB
cd DL-Model-Support
docker-compose up -d

# Test connection
python model/mongodb_client.py

# Access Mongo Express UI
open http://localhost:8081
```

### 3.1 Môi Trường & Dataset Chuẩn Bị

### 3.1 Môi Trường & Dataset Chuẩn Bị
- [ ] **Setup Python Environment**
    - [ ] Tạo Virtual Environment (`venv` hoặc `conda`) với Python 3.10+
    - [ ] Cài đặt các thư viện core: `torch`, `transformers`, `peft`, `bitsandbytes`, `huggingface_hub`
    - [ ] Cài đặt thư viện xử lý audio: `librosa`, `soundfile`, `faster-whisper`
    - [ ] Cài đặt thư viện graph: `networkx`, `kuzu` (hoặc `neo4j`)
    - [ ] Cài đặt server framework: `fastapi`, `uvicorn`, `redis`
    - [ ] Cài đặt NLP utilities: `sentence-transformers`, `spacy`
    - [ ] Tạo file `requirements.txt` cập nhật đầy đủ version
- [ ] **Model Selection & Download**
    - [ ] **STT**: Download Whisper-small (244MB) via faster-whisper
      ```python
      # Recommended: Whisper-small (WER <10% for ESL)
      from faster_whisper import WhisperModel
      model = WhisperModel("small", device="cpu", compute_type="int8")
      # Alternative: "medium" (769MB, WER <7%) nếu cần accuracy cao hơn
      ```
    - [ ] **NLP**: Download Qwen2.5-1.5B-Instruct (~1.5GB)
      ```python
      # Recommended cho MVP: Balance speed/quality
      from transformers import AutoModelForCausalLM
      model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen2.5-1.5B-Instruct")
      # Alternative: Qwen2.5-3B-Instruct (3GB) nếu có GPU mạnh
      ```
    - [ ] **Vietnamese**: Download LLaMA3-8B-VI (8GB) với 4-bit quantization
    - [ ] **Context Encoder**: Download all-MiniLM-L6-v2 (22MB)
    - [ ] **Pronunciation**: Download HuBERT-large (960MB) - optional cho phase sau
- [ ] **Dataset Collection & Processing**
    - [ ] Tải EFCAMDAT dataset (Fluency scoring)
    - [ ] Tải BEA-2019 / CoNLL-2014 dataset (Grammar correction)
    - [ ] Tải AutoTutor Dialogue Corpus (Pedagogical strategy)
    - [ ] Tải Oxford Graded Readers / CEFR corpus (Vocabulary leveling)
    - [ ] Download CEFR vocabulary lists (A2, B1, B2) - ~3000 words
    - [ ] Download grammar rule collections (Cambridge, Oxford)
    - [ ] Viết script `processing/data_cleaner.py` để chuẩn hóa định dạng dữ liệu về JSONL instruction format
    - [ ] Chia split Train/Validation/Test (80/10/10)
- [ ] **Knowledge Graph Initial Data**
    - [ ] Prepare vocabulary nodes CSV (word, level, pos, definition, examples)
    - [ ] Prepare grammar nodes CSV (rule_id, name, level, description, examples)
    - [ ] Prepare topic nodes CSV (topic_id, name, related_vocab, related_grammar)
    - [ ] Prepare relationships CSV (source, target, relationship_type, weight)

### 3.2 Model Base & Fine-tuning (LoRA)
- [ ] **Qwen2.5-1.5B Base Setup**
    - [ ] Tải model `Qwen/Qwen2.5-1.5B-Instruct`
    - [ ] Viết script lượng tử hóa (Quantization) về 4-bit (BNB4) để tiết kiệm RAM
- [ ] **Unified Adapter Training**
    - [ ] Cấu hình LoRA config (rank=48, alpha=96, modules=[all linear])
    - [ ] Viết training script `train_unified.py` sử dụng thư viện `peft`
    - [ ] Định nghĩa Prompt Template cho Multi-tasking (Fluency, Grammar, Vocab, Dialogue)
    - [ ] Train Unified Adapter trên dataset tổng hợp (~16.7k samples)
    - [ ] Export Adapter (`adapter_model.bin`) và `adapter_config.json`
- [ ] **Model Evaluation**
    - [ ] Viết script `eval_fluency.py` (Tính MAE, Pearson correlation)
    - [ ] Viết script `eval_grammar.py` (Tính F0.5 score, Precision/Recall)
    - [ ] Chạy benchmark so sánh performance với baseline

### 3.3 Audio Models Setup
- [ ] **STT Module (Whisper)**
    - [ ] Setup `faster-whisper` với model `small` hoặc `distil-small.en`
    - [ ] Tối ưu hóa với CTranslate2 để chạy trên CPU/Mobile
    - [ ] Implement VAD (Voice Activity Detection) với Silero VAD để lọc khoảng lặng
- [ ] **Pronunciation Module (HuBERT)**
    - [ ] Tải model `facebook/hubert-large-ls960`
    - [ ] Implement thuật toán DTW (Dynamic Time Warping) để so khớp phoneme
    - [ ] Xây dựng hàm tính điểm phát âm (Phone-level accuracy map)
- [ ] **TTS Module (Piper)**
    - [ ] Compile Piper TTS engine
    - [ ] Tải voice model `en_US-lessac-medium`
    - [ ] Test latency sinh audio

---

---

    - [ ] Implement conversation embedding aggregation
- [ ] **Knowledge Graph Manager**
    - [ ] Class `KnowledgeGraphManager` để quản lý graph
    - [ ] Load graph vào memory (NetworkX) hoặc connect to DB (KuzuDB)
    - [ ] Method `query_related_concepts(word, max_depth=2)` để RAG
    - [ ] Method `get_prerequisites(topic)` cho curriculum planning
    - [ ] Method `suggest_next_topics(user_progress, current_level)`
    - [ ] Cache frequently accessed subgraphs trong Redis
- [ ] **Resource Manager**
    - [ ] Implement Singleton Pattern cho Model Loading
    - [ ] Xây dựng cơ chế Lazy Loading cho LLaMA3-VI (chỉ load khi cần tiếng Việt)
    - [ ] Xây dựng cơ chế Offloading (chuyển model từ GPU về CPU khi RAM đầy)
    - [ ] Memory monitoring và auto-cleanup
### 4.1 Core Components Implementation
- [ ] **Context Manager**
    - [ ] Sử dụng `all-MiniLM-L6-v2` để encode ngữ cảnh hội thoại
    - [ ] Xây dựng Sliding Window Buffer (giữ context của 5 turn gần nhất)
    - [ ] Tích hợp Redis để lưu/đọc `user_level`, `learning_history`
    - [ ] Integrate với Knowledge Graph để query related concepts
    - [ ] Complexity assessment based on vocabulary level
- [ ] **Pipeline Execution**
    - [ ] Xây dựng class `AIOrchestrator` chính
    - [ ] Implement `async` flow để chạy song song Qwen và HuBERT
    - [ ] Implement Knowledge Graph RAG trong pipeline
    - [ ] Xây dựng cơ chế Error Handling & Fallback (như thiết kế trong architecture.md)
    - [ ] Implement logic Fusion & Aggregation để gộp kết quả từ các model
- [ ] **Feedback Strategy Engine**
    - [ ] Implement 4 strategies: PRAISE, CORRECT, EXPLAIN, DRILL
    - [ ] Level adaptation logic (A2/B1/B2)
    - [ ] Response length controller
    - [ ] Vietnamese hint generator (conditional)
### 2.2 Orchestrator Logic
- [ ] **Task Analyzer**
    - [ ] Viết logic phân tích intent người dùng (Hỏi ngữ pháp? Chat vu vơ? Luyện tập?)
    - [ ] Logic xác định chiến lược dạy (Socratic, Scaffolding, Feedback) dựa trên lịch sử lỗi
    - [ ] Request model: message, session_id, user_level, context
    - [ ] Response model: analysis, response_en, response_vi, scores, next_action
- [ ] Thiết kế API Endpoint: `POST /v1/audio/transcriptions` (STT)
- [ ] Thiết kế API Endpoint: `POST /v1/audio/speech` (TTS)
- [ ] Thiết kế API Endpoint: `GET /v1/knowledge/concepts/{concept_id}`
    - [ ] Query related concepts từ Knowledge Graph
- [ ] Thiết kế API Endpoint: `GET /v1/curriculum/suggest`
    - [ ] Suggest next topics based on user progress
- [ ] Middleware: Rate limiting, Authentication, Logging Request/Response
- [ ] WebSocket support cho streaming responses
    - [ ] Xây dựng cơ chế Error Handling & Fallback (như thiết kế trong architecture.md)
    4 [ ] Implement logic Fusion & Aggregation để gộp kết quả từ các model

### 2.3 API Gateway (FastAPI)
- [ ] Thiết kế API Endpoint: `POST /v1/chat/completions`
- [ ] Thiết kế API Endpoint: `POST /v1/audio/transcriptions` (STT)
- [ ] Thiết kế API Endpoint: `POST /v1/audio/speech` (TTS)
- [ ] Middleware: Rate limiting, Authentication, Logging Request/Response

---

## Phase 5: Backend Integration với Flutter App

**Mục tiêu**: Migrate từ Gemini API sang custom AI Orchestrator backend

### 5.1 Backend API Client
- [ ] **API Client Implementation**
    - [ ] Tạo `OrchestratorAPIClient` class
    - [ ] Implement endpoints: `/v1/chat/completions`, `/v1/audio/transcriptions`, `/v1/audio/speech`
    - [ ] Authentication và headers
- [ ] **Knowledge Graph Features**
    - [ ] Vocabulary level indicator cho từng message
    - [ ] Related concepts suggestion panel
    - [ ] Learning path visualization
    - [ ] Prerequisite checker trước khi học topic mới

---

## Phase 7: Knowledge Graph & Curriculum System (Future)

**Mục tiêu**: Xây dựng hệ thống Knowledge Graph và curriculum planning thông minh

### 7.1 Knowledge Graph Development
- [ ] **Graph Schema Design**
    - [ ] Design node types: VocabNode, GrammarNode, TopicNode, LevelNode
    - [ ] Design edge types và properties
    - [ ] Define metadata schema
- [ ] **Graph Database Setup**
    - [ ] Choose between NetworkX (simple) và KuzuDB/Neo4j (scalable)
    - [ ] Setup database connection
    - [ ] Create indexes cho fast queries
- [ ] **Data Population Pipeline**
    - [ ] Import CEFR vocabulary (~3000 words)
    - [ ] Import grammar rules (~100 rules)
    - [ ] Import topics và concepts
    - [ ] Build relationships automatically
    - [ ] Validate graph consistency

### 7.2 RAG Integration
- [ ] **Semantic Search**
    - [ ] Implement vector similarity search trong graph
    - [ ] Context-aware concept retrieval
    - [ ] Multi-hop reasoning (traverse graph)
- [ ] **Query Optimization**
    - [ ] Cache frequent queries
    - [ ] Optimize graph traversal algorithms
    - [ ] Batch queries cho performance

### 7.3 Curriculum Planning
- [ ] **Adaptive Learning Path**
    - [ ] Algorithm để suggest next topics
    - [ ] Difficulty progression based on user level
    - [ ] Prerequisite checking
    - [ ] Spaced repetition scheduling
- [ ] **Progress Tracking**
    - [ ] Track mastered concepts trong graph
    - [ ] Update edge weights based on user performance
    - [ ] Generate learning reports
- [ ] **Personalization**
    - [ ] Build user knowledge graph (subgraph of main graph)
    - [ ] Identify knowledge gaps
    - [ ] Recommend targeted practice
    - [ ] Request/Response models cho Orchestrator API
- [ ] **Data Source Updates**
    - [ ] Update `ChatRemoteDataSource` để support cả Gemini và Orchestrator
    - [ ] Feature flag để switch giữa 2 backends
    - [ ] Graceful fallback nếu Orchestrator unavailable

### 5.2 Advanced Features Integration
- [ ] **Analysis Results**
    - [ ] Parse structured response từ Orchestrator (fluency, grammar, vocab)
    - [ ] Update ChatMessage entity để lưu analysis data
    - [ ] Display detailed feedback trong UI
- [ ] **Pronunciation Data**
    - [ ] Receive pronunciation analysis từ backend
    - [ ] Store audio files và phoneme data
    - [ ] Render pronunciation feedback UI
    - [ ] `AudioRecorderButton`: Nút ghi âm với animation sóng
    - [ ] `PronunciationView`: Popup hiển thị chi tiết lỗi phát âm (tô đỏ phoneme sai)

---

## Phase 4: Testing & Optimization

### 4.1 Unit Testing
- [ ] **Backend Tests (`pytest`)**
   

### Phase 7: Knowledge Graph & Curriculum ⬜ (0%)
```
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0%
``` - [ ] Test Orchestrator logic (Mock model outputs)
    - [ ] Test LoRA Adapter outputs (Input sample -> Output structure check)
    - [ ] Test API endpoints (Input validation, Response format)
- [ ] **Mobile Tests (`flutter_test`)**
    - [ ] Test Domain UseCases
---

## Phase 6: Testing & Optimization

### 6
### 4.2 Integration Testing
- [ ] Test flow trọn vẹn: User Voice Input -> STT -> Orchestrator -> Response -> TTS -> Mobile Audio Playback
- [ ] Kiểm tra độ trễ (Latency) toàn trình. Target: < 2s cho câu trả lời đầu tiên.

### 4.3 Deployment
- [ ] Đóng gói Docker cho AI Backend Service
- [ ] Setup CI/CD Pipeline (GitHub Actions)
- [ ] Build Flutter App (release mode) cho Android/iOS

---6

## Checklists Theo Dõi

### 6.3 Performance Optimization
- [ ] **Mobile Optimization**
    - [ ] Optimize image loading và caching
    - [ ] Lazy loading 

### Sprint 4 (Future) - Knowledge Graph Foundation
- [ ] Design Knowledge Graph schema
- [ ] Collect and prepare graph data (vocabulary, grammar, topics)
- [ ] Setup graph database (NetworkX/KuzuDB)
- [ ] Implement basic RAG queries
- [ ] Build curriculum suggestion APIcho message history
    - [ ] Memory leak detection
    - [ ] Battery usage optimization
- [ ] **Network Optimization**
---

## 📊 Progress Dashboard

### Phase 0: Flutter Chat MVP (100%)
```
████████████████████████████████████████ 100%
```
- Domain Layer: Complete

4. **Knowledge Graph Technology**:
   - 🎯 MVP: NetworkX (Python, lightweight, in-memory)
     - Easy to prototype
     - Fast for small graphs (<10k nodes)
     - ⚠️ Limited scalability
   - 📋 Production: KuzuDB hoặc Neo4j
     - Optimized for graph queries
     - Persistent storage
     - Better performance at scale

5. **RAG Strategy**:
   - Hybrid approach: Vector similarity + Graph traversal
   - Use sentence embeddings (MiniLM) cho semantic search
   - Use graph edges cho prerequisite/related concept queries
- Data Layer: Complete  
- Presentation Layer: Complete
- Integration: Complete

### Phase 1: Chat UI Enhancement 🚧 (70%)
```
████████████████████████████░░░░░░░░░░░░ 70%
```
- UI Improvements: Complete (90% - search sessions pending)
- Voice Input: ⬜ Not Started
- Voice Output: ⬜ Not Started

### Phase 2: Advanced AI Features ⬜ (0%)
```
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0%
```

### Phase 3-6: Backend & Integration ⬜ (0%)
```
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0%
```

---

## 🎯 Current Sprint Goals

### Sprint 1 (Current) - Chat MVP Completion ✅
- [x] Setup secure API key management
- [x] Implement Clean Architecture cho Chat feature
- [x] Create basic Chat UI
- [x] Test Gemini AI integration
- [x] Deploy to web (Chrome testing)

### Sprint 2 (Next) - UI Enhancement ✅
- [x] Improve message bubble styling
- [x] Add session management UI
- [x] Implement markdown rendering
- [ ] Add dark mode support (partial)
- [ ] Mobile responsive design
- [ ] Voice features integration (moved to Sprint 3)

### Sprint 3 (Future) - Voice Features
- [ ] Integrate Speech-to-Text
- [ ] Knowledge Graph not built yet (needed for advanced features)

### Performance Metrics (Target)
- Initial load: < 2s
- Message send to response: < 3s (Gemini) / < 2s (Orchestrator)
- UI responsiveness: 60 FPS
- Memory usage: < 150MB (mobile)
- Knowledge Graph query: < 5ms (cached) / < 50ms (cold)
- RAG retrieval: < 100ms

### Data Requirements
- Vocabulary: ~3000 words (CEFR A2-B2)
- Grammar rules: ~100 common rules
- Topics: ~50 conversation topics
- Example sentences: ~10k sentences
- Graph edges: ~15k relationships
## 📝 Notes & Decisions

### Technical Decisions
1. **API Choice**: Started với Google Gemini API cho MVP speed
   - Pros: Quick setup, no training needed, good quality
   - ⚠️ Cons: Vendor lock-in, limited customization
   - 📋 Plan: Migrate to custom Orchestrator khi cần specialized features

2. **Model Selection**:
   - **STT (Speech-to-Text)**: Whisper-small (medium-whisper)
     - 244MB, WER <10% for ESL learners
     - Excellent Vietnamese accent support
     - Word-level timestamps cho pronunciation analysis
     - 📋 Upgrade to "medium" (769MB) nếu cần WER <7%
   
   - **NLP**: Qwen2.5-1.5B-Instruct
     - 1.5GB, latency 100-150ms
     - Sufficient cho grammar/fluency/vocab tasks
     - Can run on 8GB RAM laptop
     - 📋 Consider 3B version (3GB, +5-10% accuracy) khi có GPU server

3. **Storage Strategy**: 
   - Mobile: SQLite via DatabaseHelper
   - Web: SharedPreferences
   - 📋 Future: Sync với Firebase/Firestore

4. **State Management**: Provider pattern
   - Simple, official, suitable cho app size
   - 📋 Consider Riverpod khi app grows

### Known Issues
- [ ] Chat page session list not implemented yet
- [ ] No error retry mechanism in UI
- [ ] Missing loading indicators for long responses

### Performance Metrics (Target)
- Initial load: < 2s
- Message send to response: < 3s (Gemini)
- UI responsiveness: 60 FPS
- Memory usage: < 150MB (mobile)

---

**Last Updated**: January 15, 2026  
**Next Review**: After Sprint 2 completion  
**Ghi chú**: Luôn cập nhật file này sau mỗi sprint/milestone hoàn thành

---
**Ghi chú**: Thực hiện tuần tự theo các Phase. Luôn cập nhật trạng thái vào file này sau mỗi phiên làm việc.
