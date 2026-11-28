# Chuẩn nội dung khoá học LexiLingo

Tài liệu này ghi **những gì code thực sự kiểm tra** khi một khoá học, unit, lesson
hay bài tập được tạo — dù do AI sinh hay soạn tay — cùng nguồn dữ liệu, giấy phép
và khung chuẩn mà nội dung dựa vào. Cơ sở sư phạm (vì sao lesson phải có bài sản
sinh ngôn ngữ, can-do, ôn tập giãn cách…) nằm ở
[course_learning_methodology.md](course_learning_methodology.md).

Quy ước: **Bắt buộc** = code từ chối (422/409/lỗi chặn). **Cảnh báo** = hiện cho
admin nhưng không chặn. **Báo cáo** = chỉ đo và in ra.

---

## 1. Khung khoá học

```
Course ── level (A1–C2), skill, is_published
  └─ Unit ── order_index
       └─ Lesson ── title, skill, outcome (can-do), content.exercises[]
            └─ Exercise ── id, type, ui_type, question, options, correct_answer, explanation
```

| Thành phần | Quy định | Mức |
|---|---|---|
| Course.level | Một trong A1, A2, B1, B2, C1, C2 (CEFR) | Bắt buộc (content agent) |
| Lesson chơi được | `content.exercises` không rỗng; dùng `Lesson.exercise_count`, không dùng `total_exercises` | Bắt buộc (learner endpoint 409, cổng publish) |
| Lesson đa dạng | ≥ 3 `ui_type` khác nhau, ≥ 1 bài **sản sinh** (gõ/viết/nói), không có câu hỏi chung chung kiểu "Match the words with their meanings" | Bắt buộc với bài AI sinh (`lesson_is_varied`, `policies.PRODUCTION_UI_TYPES`) |
| Lesson.skill / Course.skill | Nhãn kỹ năng; điểm kỹ năng của người học lấy từ nhãn này (`resolve_lesson_skill`) | Báo cáo khi lệch với bài thật (`--balance`) |
| Lesson.outcome | Câu can-do dạng "You can …" (theo CEFR Companion Volume) | Báo cáo tỉ lệ có (`--balance`); chưa bắt buộc |
| Độ khó văn bản | Từ vựng phải hợp cấp độ khai báo | Báo cáo (`--level-fit`), xem §5 |

Bài sản sinh (`PRODUCTION_UI_TYPES`): `fill_in_the_blank` (gõ, không lựa chọn),
`dictation`, `grammar_correction`, `short_writing_answer`, `dialogue_completion`,
`speaking_repeat`, `pronunciation_practice`. Lý do: chỉ chọn đáp án là chưa đủ
(Swain, Output Hypothesis).

### Đề IELTS Reading (`IeltsTest`, không phải khoá học)

Đề sinh bằng `scripts/generate_ielts_paper.py`, luật ở `app/services/ielts_paper_builder.py`:

- 40 câu, 3 passage, mỗi passage 700–900 từ.
- Blueprint 13 + 13 + 14: True/False/Not Given, sentence completion (giới hạn số từ),
  multiple choice, matching headings, summary completion.
- Passage chỉ lấy từ manifest đã ghim (`scripts/ielts_passage_manifest.json`).
- Mỗi câu qua lượt giải mù: phải ra cùng đáp án **và** trích được bằng chứng có thật
  trong passage. Dưới 40 câu sống sót thì đề bị từ chối.
- Đề vào `is_published=false`, kèm `provenance`. Cổng publish kiểm tra provenance.

> Các **khoá** tên IELTS trong `content/courses/` không theo format IELTS thật
> (passage 41–136 từ, không có nhóm TFNG/headings). Xem §9.

---

## 2. Khung chuẩn tham chiếu

