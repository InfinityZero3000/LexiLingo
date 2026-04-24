# RPT-026 — SM-2 Spaced Repetition và Hệ Thống Từ Vựng

> **Cập nhật:** 2026-04-24 | **Nguồn:** `ai-service/api/services/spaced_repetition_service.py` (376 dòng), `backend-service/app/routes/vocabulary.py` (17KB)

---

## 1. Tổng Quan

LexiLingo triển khai thuật toán **SM-2 (SuperMemo 2)** — thuật toán spaced repetition nổi tiếng nhất trong giáo dục ngôn ngữ — để lên lịch ôn tập từ vựng cho người học. Hệ thống này được implement trong AI service (MongoDB), tách biệt với backend vocabulary API (PostgreSQL).

---

## 2. Thuật Toán SM-2

### 2.1 Nguyên Lý

SM-2 dựa trên nguyên tắc **"quên đường cong"** (forgetting curve) của Ebbinghaus: chúng ta nhớ thông tin tốt nhất khi ôn tập ngay trước khi quên nó. Mỗi lần ôn tập thành công sẽ kéo dài khoảng cách đến lần ôn tiếp theo.

```
Lần ôn 1 → 1 ngày sau
Lần ôn 2 → 6 ngày sau
Lần ôn 3 → 6 × EF ngày sau (EF = Easiness Factor)
Lần ôn N → Interval × EF ngày sau
```

### 2.2 Rating Quality (0-5)

Người học đánh giá mức độ nhớ sau mỗi lần ôn:

| Quality | Enum | Mô Tả |
|---------|------|--------|
| 0 | `BLACKOUT` | Hoàn toàn quên — không nhớ gì |
| 1 | `INCORRECT` | Sai nhưng nhớ ra sau khi xem gợi ý |
| 2 | `HARD` | Đúng nhưng rất khó (>=2 mới được tính là pass) |
| 3 | `GOOD` | Đúng với chút do dự |
| 4 | `EASY` | Đúng, nhớ dễ |
| 5 | `PERFECT` | Đúng ngay, không cần suy nghĩ |

### 2.3 Công Thức SM-2

```python
def _calculate_sm2(quality, ef, interval, repetitions):
    # Cập nhật Easiness Factor
    new_ef = ef + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    new_ef = max(1.3, new_ef)   # Tối thiểu EF = 1.3

    if quality < 3:             # Dưới ngưỡng GOOD → reset
        new_interval = 1
        new_reps = 0
    else:                       # Pass → tăng interval
        new_reps = repetitions + 1
        if new_reps == 1:
            new_interval = 1    # Day 1
        elif new_reps == 2:
            new_interval = 6    # Day 6
        else:
            new_interval = int(interval * new_ef)   # Exponential

    return new_ef, new_interval, new_reps
```

**Ví dụ với EF=2.5 (mặc định):**
- Ôn lần 1: Interval = 1 ngày
- Ôn lần 2: Interval = 6 ngày
- Ôn lần 3: Interval = 6 × 2.5 = 15 ngày
- Ôn lần 4: Interval = 15 × 2.5 = 37 ngày
- Ôn lần 5: Interval = 37 × 2.5 = 93 ngày (~3 tháng)

### 2.4 Mastery Score (0-1)

```python
def _calculate_mastery_score(mastery):
    accuracy = correct_count / total_reviews                          # 50% weight
    ef_factor = (easiness_factor - 1.3) / (2.5 + 1 - 1.3)          # 30% weight
    interval_factor = min(1.0, interval_days / 30)                   # 20% weight
    
    return accuracy * 0.5 + ef_factor * 0.3 + interval_factor * 0.2
```

---

## 3. ConceptMastery Model (MongoDB)

```python
class ConceptMastery:
    user_id: str
    concept_id: str           # ID của concept trong KuzuDB KG
    easiness_factor: float    # EF, default 2.5, min 1.3
    interval_days: int        # Khoảng cách đến lần ôn tiếp theo
    repetitions: int          # Số lần ôn tập thành công liên tiếp
    last_review: datetime     # Lần ôn gần nhất
    next_review: datetime     # Lần ôn tiếp theo (tính từ SM-2)
    last_quality: int         # Quality rating lần cuối (0-5)
    total_reviews: int        # Tổng số lần đã ôn
    correct_count: int        # Số lần trả lời đúng
```

