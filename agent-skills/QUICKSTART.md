# LexiLingo Agent Skills - Quick Start

Get started with AI agent skills for language learning in 5 minutes.

## 📦 Installation

No installation needed! Skills are part of the LexiLingo repository.

```bash
cd /path/to/LexiLingo/agent-skills
```

## 🚀 Quick Usage

### For AI Agents (Claude, Copilot, etc.)

Skills are automatically available when working on LexiLingo. Just reference them naturally:

**Example prompts:**
```
"Implement spaced repetition for vocabulary review"
→ Agent references language-learning-patterns skill

"Add pronunciation feedback with phoneme analysis"
→ Agent references both skills

"Optimize audio sample rate for speech recognition"
→ Agent references speech-processing-best-practices skill
```

### For Developers

Browse skills for implementation patterns:

```bash
# View skill overview
cat skills/language-learning-patterns/SKILL.md

# Read specific rule
cat skills/language-learning-patterns/rules/srs-sm2-algorithm.md

# See all rules compiled
cat skills/language-learning-patterns/AGENTS.md
```

## 📚 Available Skills

### 1. Language Learning Patterns

6 rules for effective learning features:

- ✅ **SuperMemo-2 SRS** (CRITICAL) - Optimal review intervals
- ✅ **CEFR Leveling** (HIGH) - Difficulty grading A1-C2  
- ✅ **Learning Streaks** (HIGH) - Engagement through consistency
- ✅ **Phoneme Feedback** (MEDIUM) - Pronunciation scoring
- ✅ **Adaptive Difficulty** (HIGH) - Dynamic challenge adjustment
- ✅ **Achievement Badges** (MEDIUM) - Meaningful gamification

[View full skill →](./skills/language-learning-patterns/SKILL.md)

### 2. Speech Processing Best Practices

3 rules for quality speech features:

- ✅ **16kHz Sample Rate** (CRITICAL) - Optimal audio quality
- ✅ **SSML for TTS** (HIGH) - Natural prosody control
- ✅ **Streaming STT** (HIGH) - Real-time transcription

[View full skill →](./skills/speech-processing-best-practices/SKILL.md)

## 🔧 Building Skills

### Generate AGENTS.md files

```bash
# Build all skills
python3 build.py

# Build specific skill
python3 build.py language-learning-patterns

# With npm
npm run build
```

### Validate skills

```bash
# Check all skills for errors
python3 validate.py

# With npm
npm run validate
```

## 📝 Creating a New Rule

**Step 1:** Choose your skill and category

```bash
cd skills/language-learning-patterns/rules
```

**Step 2:** Copy template (or create from scratch)

```bash
cp _template.md adaptive-focus-weak-points.md
```

**Step 3:** Fill in the rule

```markdown
---
title: Focus on Learner's Weak Points
impact: HIGH
impactDescription: Targeted practice improves 50% faster
tags: adaptive-learning, personalization, weak-points
---

## Focus on Learner's Weak Points

**Impact: HIGH (50% faster improvement)**

Explanation of why this matters...

**Incorrect:**
\`\`\`typescript
// Bad code
\`\`\`

**Correct:**
\`\`\`typescript
// Good code
\`\`\`

Reference: [Link](https://example.com)
```

**Step 4:** Build to regenerate AGENTS.md

```bash
python3 build.py language-learning-patterns
```

## 💡 Examples

### Using SRS Algorithm

```typescript
import { SM2Card, calculateNextReview, ReviewQuality } from '@/lib/srs';

// Review a vocabulary card
const card: SM2Card = {
  word: "bonjour",
  easeFactor: 2.5,
  interval: 1,
  repetitions: 0,
  nextReview: new Date()
};

// User rates their recall
const quality = ReviewQuality.CORRECT_EASY; // 4

// Calculate next review
const updated = calculateNextReview(card, quality);
// → next review in 6 days
```

### Using CEFR Leveling

```typescript
import { CEFRLevel, getContentForLevel } from '@/lib/content';

// Get appropriate content for user
const userLevel = CEFRLevel.B1; // Intermediate
const content = await getContentForLevel(userLevel, 10);

// Returns:
// - 20% A2 (review)
// - 60% B1 (current level)
// - 20% B2 (challenge)
```

### Using 16kHz Audio

```typescript
import { recordHighQualityAudio } from '@/lib/audio';

// Record with optimal settings
const { blob, actualSampleRate } = await recordHighQualityAudio(5000);

// Process for STT
const transcription = await sttService.transcribe(blob);
```

## 🎯 Impact Levels

Rules are prioritized by impact:

| Level | Description | Example |
|-------|-------------|---------|
| **CRITICAL** | Core algorithms, major issues | SRS algorithm, sample rate |
| **HIGH** | Significant improvements | CEFR leveling, streaming STT |
| **MEDIUM** | Moderate enhancements | Phoneme feedback, badges |
| **LOW** | Incremental optimizations | UI polish |

## 🤝 Contributing

Want to add more rules? See [CONTRIBUTING.md](./CONTRIBUTING.md)

1. Fork the repository
2. Create a new rule following the template
3. Test with `python3 validate.py`
4. Build with `python3 build.py`
5. Submit a pull request

## 📖 Documentation

- [Main README](./README.md) - Full documentation
- [BUILD.md](./BUILD.md) - Build system details
- [SKILL.md files](./skills/) - Individual skill overviews
- [AGENTS.md files](./skills/) - Compiled comprehensive guides

## 🔗 Integration

These skills integrate with:

| Component | Usage |
|-----------|-------|
| **backend-service** | SRS algorithms, progress tracking |
| **ai-service** | Content generation, STT/TTS |
| **flutter-app** | UI patterns, gamification |
| **DL-Model-Support** | Speech models, training |

## 📊 Stats

- **2 Skills** covering 13 categories
- **9 Rules** with detailed examples
- **~3000 lines** of implementation patterns
- **Research-backed** with citations

## ❓ FAQ

**Q: Do I need to install anything?**  
A: Just Python 3.8+ for the build scripts.

**Q: How do AI agents use these?**  
A: They reference SKILL.md or AGENTS.md when relevant tasks are detected.

**Q: Can I use these in my own project?**  
A: Yes! MIT license. Use freely.

**Q: How do I request a new rule?**  
A: Open an issue with the topic and we'll add it.

## 🌟 Featured Rules

- **SuperMemo-2 SRS**: Scientifically-proven spaced repetition
- **CEFR Leveling**: International standard difficulty grading
- **Learning Streaks**: Proven engagement mechanic (3-5x retention)
- **16kHz Audio**: Optimal sample rate for STT accuracy
- **SSML Markup**: Natural TTS with prosody control
- **Adaptive Difficulty**: Keep users in flow state (60-80% efficiency)

## 🚀 Next Steps

1. Browse the [skills directory](./skills/)
2. Read the [full README](./README.md)
3. Try implementing a pattern from AGENTS.md
4. Share your results!

---

**Built for**: Claude Code, GitHub Copilot, Cursor, and other AI agents  
**Maintained by**: LexiLingo Team  
**License**: MIT