| Chuẩn | Dùng cho | Code có kiểm không |
|---|---|---|
| **CEFR** (Council of Europe 2001; Companion Volume 2020) | Cấp độ A1–C2 của khoá, từ vựng, bài thi; mục tiêu can-do | Nhãn hợp lệ: **có**. Văn bản khớp cấp độ: **báo cáo** (§5) |
| **CEFR-J Wordlist 1.5** (Tono, TUFS) | Cấp độ từ A1–B2; content agent chọn từ mục tiêu theo `declared_cefr` | **Có** khi chọn từ (`plan_curriculum`, `require_labelled_source`) |
| **Octanove Vocabulary Profile C1/C2 1.0** | Cấp độ từ C1–C2 | Dùng trong bảng đo (§5) |
| **CEFR-J Grammar Profile 20180315** | Cấp độ điểm ngữ pháp | **Chưa dùng** (dữ liệu có, chưa nối) |
| **Định dạng IELTS Academic Reading** | Đề `IeltsTest` | **Có**, đầy đủ (§1) |
| **IELTS band descriptors** | Chấm bài Writing/Speaking của người học (`ielts_grader.py`) | Có, khi chấm; không áp lên nội dung khoá |
| GSE (Pearson), English Vocabulary Profile (Cambridge) | — | **Không dùng.** Không có giấy phép; đừng ghi tên chúng trong tài liệu marketing |
| Academic Word List | — | Chỉ xuất hiện trong tag seed |

---

## 3. Nguồn dữ liệu và giấy phép

| Nguồn | Vai trò | Giấy phép trong code | Ghi chú |
|---|---|---|---|
| CEFR-J Wordlist + Grammar Profile | Nhãn CEFR cho từ (seed) | `LicenseRef-CEFR-J-Commercial` | README của `ai-service/data/lexicon/` ghi "miễn phí cho nghiên cứu và thương mại nếu trích dẫn"; ETL vẫn để chưa ghim. **Cần xác nhận lại điều khoản trước khi phân phối dữ liệu gốc.** Chỉ dùng để đo, không trả từ điển ra API |
| Octanove C1/C2 | Nhãn CEFR C1–C2 | CC BY-SA 4.0 | Share-alike |
| Open English WordNet 2025 (OEWN) | Bổ sung định nghĩa, ví dụ (reference, không chọn từ) | CC BY 4.0 | Ghi công đi theo `lineage.enrichment` và manifest |
| CMUdict | Phát âm → IPA | `LicenseRef-CMUdict` (BSD-style) | Giữ dấu nhấn (`AH0`/`AH1`) |
| Tatoeba | Câu ví dụ | CC BY 2.0 FR | |
| Wikidata | Chủ đề | CC0 1.0 | |
| LibriSpeech, Common Voice | Audio | CC BY 4.0 / CC0 | |
| Upload của admin | Nguồn seed có nhãn | `LicenseRef-Admin-Owned` | |
| Passage IELTS | Wikipedia (theo `oldid`), Gutenberg, trang `.gov` | CC BY-SA 4.0 (5), Public Domain (1), US Gov Public Domain (1) | Câu hỏi do LLM viết; passage không bị sửa |
| Nội dung LLM sinh | Bài tập, mission | `LicenseRef-Generated` | Groq `qwen/qwen3.8-27b` → Gemini → template |

Quy tắc ETL: một dataset chỉ bật khi **cả** version **và** sha256 đã ghim; nguồn
`reference` không bao giờ tự chọn từ, chỉ lấp trường còn thiếu. Chi tiết ở CLAUDE.md
mục "Content ETL / Crawl".

---

## 4. Ràng buộc từng dạng bài tập

Một hàm cho mọi đường ghi: `exercise_shape_problems` (`backend-service/app/models/course.py`).
`@validates("content")` tự suy `type` từ `ui_type`, vì bộ chấm chọn luật theo `type`.

