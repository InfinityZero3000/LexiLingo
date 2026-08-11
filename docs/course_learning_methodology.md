# Phương pháp luận Course/Lesson cho LexiLingo — Tổng hợp nghiên cứu & đề xuất

> Mục tiêu tài liệu: tổng hợp các nghiên cứu học thuật đã công bố về phương pháp học ngôn ngữ hiệu quả, đối chiếu với cách Duolingo triển khai (cả điểm mạnh lẫn giới hạn), và rút ra một khung phương pháp cụ thể cho LexiLingo — tổ chức theo **mission/task** thay vì danh sách thì/loại từ, tránh đơn điệu, tạo giá trị tri thức thật.
>
> Đây là tài liệu nghiên cứu + đề xuất (chưa implement). Phần "Bước tiếp theo" ở cuối liệt kê các lựa chọn để quyết định trước khi viết code/migration.

---

## 1. Câu hỏi cốt lõi

Duolingo tổ chức nội dung theo **skill** (nhóm ngữ pháp/chủ đề từ vựng — "linguistic-content syllabus"). LexiLingo hiện cũng vậy (category: Grammar, Vocabulary, Business English...). Câu hỏi: có nên chuyển sang **task-based syllabus** (đơn vị = việc người học làm được bằng ngôn ngữ), và nếu có thì tổ chức lại như thế nào để vừa giữ được nền tảng ngữ pháp/từ vựng có hệ thống, vừa tạo trải nghiệm không nhàm chán, không chỉ là "chọn đáp án cho xong"?

---

## 2. Tổng hợp nghiên cứu

### 2.1. Đơn vị lập kế hoạch: Task/Mission, không phải danh sách ngữ pháp

**Nguồn:** Richards, J.C. & Rodgers, T.S. (2014). *Approaches and Methods in Language Teaching*, 3rd ed., Chương 9 "Task-Based Language Teaching". Cambridge University Press. DOI: 10.1017/9781009024532.012

Trích Van den Branden (2006:3), dẫn trong sách:

> Curricula/syllabuses formulate lower-level goals either in terms of **linguistic content** (which words/grammar rules to acquire) or in terms of **language use** (what learners will be able to do with the language). Task-based curricula belong to the second category.

TBLT (Task-Based Language Teaching) coi **task có mục đích thực (real-world, non-linguistic purpose)** là đơn vị lập kế hoạch dạy học — không phải bài ngữ pháp. Task ở đây nghĩa là: người học dùng ngôn ngữ để hoàn thành một việc có ý nghĩa (đặt bàn nhà hàng, viết email xin nghỉ, thuyết phục ai đó...), tập trung vào **trao đổi ý nghĩa (meaning exchange)** trước, đúng ngữ pháp là thứ yếu.

TBLT được coi là "approach" chứ không phải "method" cứng — kết hợp được với các syllabus khác (content-based, text-based), nên **không cần bỏ hệ thống ngữ pháp/CEFR hiện có**, chỉ cần đổi vai trò của nó.

**Cấu trúc bài học 3 pha (Jane Willis, 1996 — chuẩn TBLT thực hành):**

| Pha | Nội dung | Vai trò của ngữ pháp |
|---|---|---|
| **Pre-task** | Giới thiệu mission, kích hoạt từ vựng/ngữ cảnh | Không dạy trước |
| **Task cycle** | Người học thực hiện task bằng ngôn ngữ đang có (nói/viết), có thể sai, ưu tiên hoàn thành mục tiêu | Không sửa lỗi giữa chừng |
| **Language focus** | Phân tích/luyện điểm ngữ pháp-từ vựng **nảy sinh từ chính task đã làm** | Ngữ pháp xuất hiện SAU, phục vụ task |

→ **Áp dụng:** Course/Unit/Lesson của LexiLingo nên tổ chức bề mặt (title, mô tả, mục tiêu hiển thị cho người học) theo **mission**, còn CEFR level + GrammarItem/VocabularyItem hiện có vẫn giữ nguyên vai trò — nhưng lùi xuống làm **ràng buộc nội dung** (task ở A2 phải kéo đúng ngữ pháp/từ vựng A2 vào), đúng như bạn đã chốt: "khung cố định vẫn cần tồn tại, nhưng chỉ là khung sư phạm, không phải khung UI".