Lưu trong MongoDB collection `spaced_repetition`.

---

## 4. API Spaced Repetition (AI Service)

### 4.1 Lấy Từ Cần Ôn
```
GET /api/v1/vocabulary/due-reviews?user_id={uid}&limit=10
```

Trả về danh sách concept đến hạn ôn, ưu tiên theo `priority`:
```python
# Priority = overdue_days + (1 / easiness_factor)
# Càng overdue và càng khó → priority cao hơn → ôn trước
items.sort(key=lambda x: x.priority, reverse=True)
```

### 4.2 Ghi Nhận Kết Quả Ôn
```
POST /api/v1/vocabulary/record-review
{
    "user_id": "uid",
    "concept_id": "grammar_present_perfect",
    "quality": 4  # 0-5
}
```

Response:
```json
{
    "concept_id": "grammar_present_perfect",
    "quality": 4,
    "new_interval": 15,
    "next_review": "2026-05-09T00:00:00Z",
    "mastery_change": 0.12
}
```

### 4.3 Tổng Hợp Mastery
```
GET /api/v1/vocabulary/mastery-summary?user_id={uid}
```

```json
{
    "total_concepts": 47,
    "avg_easiness": 2.31,
    "total_reviews": 203,
    "accuracy": 0.84
}
```

---

## 5. Vocabulary Backend API (PostgreSQL)

Tách biệt với AI service, quản lý từ vựng trong context học tập:

| Method | Endpoint | Mô Tả |
|--------|---------|--------|
| GET | `/api/v1/vocabulary/` | Danh sách từ vựng của user |
| POST | `/api/v1/vocabulary/` | Thêm từ vào danh sách học |
| DELETE | `/api/v1/vocabulary/{id}` | Xóa từ |
| GET | `/api/v1/vocabulary/flashcards` | Lấy flashcards để review |
| POST | `/api/v1/vocabulary/flashcards/review` | Submit kết quả flashcard |
| GET | `/api/v1/vocabulary/stats` | Thống kê từ vựng |

---

## 6. Tích Hợp Với GraphCAG

Spaced repetition tích hợp với KuzuDB Knowledge Graph:

```
GraphCAG phân tích lỗi user
    │
    ├─ Phát hiện: user hay nhầm Present Perfect vs Past Simple
    ├─ Gọi: SpacedRepetitionService.seed_concepts_for_user(
    │         user_id, ["grammar_present_perfect", "grammar_past_simple"])
    └─ Từ hôm nay, system sẽ lên lịch ôn tập 2 concepts này cho user
```

```
User mở FlashcardReviewScreen
    │
    ├─ GET /vocabulary/due-reviews → 10 concepts cần ôn
    ├─ Hiển thị flashcard lần lượt
    ├─ User chọn quality (Easy/Good/Hard/Again)
    └─ POST /vocabulary/record-review → SM-2 tính next_review
```

---

## 7. Flutter Integration

### 7.1 Màn Hình

| Screen | Mô Tả |
|--------|--------|
| `FlashcardReviewScreen` | Ôn flashcard theo SM-2 |
| `SessionCompleteScreen` | Báo cáo sau phiên ôn tập |
| `VocabularyListScreen` | Danh sách từ đang học |

### 7.2 Provider

`VocabularyProvider` trong `features/vocabulary`:
- `getDueReviews()` → gọi AI service
- `submitReview(conceptId, quality)` → ghi kết quả
- `getMasterySummary()` → hiển thị progress

---

## 8. Mastery Summary Dashboard

Trong `MyProgressScreen`, người dùng thấy:

| Metric | Mô Tả |
|--------|--------|
| Total Concepts | Số concept đang track |
| Average Accuracy | % câu trả lời đúng tổng thể |
| Average Easiness | EF trung bình (2.5 là tốt, <1.5 là cần chú ý) |
| Due Today | Số concept cần ôn hôm nay |
| Mastered | Số từ đã ôn ≥30 ngày (interval ≥30) |

---

*Tham khảo: [RPT-021](RPT-021_GRAPHCAG_ALGORITHM_FLOW.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-027](RPT-027_PROFICIENCY_CEFR_ASSESSMENT.md)*