| ui_type | Ràng buộc |
|---|---|
| Mọi dạng | `question` không rỗng; `correct_answer` không rỗng (trừ `short_writing_answer`); `ui_type` phải biết |
| `multiple_choice`, `collocation_choice`, `translation_choice`, `listen_and_choose`, `reading_comprehension`, `vocabulary_flashcard` | ≥ 2 lựa chọn; đáp án nằm trong lựa chọn; **không có hai lựa chọn trùng nhau** sau khi bỏ hoa/thường, khoảng trắng, dấu câu cuối |
| `image_based_choice` | Như trên + bắt buộc `image_url`. Chưa có pipeline ảnh → generator không được sinh dạng này |
| `true_or_false` | Đáp án là `True` hoặc `False` |
| `match_word_to_meaning`, `categorization`, `cognitive_fluidity` | `options` = mọi key rồi mọi value (≥ 2 cặp, ≥ 4 option); `correct_answer` = `"k1:v1, k2:v2"`, **ngăn cách bằng `", "`** |
| `arrange_the_sentence` | `options` là đúng các từ của câu đáp án (đã xáo); đáp án không bao giờ là một option |
| `fill_in_the_blank`, `dialogue_completion`, `grammar_correction` có option | Đáp án nằm trong option, không trùng option; `dialogue_completion` không option phải có `{blank}` |
| `short_writing_answer` | Câu dịch phải có đáp án mẫu; đáp án mẫu đúng ngôn ngữ đề yêu cầu; câu Đúng/Sai → `true_or_false`; câu hỏi "chọn/which … best" hoặc có lựa chọn → `multiple_choice` |

Chấm `short_writing_answer` (`app/core/free_form_writing.py`): đúng ngôn ngữ đích, là
chữ thật (không phải gõ bừa), không phải câu đệm ("ok", "idk"); câu dịch có trích
nguồn thì phải trùng ≥ 65% từ (token F1) với đáp án mẫu. Đáp án chưa chấm chắc được
thì không thành bằng chứng cho lịch ôn tập.

Sửa tự động: `retype_misused_writing` chuyển các bài viết dùng sai dạng sang
`multiple_choice` / `true_or_false` / `fill_in_the_blank`; mọi đường ghi chạy nó trước
khi kiểm tra.

---

## 5. Xác thực đáp án và đo cấp độ

### 5.1 Lượt giải mù (blind answer, `blind-answer-v1`)

Sau khi LLM sinh bài, một lượt gọi thứ hai giải từng câu **không thấy đáp án và lời
giải thích**, lựa chọn giữ nguyên thứ tự. Câu nào model chọn khác đáp án đã lưu (hoặc
trả -1: không có / nhiều hơn một đáp án đúng) bị loại.

- **Được kiểm:** mọi bài có ≥ 2 lựa chọn và đáp án nằm trong đó: `multiple_choice`,
  `true_or_false`, `translation_choice`, `collocation_choice`, `vocabulary_flashcard`,
  `reading_comprehension`, và `fill_in_the_blank`/`dialogue_completion`/
  `grammar_correction` có lựa chọn.
- **Không kiểm, và vì sao:** `short_writing_answer` (nhiều cách viết đúng),
  `speaking_repeat`/`pronunciation_practice` (chấm bằng độ giống), dạng ghép cặp và
  `arrange_the_sentence` (không có một lựa chọn để chọn), `listen_and_choose` (đáp án
  là âm thanh app đọc), bài gõ không lựa chọn.
- **Còn < 3 bài hoặc mất bài sản sinh** → coi như lần sinh hỏng, sinh lại; hết lượt thì
  không ghi đè gì.
- **Lượt kiểm lỗi** (mạng, JSON hỏng; đã thử lại 1 lần): script batch **dừng**; admin
  nhận bản nháp với `verification.status = "unverified"` để tự duyệt.
- Kết quả lưu vào `content.verification` (`method`, `checked`, `agreed`, `dropped`),
  và trả về cho admin trong `POST /admin/lessons/{id}/generate-exercises`.

Áp dụng ở: content agent (ai-service `content_agent/verification.py`), admin AI draft
và `scripts/generate_exercises_ai.py` (backend `exercise_generation.verify_exercises`).

Giới hạn: người giải là cùng một model, nên lỗi kiến thức chung của model không bị bắt.
Đây là lưới lọc đáp án sai/mơ hồ, không thay người duyệt.

### 5.2 Đo cấp độ CEFR (`app/services/cefr_level_fit.py`, báo cáo)

Tách từ nội dung của `question`, `options`, `correct_answer` (bỏ đoạn tiếng Việt, bỏ
`explanation`), tra cấp độ thấp nhất của từ trong lexicon, rồi:

| Kết luận | Điều kiện (hằng số trong module) |
|---|---|
| `unknown` | < 30 từ tra được (`MIN_LISTED_WORDS`) |
| `too_hard` | > 15% từ tra được nằm **trên** cấp khai báo (`TOO_HARD_ABOVE_SHARE`) |
| `too_easy` | Chỉ từ B2 trở lên: < 10% từ ở mức cấp khai báo − 1 trở lên (`TOO_EASY_MIN_NEAR_SHARE`) |
| `fits` | Còn lại |

Lexicon: bảng `vocabulary_items` trên DB (endpoint và audit), hoặc file
`ai-service/data/lexicon/cefr_vocabulary.jsonl` (script offline). Từ không có trong
lexicon được đếm riêng, không tính là khó. Ngưỡng mới hiệu chỉnh trên 15 khoá trong
repo — **chưa đủ để chặn publish**.

---

## 6. Cổng publish và các đường ghi

`CourseCRUD.publish_blockers` chạy khi chuyển draft → published. Nó chặn nếu: khoá
không có lesson, lesson không có bài, **hoặc bất kỳ bài nào vi phạm §4**. Đây là chốt
chung bắt cả những gì đã lọt qua các đường ghi khác (script, seed, SQL tay).

| Đường ghi | Kiểm dạng (§4) | Giải mù (§5.1) | Ghi nguồn gốc | Người duyệt |
|---|---|---|---|---|
| Content agent (`/admin/content-agent`) | Chặn trong `validate_artifact` (`EXERCISE_SHAPE_INVALID`) và khi admin sửa record (422) | Có | `ContentProvenance`, `content.generation_mode` (`llm`/`template`), `content.verification`; cảnh báo `LESSON_TEMPLATE_FALLBACK`, `LESSON_UNVERIFIED` | Khoá vào draft; admin xem trang Content QA rồi publish |
| Admin sửa lesson (`PUT /admin/lessons/{id}`, `/content`) | 422 nêu tên bài | — (người soạn) | — | Chính admin |
| Admin AI draft (`POST /admin/lessons/{id}/generate-exercises`) | `sanitize_exercises`, rồi PUT kiểm lại | Có; trả thống kê cho admin | `verification` trong response | Admin bấm lưu |
| `scripts/generate_exercises_ai.py` | `sanitize_exercises` | Có, lỗi thì dừng | `generated_by`, `model`, `generated_at`, `verification`; tăng `content_version`; backup nội dung cũ ra `backups/lesson-content-<ts>.json` | `--regenerate` bỏ qua khoá đã publish trừ khi có `--include-published` |
| `content/courses/*.json` + `import_course_content.py` | CI (`test_committed_course_content.py`) | — | git history | PR review |
| Seed (`admin_seed_service`) | Chỉ publish khi qua `publish_blockers` | — | — | — |
| Đề IELTS | `validate_paper` | Có (kèm bằng chứng) | `provenance` đầy đủ | Cổng publish IELTS |

Khi LLM lỗi, content agent rơi về **template** soạn sẵn. Template đã được sửa để đúng
dạng (Đúng/Sai không còn luôn là True, bài ghép cặp ≥ 2 cặp, bỏ bài khi không có định
nghĩa thật) nhưng vẫn đơn điệu — job sẽ ghi cảnh báo "template fallback" và lesson mang
`generation_mode: "template"`. **Đừng publish khoá có nhiều lesson template mà chưa
đọc lại.**

---

## 7. Checklist trước khi publish

Áp dụng cho cả khoá AI sinh và khoá soạn tay.

- [ ] `audit_course_content.py` báo **0** bài sai dạng
- [ ] Mọi lesson có ≥ 3 dạng bài và ≥ 1 bài sản sinh
- [ ] Lesson AI sinh: `content.verification` có, `agreed` = `checked`; không còn cảnh
      báo `LESSON_UNVERIFIED`