### 2.2. CEFR chính thức cũng đã đi theo hướng "task/can-do", không phải danh sách ngữ pháp

**Nguồn:** Council of Europe — *Common European Framework of Reference for Languages* (CEFR) và CEFR Companion Volume (2018/2020), coe.int/en/web/common-european-framework-reference-languages

CEFR mô tả năng lực người học bằng **can-do descriptors** ("I can order food in a restaurant", "I can write a simple personal letter") — mô tả **việc làm được**, không phải "đã học thì nào". Đây là điểm quan trọng: **hệ thống level A1–C2 mà LexiLingo đang dùng vốn được thiết kế theo tinh thần action-oriented**, chỉ là cách LexiLingo (và cả Duolingo) đang *hiện thực hoá* nó thành danh sách kỹ năng ngữ pháp thay vì can-do task. Nghĩa là chuyển sang mission-based **không mâu thuẫn** với CEFR đang dùng — mà là dùng đúng tinh thần gốc của CEFR hơn.

→ **Áp dụng:** Mỗi Mission nên có 1 câu can-do statement làm "outcome" hiển thị cho người học (vd: "Sau mission này, bạn có thể đặt bàn ăn qua điện thoại bằng tiếng Anh") — đây chính là field `outcome`/`objective` đã xác định là còn thiếu trong model `Course`/`Lesson` (xem phần 4).

### 2.3. Input dễ hiểu + hạ "bộ lọc cảm xúc" — Krashen

**Nguồn:** Krashen, S.D. (1986). *Principles and Practice in Second Language Acquisition*. Pergamon Press. (sdkrashen.com/content/books/principles_and_practice.pdf)

Hai giả thuyết liên quan trực tiếp tới trải nghiệm app:

- **Input Hypothesis (i+1):** người học tiến bộ khi tiếp xúc input nhỉnh hơn trình độ hiện tại một chút, không phải input ngang bằng hay quá cao.
- **Affective Filter Hypothesis:** 3 biến số — **motivation, self-confidence, anxiety** — quyết định input có "lọt vào" được hay không. Lo âu cao → dù input dễ hiểu vẫn khó hấp thụ.

Yếu tố **làm tăng** affective filter (cản trở học), theo tổng hợp thực hành từ Krashen: **error correction (sửa lỗi tức thì), forcing output too early (ép nói/viết quá sớm), isolation, embarrassment.**

→ **Áp dụng trực tiếp và quan trọng:** cơ chế "tim/mạng sống" (hearts) kiểu Duolingo — trả lời sai bị trừ mạng ngay lập tức, hết mạng bị chặn học — là một dạng **error correction tức thì + nguy cơ embarrassment**, đi ngược Krashen. LexiLingo có thể **làm tốt hơn Duolingo ở đây**: phản hồi sai mang tính xây dựng (gợi ý, không chặn), cho thử lại trong task cycle, chỉ tổng kết/đánh giá ở cuối mission — vừa giữ được "desirable difficulty" (mục 2.4) vừa không đẩy affective filter lên cao.

### 2.4. Output Hypothesis — vì sao chỉ chọn đáp án là chưa đủ

**Nguồn:** Swain, M. (1985). "Communicative competence: Some roles of comprehensible input and comprehensible output in its development." Trong *Input in Second Language Acquisition*, Gass & Madden (eds).

Swain chỉ ra: input dễ hiểu (Krashen) là điều kiện cần nhưng **chưa đủ**. Người học cần **ép buộc sản sinh ngôn ngữ (pushed output)** — nói/viết — để nhận ra khoảng trống giữa cái mình *hiểu được* và cái mình *tự nói được* ("noticing the gap"), từ đó việc học mới thật sự xảy ra ở tầng sản sinh (production), không chỉ tầng nhận diện (recognition).

→ **Áp dụng:** đây là cơ sở học thuật chính xác cho đúng nỗi lo của bạn — "trắc nghiệm chọn đáp án là xong" chỉ luyện **recognition**, không luyện **production**. Mỗi Mission (task cycle) bắt buộc có tối thiểu 1 exercise dạng production (nói qua STT, hoặc viết câu tự do có chấm bằng LLM/rule), không thể toàn bộ là MCQ/tap-the-word.

### 2.5. Trí nhớ dài hạn: đường cong quên & ôn tập đúng lúc

