---
title: Use SuperMemo-2 Algorithm for Optimal Review Intervals
impact: CRITICAL
impactDescription: Scientifically proven to improve retention by 200-300% vs fixed intervals
tags: spaced-repetition, srs, memory, algorithm
---

## Use SuperMemo-2 Algorithm for Optimal Review Intervals

**Impact: CRITICAL (200-300% retention improvement)**

The SuperMemo-2 (SM-2) algorithm is the gold standard for spaced repetition systems. It calculates optimal review intervals based on user performance, maximizing long-term retention while minimizing study time. Using fixed intervals or arbitrary scheduling significantly reduces learning efficiency.

**Incorrect (Fixed interval approach):**

```typescript
// Anti-pattern: Fixed review intervals
interface VocabularyCard {
  word: string;
  nextReview: Date;
}

function scheduleNextReview(card: VocabularyCard, correct: boolean): Date {
  // Fixed intervals: 1 day, 3 days, 7 days, 14 days...
  const fixedIntervals = [1, 3, 7, 14, 30];
  const currentIndex = 0; // Track somehow
  
  if (correct) {
    const daysToAdd = fixedIntervals[currentIndex] || 30;
    return new Date(Date.now() + daysToAdd * 24 * 60 * 60 * 1000);
  }
  
  // Reset to day 1 if incorrect
  return new Date(Date.now() + 24 * 60 * 60 * 1000);
}
```

**Why this is incorrect:** 
- Fixed intervals don't adapt to individual card difficulty
- No differentiation between "easy" and "hard" correct answers
- Inefficient for both easy and difficult content
- Doesn't account for memory strength variations
- Poor long-term retention outcomes

**Correct (SM-2 algorithm implementation):**

```typescript
// Best practice: SuperMemo-2 algorithm
interface SM2Card {
  word: string;
  easeFactor: number;    // 1.3 to 2.5, default 2.5
  interval: number;       // Days until next review
  repetitions: number;    // Consecutive correct reviews
  nextReview: Date;
}

enum ReviewQuality {
  COMPLETE_BLACKOUT = 0,  // Complete failure
  INCORRECT_RECALLED = 1,  // Incorrect but remembered
  DIFFICULT_CORRECT = 2,   // Correct with difficulty
  CORRECT_HESITANT = 3,    // Correct after hesitation
  CORRECT_EASY = 4,        // Correct with some effort
  PERFECT = 5              // Perfect response
}

function calculateNextReview(
  card: SM2Card,
  quality: ReviewQuality
): SM2Card {
  let { easeFactor, interval, repetitions } = card;
  
  // Update ease factor (memory strength)
  easeFactor = Math.max(
    1.3,
    easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
  );
  
  // Calculate next interval
  if (quality < 3) {
    // Failed review: reset but keep ease factor
    repetitions = 0;
    interval = 1;
  } else {
    // Successful review: increase interval
    repetitions += 1;
    
    if (repetitions === 1) {
      interval = 1;
    } else if (repetitions === 2) {
      interval = 6;
    } else {
      interval = Math.round(interval * easeFactor);
    }
  }
  
  return {
    ...card,
    easeFactor,
    interval,
    repetitions,
    nextReview: new Date(Date.now() + interval * 24 * 60 * 60 * 1000)
  };
}

// Usage example
function reviewCard(card: SM2Card, userRating: ReviewQuality): SM2Card {
  const updatedCard = calculateNextReview(card, userRating);
  
  // Save to database
  return updatedCard;
}
```

**Why this is better:**
- Adapts interval length based on individual card difficulty
- Easy cards reviewed less frequently, hard cards more often
- Ease factor tracks long-term memory strength
- Quality rating (0-5) captures nuance in recall difficulty
- Scientifically proven to optimize retention/time ratio
- Handles lapses intelligently without full reset

**Implementation tips:**
1. Store `easeFactor`, `interval`, and `repetitions` for each card
2. Present quality scale (0-5) clearly to users
3. Consider fuzzing intervals (±10%) to prevent review bunching
4. Cap maximum interval (e.g., 365 days) for very easy cards
5. Track first-time vs review cards separately

**Advanced enhancements:**
- Add "Hard" button that repeats card in same session
- Implement "bury" feature for related cards
- Use load balancing to distribute daily reviews evenly
- Consider time-of-day effects on memory performance

Reference: [SuperMemo-2 Algorithm](https://www.supermemo.com/en/archives1990-2015/english/ol/sm2) | [Anki Implementation](https://faqs.ankiweb.net/what-spaced-repetition-algorithm.html)
