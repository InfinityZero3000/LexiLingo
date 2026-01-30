# 📋 LexiLingo - Remaining Features Documentation

> **Ngày tạo**: 30/01/2026  
> **Mục tiêu**: Tài liệu chi tiết các features chưa implement và kế hoạch thực hiện

---

## 📊 Tổng Quan Features Đã Có

### ✅ Core Features (Hoàn thành)
| Feature | Backend | Flutter | Status |
|---------|---------|---------|--------|
| Authentication (JWT + Google) | ✅ | ✅ | Production |
| Course System | ✅ | ✅ | Production |
| Learning Sessions | ✅ | ✅ | Production |
| Vocabulary & Flashcards | ✅ | ✅ | Production |
| AI Chat (Gemini) | ✅ | ✅ | Production |
| Voice STT/TTS | ✅ | ✅ | Production |
| TTS Speed Controls | ✅ | ✅ | Production |

### ✅ Gamification (Hoàn thành)
| Feature | Backend | Flutter | Status |
|---------|---------|---------|--------|
| Streak System | ✅ | ✅ | Production |
| Daily Challenges | ✅ | ✅ | Production |
| XP & Levels | ✅ | ✅ | Production |

### ✅ Infrastructure (Hoàn thành)
| Feature | Backend | Flutter | Status |
|---------|---------|---------|--------|
| Firebase Configuration | ✅ | ✅ | Production |
| Skeleton Loading | - | ✅ | Production |
| Error Handling UI | - | ✅ | Production |
| Pull-to-Refresh | - | ✅ | Production |

---

## 🔴 Features Chưa Implement (Priority: HIGH)

### 1. Achievement/Badge System
**Độ phức tạp**: 🔴 High  
**Impact**: High - Tăng user engagement đáng kể

#### 1.1 Backend Tasks
- [x] Model Achievement, UserAchievement (đã có)
- [x] CRUD operations (đã có)
- [x] API endpoints GET /achievements (đã có)
- [ ] **Achievement Checker Service** - Logic tự động kiểm tra điều kiện
- [ ] **Trigger System** - Khi nào check achievements
- [ ] API endpoint POST /achievements/check - Force check
- [ ] Seed thêm achievements data (hiện chỉ có 3)

#### 1.2 Achievement Types Cần Implement
| Type | Condition | Example |
|------|-----------|---------|
| `lesson_complete` | Hoàn thành N lessons | First Steps (1), Scholar (10), Professor (100) |
| `reach_streak` | Đạt streak N ngày | Week Warrior (7), Month Master (30), Year Legend (365) |
| `vocab_mastered` | Master N từ vựng | Vocab Starter (10), Vocab Master (100), Polyglot (1000) |
| `perfect_score` | N lần điểm tuyệt đối | Perfectionist (1), Perfect 10 (10) |
| `xp_earned` | Tích lũy N XP | XP Hunter (100), XP Champion (1000) |
| `voice_practice` | Luyện phát âm N lần | Voice Starter (10), Voice Pro (100) |
| `course_complete` | Hoàn thành N khóa học | Graduate (1), Multi-Lingual (5) |

#### 1.3 Flutter Tasks
- [ ] Tạo `features/achievements/` module
- [ ] AchievementEntity, AchievementModel
- [ ] AchievementRepository + DataSource
- [ ] AchievementProvider
- [ ] AchievementsScreen (Grid badges)
- [ ] BadgeUnlockPopup (với confetti animation)
- [ ] Tích hợp vào Profile screen

#### 1.4 Thuật Toán Achievement Checker
```python
class AchievementChecker:
    """
    Stateless service to check achievement conditions.
    Called after specific user actions.
    """
    
    async def check_all(user_id: UUID) -> List[Achievement]:
        """Check all achievements for user, return newly unlocked"""
        
    async def check_by_trigger(user_id: UUID, trigger: str) -> List[Achievement]:
        """Check only achievements related to trigger type"""
        # Triggers: lesson_complete, streak_update, vocab_review, etc.
        
    async def evaluate_condition(user_id: UUID, achievement: Achievement) -> bool:
        """Evaluate single achievement condition"""
        # Based on condition_type:
        # - lesson_complete: count user's completed lessons >= condition_value
        # - reach_streak: current_streak >= condition_value
        # - vocab_mastered: count mastered words >= condition_value
        # etc.
```

---

### 2. Leaderboard System
**Độ phức tạp**: 🟡 Medium  
**Impact**: High - Competitive motivation

#### 2.1 Backend Tasks
- [x] Model LeaderboardEntry (đã có)
- [x] API endpoint GET /leaderboard (đã có)
- [ ] Weekly reset logic
- [ ] League promotion/demotion
- [ ] Friends-only filter

#### 2.2 Flutter Tasks
- [ ] LeaderboardScreen
- [ ] LeaderboardProvider
- [ ] User rank widget on Home

---

### 3. Onboarding Flow
**Độ phức tạp**: 🟢 Low  
**Impact**: Medium - Better first impression

#### 3.1 Flutter Tasks
- [ ] OnboardingScreen (4-5 slides)
- [ ] Language selection
- [ ] Level assessment mini-quiz
- [ ] Daily goal setting
- [ ] Store completion flag

---

### 4. Shop & Inventory
**Độ phức tạp**: 🟡 Medium  
**Impact**: Medium - Monetization potential

#### 4.1 Backend (đã có models)
- [x] ShopItem, UserInventory models
- [x] Purchase endpoints
- [ ] Use item logic (streak freeze, double XP)

#### 4.2 Flutter Tasks
- [ ] ShopScreen
- [ ] InventoryWidget
- [ ] Use item flow

---

### 5. Advanced Learning Modules
**Độ phức tạp**: 🔴 High  
**Impact**: High - Core learning value

#### 5.1 Grammar Practice
- [ ] Grammar exercise types
- [ ] Fill-in-blank UI
- [ ] Sentence reordering

#### 5.2 Writing Practice
- [ ] Writing prompt generator
- [ ] AI feedback integration
- [ ] Correction display

#### 5.3 Reading Comprehension
- [ ] Passage display
- [ ] Vocabulary highlighting
- [ ] Comprehension questions

---

## 📅 Implementation Priority

### Sprint 1: Achievement System (This Session)
1. ✅ Document features
2. 🔄 Backend: AchievementCheckerService
3. 🔄 Backend: Seed more achievements
4. 🔄 Backend: Trigger integration
5. 🔄 Flutter: Achievement module
6. 🔄 Test: Verify badge unlocking

### Sprint 2: Leaderboard + Onboarding
- Leaderboard Flutter UI
- Onboarding flow

### Sprint 3: Shop + Content
- Shop/Inventory Flutter
- More course content

---

## 🔧 Technical Decisions

### Achievement Trigger Points
1. **After lesson complete** → check lesson_complete, xp_earned
2. **After streak update** → check reach_streak
3. **After vocab review** → check vocab_mastered
4. **After quiz perfect** → check perfect_score
5. **After voice practice** → check voice_practice
6. **After course complete** → check course_complete

### Badge Unlock Flow
```
User Action → API → Update DB → Call AchievementChecker 
    → If new unlock → Save UserAchievement → Return in response
    → Flutter shows popup with confetti
```

---

*Cập nhật: 30/01/2026*