**Nguồn:** Ebbinghaus, H. (1885) — forgetting curve. Và: Settles, B. & Meeder, B. (2016). "A Trainable Spaced Repetition Model for Language Learning." *Proceedings of ACL*, pp. 1848–1858. (aclweb.org/anthology/P/P16/P16-1174.pdf) — đây chính là bài báo khoa học Duolingo công bố về thuật toán **Half-Life Regression (HLR)**.

Cơ chế: xác suất nhớ một từ giảm theo hàm mũ theo thời gian kể từ lần ôn cuối (`p = 2^(-Δ/h)`, Δ = thời gian đã trôi qua, h = "half-life" — thời gian trí nhớ giảm còn một nửa). Thời điểm ôn tối ưu là **khi Δ và h gần bằng nhau** — tức sắp quên nhưng chưa quên hẳn.

Duolingo thử nghiệm HLR so với hệ thống Leitner cũ (flashcard cổ điển) trên 12 triệu phiên học thật: HLR giảm sai số dự đoán gần một nửa, và A/B test cho kết quả **retention tăng 9.5% (phiên ôn tập), 1.7% (bài học mới), 12% (hoạt động tổng thể)**.

→ **Áp dụng:** LexiLingo cần một cơ chế ôn tập dựa trên forgetting-curve cá nhân hoá cho từng VocabularyItem/GrammarItem đã học (không chỉ ôn ngẫu nhiên hoặc theo lịch cố định) — đúng bản chất "review" của `lesson_type` hiện có, nhưng cần dữ liệu lịch sử đúng-sai theo thời gian để ước lượng half-life, không phải chỉ đếm số lần đúng.

### 2.6. "Desirable difficulties" — khó vừa đủ mới nhớ lâu

**Nguồn:** Bjork, R.A. & Bjork, E.L. (nhiều công bố từ 1994; tổng hợp gần đây: Soderstrom et al. 2022, *Medical Education*; Cepeda et al. 2006; Roediger & Karpicke 2006; Pan et al. 2019; Larsen et al. 2022, *Medical Teacher*). bjorklab.psych.ucla.edu/research

4 kỹ thuật "khó có chủ đích" được chứng minh hiệu quả (kèm effect size cụ thể):

| Kỹ thuật | Ý nghĩa | Hiệu quả đo được |
|---|---|---|
| **Spacing** | Giãn cách các lần ôn thay vì học dồn (cramming) | Cepeda et al. 2006: tăng retention 10–30% |
| **Retrieval practice** | Chủ động nhớ lại (test) thay vì đọc lại | Roediger & Karpicke 2006: tăng khả năng nhớ lại ~50% |
| **Interleaving** | Trộn nhiều chủ đề/dạng bài thay vì học khối (block) một chủ đề liên tục | Pan et al. 2019: d = 0.67 (hiệu ứng lớn), do giúp phân biệt (discriminate) giữa các khái niệm |
| **Generation effect** | Tự tạo ra câu trả lời thay vì nhận diện có sẵn | Liên hệ trực tiếp Output Hypothesis (2.4) |

**Lưu ý quan trọng — không phải "càng khó càng tốt":** Larsen et al. (2022) trên nhóm bác sĩ nội trú cho thấy kết hợp spacing + retrieval nâng điểm từ 149 → 160, nhưng thêm interleaving vào thành bộ ba thì điểm **giảm xuống** — có ngưỡng mà độ khó vượt quá sẽ phản tác dụng (Cognitive Load Theory). 

→ **Áp dụng:** thiết kế bài tập nên **trộn dạng bài trong cùng 1 mission** (không làm 10 câu MCQ liên tiếp cùng dạng) và **ôn qua retrieval** (nhớ lại) thay vì cho xem lại đáp án — nhưng không dồn quá nhiều loại "khó" cùng lúc trong 1 buổi học ngắn, đặc biệt với người mới (A1-A2).

### 2.7. Flow: giữ người học trong vùng "vừa đủ thách thức"

**Nguồn:** Csikszentmihalyi, M. — Flow Theory. Và ứng dụng thực tế: Duolingo Birdbrain — Bicknell, K. & Brust, C. (2020). "Learning how to help you learn: Introducing Birdbrain!" blog.duolingo.com/learning-how-to-help-you-learn-introducing-birdbrain/

