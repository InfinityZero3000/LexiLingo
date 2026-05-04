# RPT-027 — Hệ Thống Đánh Giá Năng Lực (CEFR Proficiency Assessment)

> **Cập nhật:** 2026-04-24 | **Nguồn:** `backend-service/app/services/proficiency_service.py` (619 dòng)

---

## 1. Tổng Quan

Hệ thống đánh giá năng lực của LexiLingo khác biệt hoàn toàn với hệ thống XP. Trong khi XP đại diện cho **sự nỗ lực và thời gian** (cày cuốc), hệ thống Proficiency đo lường **kỹ năng thực tế** dựa trên độ chính xác và độ khó của các bài tập người dùng thực hiện.

Mục tiêu cốt lõi: Xác định chính xác trình độ CEFR (A1 → C2) của người dùng để GraphCAG và AI Tutor cung cấp nội dung phù hợp.

---

## 2. Kiến Trúc Thuật Toán Đánh Giá

Thuật toán đánh giá là một hàm đa chiều tính toán dựa trên:

1. **Khối lượng (Volume):** Không thể lên level nếu chỉ làm đúng 1-2 câu.
2. **Độ chính xác (Accuracy):** Tỷ lệ đúng/sai trong khoảng thời gian phân tích.
3. **Độ khó (Difficulty Multiplier):** Làm đúng bài khó (C1) được điểm kỹ năng cao hơn bài dễ (A1).
4. **Nhóm kỹ năng (Skill Weighting):** Phân bổ điểm theo 6 kỹ năng cốt lõi.
5. **Độ ổn định (Consistency):** Tính toán độ dốc (trend) của lịch sử học tập.

### 2.1 Trọng Số Kỹ Năng

| Kỹ năng | Weight | Nguồn Data Thường Gặp |
|---------|--------|-----------------------|
| `VOCABULARY` | 25% | Spaced Repetition, Word Scramble, Matching |
| `GRAMMAR` | 25% | Grammar Quiz, Fill Blank, GraphCAG phân tích lỗi |
| `READING` | 15% | News Reading, Reading Comprehension |
| `LISTENING` | 15% | Spelling Bee, Podcast, YouTube subtitles |
| `SPEAKING` | 10% | AI Voice Chat (Fluency score) |
| `WRITING` | 10% | Chat messages (GraphCAG chấm điểm) |

### 2.2 Hệ Số Độ Khó (Difficulty Multiplier)

Khi tính điểm thành phần, bài tập khó có hệ số nhân cao hơn:
- A1: x0.5
- A2: x0.7
- B1: x1.0
- B2: x1.3
- C1: x1.6
- C2: x2.0

---

## 3. Các Ngưỡng Level (Level Thresholds)

Để đạt được một level mới, user phải thỏa mãn đồng thời 2 điều kiện: **Min Score** và **Min Exercises** (thể hiện sự ổn định).

| CEFR Level | Min Score | Min Exercises | Yêu cầu Kỹ năng tối thiểu |
|------------|-----------|---------------|---------------------------|
| **A1**     | 0         | 0             | - |
| **A2**     | 250       | 50            | Grammar >= 40 |
| **B1**     | 600       | 150           | Vocab >= 100, Grammar >= 100 |
| **B2**     | 1200      | 350           | Mọi kỹ năng >= 150 |
| **C1**     | 2200      | 700           | Speaking >= 200, Writing >= 200 |
| **C2**     | 3800      | 1200          | Mọi kỹ năng >= 500 |

*Ví dụ:* Một user có 1500 điểm nhưng chưa làm đủ 350 bài tập thì vẫn sẽ bị kẹp ở B1, điều này chống hiện tượng "nhảy cóc" do hên xui trong vài bài quiz.

---

## 4. Flow Tính Toán Đánh Giá

Quá trình tính toán diễn ra theo các bước sau, thường được trigger ngầm (background) hoặc định kỳ chứ không chạy đồng bộ mỗi khi user trả lời 1 câu hỏi (để tiết kiệm resource).

```python
# Pseudo-code trong ProficiencyService
def calculate_proficiency(user_id):
    # 1. Fetch raw data
    exercises = fetch_last_90_days_exercises(user_id)
    
    # 2. Phân loại theo Skill
    skill_buckets = group_by_skill(exercises)
    
    # 3. Tính điểm từng Skill (Tích hợp Difficulty Multiplier)
    skill_scores = {}
    for skill, exercises in skill_buckets:
        accuracy = calculate_weighted_accuracy(exercises) # Ưu tiên bài làm gần đây
        volume_penalty = apply_volume_curve(len(exercises))
        skill_scores[skill] = base_score * accuracy * volume_penalty * difficulty
        
    # 4. Tính Overall Score (áp dụng Weights)
    overall_score = sum(skill_scores[k] * SKILL_WEIGHTS[k] for k in skills)
    
    # 5. Xác định Level
    current_level = map_score_to_cefr(overall_score, total_exercises, skill_scores)
    
    return ProficiencyProfile(current_level, overall_score, skill_scores)
```

---

## 5. Phân Tích Xu Hướng (Trend Analysis)

Service cũng phân tích độ cải thiện của user bằng cách so sánh 30 ngày gần nhất với 30 ngày trước đó.
- Sinh ra trường `trend`: `IMPROVING`, `STABLE`, hoặc `DECLINING`.
- Nếu user nghỉ học quá lâu (không có exercise mới), system áp dụng **Time Decay** (độ phai mòn), làm giảm nhẹ overall score mô phỏng việc quên kiến thức, có thể khiến user rớt hạng (ví dụ từ đầu B2 xuống cuối B1).

---

## 6. API Endpoints

1. `GET /api/v1/proficiency/` — Lấy profile hiện tại (spider chart data).
2. `POST /api/v1/proficiency/assess` — Force trigger tính toán lại (thường dùng khi user làm xong bài test định kỳ).
3. `GET /api/v1/proficiency/history` — Lấy biểu đồ lịch sử tăng trưởng điểm.

---

## 7. Tích Hợp Lên AI Service (GraphCAG)

Điểm Proficiency được xem là "Source of Truth" về trình độ của user:

```
[Backend Proficiency DB] ──(Sync)──► [AI Service Learner Profile]
```

Khi user chat, GraphCAG nhận `{"level": "B1", "weaknesses": ["listening", "grammar_past_tense"]}`.
Dữ liệu này được GraphCAG dùng để:
1. Quyết định độ khó của câu từ chối/phản hồi.
2. Quyết định có nên ngắt lời để sửa lỗi Grammar không (A1 sửa lỗi nhiều hơn C1).

---

*Tham khảo: [RPT-021](RPT-021_GRAPHCAG_ALGORITHM_FLOW.md), [RPT-025](RPT-025_GAMIFICATION_XP_SYSTEM.md)*