- [ ] Lesson `generation_mode: "template"` đã được người đọc lại hoặc sinh lại
- [ ] `--level-fit` của khoá là `fits` (hoặc lệch có lý do, ghi vào mô tả khoá)
- [ ] `--balance`: `Course.skill` khớp kỹ năng bài tập thật đo; mỗi unit có bài sản sinh
- [ ] Lesson có `outcome` dạng "You can …" (khuyến nghị; chưa bắt buộc)
- [ ] Bài trắc nghiệm: phương án nhiễu **sai rõ ràng**, không có hai phương án cùng đúng
      về nghĩa (code chỉ bắt trùng chữ — ví dụ "couldn't care less" và "could not care
      less" phải do người phát hiện)
- [ ] Nguồn ngoài (passage, câu ví dụ) có trong bảng §3 và ghi công đúng

---

## 8. Lệnh vận hành

```bash
cd backend-service
venv/bin/python3 scripts/audit_course_content.py                    # báo cáo dạng bài + khoá không chơi được
venv/bin/python3 scripts/audit_course_content.py --fix-unplayable   # sửa tự động những gì sửa được
venv/bin/python3 scripts/audit_course_content.py --level-fit --balance   # chỉ báo cáo CEFR + cân bằng
venv/bin/python3 scripts/report_content_level_fit.py \
    --courses content/courses --lexicon ../ai-service/data/lexicon/cefr_vocabulary.jsonl  # không cần DB
venv/bin/python3 scripts/generate_exercises_ai.py --regenerate       # sinh lại bài yếu (bỏ qua khoá đã publish)
```

API cho admin: `GET /api/v1/admin/courses/{id}/quality` → `level_fit` + `balance` (quyền
`courses:read`; chỉ trả tỉ lệ, không trả từ điển).

Trên prod, chạy trong container: `docker exec lexilingo-backend-service python scripts/…`.
Trước mọi lệnh `--fix-*`, dump bảng `lessons` vào `.deploy/`.

---

## 9. Hiện trạng và việc còn mở (2026-11-28)

Đo trên 15 khoá trong repo (lexicon CEFR-J + Octanove):

| Khoá | Khai báo | Kết luận | Ghi chú |
|---|---|---|---|
| Advanced English Mastery | C2 | too_easy | 67% từ A1/A2, chỉ ~4% C1/C2 |
| IELTS Foundation Band 3–4 | A1 | too_hard | 42% từ trên A1; band 3–4 tương đương khoảng A2 |
| IELTS Starter 4–5 | A2 | too_hard | 20% từ trên A2; band 4–5 khoảng B1 |
| Daily Vocabulary Starter, English Grammar Foundations | A1 | too_hard (sát ngưỡng) | Từ mục tiêu như tên người trong gia đình được CEFR-J xếp trên A1 |
| 10 khoá còn lại | | fits | |

Các điểm còn mở:

1. **Gắn lại nhãn cấp độ** cho 3 khoá trên, hoặc sinh lại nội dung cho đúng cấp — thay
   đổi dữ liệu prod, cần quyết định.
2. **Khoá IELTS không theo format IELTS**: đổi tên thành "IELTS-style practice" hoặc
   dẫn người học sang đề `IeltsTest` thật. Listening chưa có bộ sinh.
3. **0% lesson có `outcome`** — cần bổ sung can-do statements.
4. **6 khoá có `Course.skill` lệch** kỹ năng bài tập thật (ví dụ Everyday English
   khai báo speaking nhưng không có bài nói).
5. **Chưa có trạng thái duyệt theo lesson** (`review_status`) — cần migration. Hiện việc
   duyệt là bước publish của admin.
6. **Content agent gửi `reasoning_effort: "none"`** cho qwen, ngược với ghi chú "generation
   giữ reasoning" trong CLAUDE.md; lượt giải mù dùng chung cấu hình nên có thể kém chính
   xác hơn mức có thể.
7. **Ngưỡng CEFR chưa đủ dữ liệu để thành cổng chặn**; lexicon trên prod chỉ lớn bằng bảng
   `vocabulary_items`, khoá ít từ trùng sẽ ra `unknown`.
8. **CEFR-J Grammar Profile** (500 điểm ngữ pháp) chưa được dùng để kiểm cấp độ ngữ pháp.
9. **13 khoá lớn chỉ có trên DB** không tái tạo được từ repo; chạy `--level-fit --balance`
   trên prod để có số liệu thật.