Flow = trạng thái tập trung tối đa khi **độ khó của nhiệm vụ khớp sát với năng lực hiện tại**: quá dễ → chán (boredom), quá khó → lo âu (anxiety, liên hệ trực tiếp Krashen ở 2.3).

Duolingo hiện thực hoá bằng **Birdbrain**: mô hình ML dự đoán xác suất người học trả lời đúng cho *từng bài tập cụ thể với từng người học cụ thể* (không phải độ khó chung chung), rồi cấp thông tin này cho "Session Generator" để chọn đúng bài ở đúng độ khó. Kết quả đo được: tăng cả **learning** (học được nhiều hơn) lẫn **engagement** (quay lại đều hơn, học nhiều bài hơn/ngày) trong A/B test.

→ **Áp dụng:** hệ thống chấm điểm khó/dễ hiện có (nếu chưa có, cần bổ sung) nên là **per-user per-exercise**, không phải chỉ gắn cứng CEFR level vào exercise. Đây là điều kiện để "flow" hoạt động — nếu chỉ dựa vào level tĩnh, hai người cùng A2 nhưng mạnh/yếu khác nhau ở từng điểm ngữ pháp sẽ có trải nghiệm rất khác nhau.

### 2.8. Động lực nội tại: Tự chủ – Năng lực – Kết nối

**Nguồn:** Deci, E.L. & Ryan, R.M. — Self-Determination Theory (selfdeterminationtheory.org). Ứng dụng UX: Kohler, T. (2022). "Autonomy, Relatedness, and Competence in UX Design." Nielsen Norman Group, nngroup.com/articles/autonomy-relatedness-competence/

3 nhu cầu tâm lý nền tảng thúc đẩy động lực **nội tại** (làm vì muốn, không phải vì bị ép):

- **Autonomy (tự chủ):** được chọn lựa theo ưu tiên của bản thân.
- **Competence (năng lực):** cảm thấy mình làm được, đang tiến bộ.
- **Relatedness (kết nối):** cảm thấy được kết nối/thấu hiểu bởi người khác.

→ **Áp dụng:**
- *Autonomy*: cho người học **chọn mission** theo hứng thú (du lịch, phỏng vấn, hẹn hò, công việc...) thay vì đường đi tuyến tính bắt buộc — đúng tinh thần "mission-based" bạn đề xuất từ đầu.
- *Competence*: hệ quả trực tiếp của Flow/Birdbrain (2.7) — đúng độ khó = cảm nhận năng lực đúng.
- *Relatedness*: LexiLingo đã có sẵn hạ tầng xã hội (follow, leaderboard, activity feed trong `gamification.py`) — nên gắn vào mission (vd: mission theo nhóm bạn, chia sẻ kết quả task thật) thay vì chỉ dùng cho XP ranking thuần tuý.

### 2.9. Cách Duolingo scale nội dung — tham khảo được, nhưng cần nâng cấp

**Nguồn:** Henry, P. (2023). "How Duolingo uses AI to create lessons faster." blog.duolingo.com/large-language-model-duolingo-lessons/ (đã đọc ở lượt trước)

Quy trình: Learning Designer định chủ đề + ngữ pháp mục tiêu → điền "prompt Mad Lib" (rule cố định: số đáp án, giới hạn ký tự + rule biến đổi: CEFR level, ngữ pháp, chủ đề) → LLM sinh ~10 câu → **người có chuyên môn chọn 2-3 câu tốt nhất và luôn có thể chỉnh sửa** trước khi publish.

**Giới hạn của cách này khi soi qua các nghiên cứu ở trên:** prompt vẫn tổ chức theo **ngữ pháp là mục tiêu chính** ("must contain THE PRETERITE TENSE"), câu sinh ra là **câu đơn lẻ, không có task/mục đích giao tiếp thật** — đúng dạng "linguistic-content syllabus" mà TBLT (2.1) phân biệt với task-based. Đây chính là chỗ LexiLingo có thể vượt qua: dùng cùng cơ chế (LLM + human curation) nhưng **prompt được điều khiển bởi mission/task** (rule biến đổi = tình huống + can-do outcome, không chỉ = tense), sinh ra **cả một task cycle** (hội thoại/tình huống nhiều bước) chứ không chỉ câu đơn lẻ.

---

## 3. Duolingo — điểm mạnh nên học, giới hạn có thể vượt qua

