# Khảo sát kiến trúc hệ thống hiện tại — chuẩn bị cho mission-based course

> Đi kèm `docs/course_learning_methodology.md`. Đây là kết quả khảo sát thực tế codebase (không phải đề xuất) — dùng làm nền cho implementation plan.

## 1. FSRS/SRS — có 2 engine song song, chưa hợp nhất

| Hệ thống | Vị trí | Thuật toán | Wire tới user chưa? |
|---|---|---|---|
| **Vocabulary SRS** | `UserVocabulary` model (`vocabulary.py:155-181`), `calculate_next_review()` + `calculate_fsrs_review()` (`crud/vocabulary.py:449-585`) | SM-2 chuẩn **và** một FSRS-lai tự viết, lưu song song 2 bộ field | ✅ Đầy đủ: `GET /vocabulary/due`, `POST /vocabulary/review/{id}`, Flutter flashcard/quiz screen dùng thật |
| **Learner Concept State** | `learner_concept_states` (`models/learner_state.py`), `evolve_state()` (`services/learner_state.py:84-156`) | BKT + FSRS hybrid **bài bản hơn** — tổng quát hoá theo `concept_id` (không chỉ từ vựng), có `next_review_at`, `mastery_probability`, `algorithm_version="bkt-fsrs-v1"` | ❌ Chỉ dùng nội bộ để cá nhân hoá retrieval cho TRACE-CAG (ai-service), **không có endpoint "due today"**, Flutter không hề gọi tới |
| **Mistake Notebook** | `mistake_notebook_entries` (`models/mistake.py`) | Không có — chỉ cờ open/reviewed | ✅ Wired nhưng chỉ là bug-tracker câu sai, không phải bộ nhớ đệm ôn tập |

**Ý nghĩa cho plan:** `learner_concept_state` là engine tốt hơn về mặt lý thuyết (khớp đúng nghiên cứu HLR/FSRS ở mục 2.5 methodology doc, tổng quát cho cả ngữ pháp/mission chứ không riêng từ vựng) nhưng đang "chết" — không ai gọi tới ngoài TRACE-CAG. Đây là quyết định kiến trúc cần chốt trước khi làm review cho mission: **mở rộng engine này thành nguồn "due for review" chính** (concept = từ vựng + ngữ pháp + mission-skill), hay tiếp tục dùng riêng SM-2 cho vocab.

## 2. Kho exercise — đa dạng hơn dự đoán ban đầu

20 loại widget thật trong Flutter (`premium_exercise_widgets.dart`), backend có `QuestionType` enum riêng (MC/TrueFalse/FillBlank/Matching/Listening/Speaking/Translation) nhưng Flutter dùng `ui_type` chi tiết hơn:

- **Recognition (10 loại):** TrueOrFalse, MultipleChoice, TranslationChoice, CollocationChoice, ImageBasedChoice, ListeningChoice, MatchWordMeaning, ReadingComprehension, ArrangeSentence, Categorization.
- **Production (7 loại):** FillBlank, Dictation, GrammarCorrection, ShortWritingAnswer, DialogueCompletion, **SpeakingRepeat**, **PronunciationPractice** (2 loại cuối dùng mic thật).

→ Kết luận quan trọng: **kho widget đã đủ để làm task cycle đa dạng** (không cần build thêm loại bài mới cho hầu hết trường hợp) — vấn đề nằm ở việc **content hiện có (seed/generate) có thực sự dùng đa dạng này không**, và ở **cách sắp xếp theo pha TBLT** (pre-task/task-cycle/language-focus), chứ không phải thiếu công cụ.

**Giới hạn thật sự:**
- Không có model "Story"/hội thoại nhiều lượt — `DialogueCompletionWidget` chỉ là fill-blank style hội thoại 1 câu, không phải task nhiều bước.
- "Listening" exercise dùng TTS client-side (`audio_url` luôn null, xác nhận tại `games.py:1145`), không phải audio thu âm thật.
- Chấm điểm speaking dùng Levenshtein text-similarity (`learning.py:767-820`, ngưỡng 0.85), **không dùng** điểm HuBERT pronunciation thật — dù hạ tầng HuBERT đã có sẵn và đang chấm điểm tốt cho flow ôn từ vựng riêng (`/vocabulary/pronunciation/evaluate`).

## 3. Admin course-creation flow — đã khá đầy đủ, chỉ thiếu field mission

- UI lồng nhau thật: Course → Units → Lessons → Exercises, tất cả CRUD wired vào Postgres qua `admin_courses.py`.
- Form Course hiện có: title, description, language, level, tags, thumbnail_url, is_published. **Không có field mission/outcome/objective.**
- Nút "Generate with agent" (Sparkles) → tạo job → `ContentQaQueuePage` duyệt → "Approve & publish" ghi thật vào Course/Unit/Lesson/VocabularyItem + `ContentProvenance` audit trail. Đây là pipeline người-trong-vòng-lặp đã hoạt động, chỉ thiếu bước **edit tại chỗ** trước khi publish.
- `content_agent` (ai-service) hoàn toàn deterministic — `planner.py` chỉ phân bổ từ vựng tuần hoàn theo unit/lesson, `generator.py` sinh nội dung bằng f-string template cố định + catalog ~10 exercise template, **không có lời gọi LLM nào** trong toàn bộ package.
- Hệ thống license/provenance (`policies.py`) cho dataset ngoài (OEWN, CMUdict, CEFR-J, Wikidata, Tatoeba, LibriSpeech, Common Voice) đã khá tốt, tái dùng được cho pipeline mission-based.

## 4. Kết nối với 8 nguyên tắc trong methodology doc

| Nguyên tắc (methodology §5) | Trạng thái hệ thống |
|---|---|
| 1. Mission làm đơn vị tổ chức | Chưa có field outcome/mission — cần thêm |
| 2. Cấu trúc 3 pha TBLT | Lesson.content là mảng exercise phẳng, chưa có khái niệm pha |
| 3. ≥1 production exercise/mission | Widget đã có sẵn, cần validation rule khi generate/duyệt |
| 4. Độ khó thích ứng per-learner | Chưa xác nhận có Birdbrain-tương-đương — cần khảo sát riêng (ranking_agent_insights?) |
| 5. Ôn tập theo forgetting-curve cá nhân hoá | Đã có 2 engine (mục 1) nhưng phân mảnh, engine tốt hơn (`learner_concept_state`) chưa lộ ra user |
| 6. Phản hồi lỗi không phạt nặng giữa chừng | Chưa khảo sát (thuộc UX/gamification hearts — vấn đề product, không chỉ backend) |
| 7. Chọn mission theo sở thích (autonomy) | Chưa có — phụ thuộc field mission (#1) |
| 8. Sinh nội dung AI theo mission-prompt | content_agent chưa có LLM, cần thêm; QA queue thiếu bước edit |