| | Duolingo hiện tại | Cơ sở nghiên cứu | LexiLingo có thể làm gì hơn |
|---|---|---|---|
| Đơn vị tổ chức | Skill (ngữ pháp/chủ đề từ vựng) | TBLT: linguistic-content vs task-based syllabus (2.1) | Mission (can-do outcome), ngữ pháp lùi thành ràng buộc nội dung |
| Ôn tập | HLR — rất tốt, có bằng chứng khoa học mạnh | Ebbinghaus, Settles & Meeder 2016 (2.5) | Áp dụng nguyên lý tương tự, không cần phát minh lại |
| Độ khó | Birdbrain — adaptive per-learner per-exercise | Flow Theory (2.7) | Áp dụng nguyên lý tương tự |
| Dạng bài | Đa số MCQ/tap-the-word (recognition) | Swain Output Hypothesis (2.4) | Bắt buộc có production (nói/viết) mỗi mission |
| Sửa lỗi | Hearts/lives — trừ mạng ngay khi sai | Krashen Affective Filter (2.3): error correction tức thì làm tăng lo âu | Phản hồi xây dựng, đánh giá cuối task thay vì chặn giữa chừng |
| Sinh nội dung AI | Mad Lib prompt theo ngữ pháp, câu đơn lẻ | TBLT (2.1) | Prompt theo mission, sinh cả task cycle có ngữ cảnh |
| Động lực | Streak, XP, league (extrinsic mạnh) | SDT (2.8): cần cả autonomy + competence, không chỉ extrinsic reward | Thêm lựa chọn mission theo sở thích (autonomy) |

---

## 4. Đối chiếu nhanh với hệ thống hiện tại của LexiLingo

(Đã khảo sát ở các lượt trước trong phiên làm việc này — liệt kê lại để tài liệu tự đủ nghĩa)

- `Course` → `Unit` → `Lesson` (course.py): đã đủ linh hoạt, không khoá cứng theo thì/loại từ. `Course` có `tags` (JSON tự do) + `category_id`; **chưa có field `outcome`/`objective`** (can-do statement, mục 2.2).
- `GrammarItem`/`VocabularyItem`: pool nội dung độc lập, có `topic`/`tags` riêng, không bắt buộc FK vào Course/Lesson — phù hợp để dùng làm "ràng buộc nội dung" cho mission (mục 2.1) mà không cần đổi schema.
- `content_agent` (ai-service) + `ContentQaQueuePage` (admin-service): đã có pipeline generate + hàng đợi duyệt người-trong-vòng-lặp — nhưng generator hiện là **template string cố định, không dùng LLM**, và hàng đợi **chưa có bước edit tại chỗ** (chỉ approve/reject/retry) — cần cho quy trình Mad Lib-nâng-cấp ở mục 2.9.
- `generate_exercises_ai.py` (backend-service/scripts) + `mcp-server/handlers/gemini.py`: đã có generate bằng LLM riêng lẻ, chưa nối với `content_agent`/QA queue.
- Gamification (`gamification.py`, `challenges.py`): đã có wallet/gems, XP, streak, leaderboard, follow/social — hạ tầng SDT relatedness (2.8) đã sẵn, chưa gắn vào mission.
- **Chưa xác nhận** (cần khảo sát riêng, không nằm trong tài liệu này): hệ thống SRS/mistake-notebook có tồn tại thật không (từng thấy tên migration `add_mistake_notebook_entries`, `add_learner_concept_state` — cần đọc code thật để biết đã làm tới đâu), kho exercise type hiện có (MCQ/fill-blank/listening/speaking...) và tính năng phát âm/STT đã merge tới đâu.

---

## 5. Khung phương pháp đề xuất cho LexiLingo (tổng hợp)

1. **Đơn vị tổ chức = Mission**, mô tả bằng 1 câu can-do (CEFR action-oriented, mục 2.2), không phải tên ngữ pháp.
2. **Cấu trúc mỗi Mission theo 3 pha TBLT** (mục 2.1): Pre-task (kích hoạt ngữ cảnh) → Task cycle (thực hành có output thật, đa dạng dạng bài, trộn loại theo interleaving — mục 2.6) → Language focus (chốt ngữ pháp/từ vựng nảy sinh từ task).
3. **Bắt buộc ≥1 exercise production** (nói/viết) mỗi mission, không để toàn bộ là recognition (mục 2.4).
4. **Độ khó thích ứng per-learner per-exercise** kiểu Birdbrain (mục 2.7), giữ trong flow channel.
5. **Ôn tập theo forgetting-curve cá nhân hoá** kiểu HLR (mục 2.5), không ôn ngẫu nhiên/cố định.
6. **Phản hồi lỗi mang tính xây dựng**, không phạt/chặn tức thì giữa task cycle (mục 2.3) — đánh giá tổng kết ở cuối mission.
7. **Cho chọn mission theo sở thích** (autonomy, mục 2.8), không ép tuyến tính hoàn toàn; giữ hạ tầng xã hội hiện có gắn vào mission thay vì chỉ dùng cho ranking.
8. **Sinh nội dung AI theo mission-prompt** (nâng cấp từ Mad Lib của Duolingo, mục 2.9): rule biến đổi = tình huống/can-do outcome, sinh cả task cycle có ngữ cảnh; route qua `content_agent` + `ContentQaQueuePage` đã có, bổ sung bước edit.

---

## 6. Bước tiếp theo (chưa làm, để quyết định)

- [ ] Khảo sát kỹ thuật: hệ thống SRS/mistake-notebook, kho exercise type, tính năng speech/STT hiện có tới đâu (làm rõ trước khi thiết kế schema).
- [ ] Thiết kế field `outcome`/`objective` (can-do statement) cho `Course`/`Lesson` + migration.
- [ ] Thiết kế bảng/relationship cho "Mission" nếu cần tách khỏi `Course` hiện có, hoặc tái dùng `Course`+`tags` không đổi schema.
- [ ] Thiết kế prompt template mission-based cho content_agent (thay template string hiện tại), nối với LLM.
- [ ] Thêm bước edit vào `ContentQaQueuePage`.
- [ ] Thiết kế thuật toán ôn tập kiểu HLR cho VocabularyItem/GrammarItem đã học.
- [ ] Thiết kế cơ chế difficulty-adaptation per-learner (Birdbrain-style) cho việc chọn exercise trong session.

---

## Nguồn tham khảo đầy đủ

1. Richards, J.C. & Rodgers, T.S. (2014). *Approaches and Methods in Language Teaching* (3rd ed.), Ch. 9. Cambridge University Press. https://doi.org/10.1017/9781009024532.012
2. Council of Europe. *Common European Framework of Reference for Languages* (CEFR) & CEFR Companion Volume. https://www.coe.int/en/web/common-european-framework-reference-languages
3. Krashen, S.D. (1986). *Principles and Practice in Second Language Acquisition*. Pergamon Press. http://www.sdkrashen.com/content/books/principles_and_practice.pdf
4. Swain, M. (1985). "Communicative competence: Some roles of comprehensible input and comprehensible output in its development." In Gass & Madden (eds.), *Input in Second Language Acquisition*.
5. Settles, B. & Meeder, B. (2016). "A Trainable Spaced Repetition Model for Language Learning." *Proceedings of ACL*, pp. 1848–1858. http://aclweb.org/anthology/P/P16/P16-1174.pdf
6. Duolingo Blog. "How we learn how you learn" (2016). https://blog.duolingo.com/how-we-learn-how-you-learn/
7. Bjork, R.A. & Bjork, E.L. — UCLA Bjork Learning and Forgetting Lab. https://bjorklab.psych.ucla.edu/research/ ; Cepeda et al. (2006); Roediger & Karpicke (2006); Pan et al. (2019); Larsen et al. (2022, *Medical Teacher*).
8. Bicknell, K. & Brust, C. (2020). "Learning how to help you learn: Introducing Birdbrain!" https://blog.duolingo.com/learning-how-to-help-you-learn-introducing-birdbrain/
9. Csikszentmihalyi, M. — Flow Theory (tổng hợp ứng dụng giáo dục: structural-learning.com/post/flow-state).
10. Deci, E.L. & Ryan, R.M. — Self-Determination Theory. https://selfdeterminationtheory.org/ ; Kohler, T. (2022), Nielsen Norman Group. https://www.nngroup.com/articles/autonomy-relatedness-competence/
11. Henry, P. (2023). "How Duolingo uses AI to create lessons faster." https://blog.duolingo.com/large-language-model-duolingo-lessons/
