# LexiLingo Agent Skills

AI agent skills for building effective language learning applications. This repository contains reusable best practices and patterns optimized for AI coding assistants working on the LexiLingo project.

## 🎯 What are Skills?

Skills are packaged knowledge and guidelines that help AI agents make better decisions when building specific types of features. Each skill contains:
- **SKILL.md**: Overview and quick reference for AI agents
- **Rules**: Detailed implementation patterns with code examples
- **Metadata**: Version info and references

Skills follow the [skills.sh](https://skills.sh/) format and can be used with Claude Code, GitHub Copilot, Cursor, and other AI coding assistants.

## 📦 Available Skills

### 1. [Language Learning Patterns](./skills/language-learning-patterns/)

Best practices for building engaging and effective language learning features.

**Use when:**
- Implementing spaced repetition systems
- Building vocabulary exercises
- Creating progress tracking features
- Designing adaptive difficulty systems
- Implementing pronunciation feedback

**Key topics:**
- ✅ SuperMemo-2 algorithm for optimal review intervals
- ✅ CEFR difficulty leveling (A1-C2)
- ✅ Streak tracking with protections
- ✅ Phoneme-level pronunciation feedback
- ✅ Gamification and engagement mechanics

[View full skill →](./skills/language-learning-patterns/SKILL.md)

---

### 2. [Speech Processing Best Practices](./skills/speech-processing-best-practices/)

Technical guidelines for implementing high-quality speech features.

**Use when:**
- Integrating STT (Speech-to-Text) services
- Implementing TTS (Text-to-Speech) features
- Building pronunciation assessment
- Optimizing audio quality
- Handling voice recordings

**Key topics:**
- ✅ 16kHz+ sample rate for speech recognition
- ✅ SSML for natural TTS prosody
- ✅ Audio preprocessing and noise reduction
- ✅ Pronunciation scoring algorithms
- ✅ Performance optimization strategies

[View full skill →](./skills/speech-processing-best-practices/SKILL.md)

---

### 3. [Flutter Clean Architecture](./skills/flutter-clean-architecture/) ✨ New

Domain/Data/Presentation layer patterns for all LexiLingo Flutter features.

**Use when:**
- Creating any new feature (Notifications, Level, User Stats, Course Categories)
- Adding a repository, use case, or Provider to an existing feature
- Ensuring entities don't contain `fromJson` / no data leaking into widgets

**Key topics:**
- ✅ Domain entity + `Equatable` pattern (no serialization in domain)
- ✅ Abstract repository interface (domain) + concrete impl (data)
- ✅ Single-responsibility use case call objects
- ✅ `ChangeNotifier` Provider with `isLoading` / `error` / `data` triad
- ✅ Exception → typed `Failure` mapping at repository boundary
- ✅ Complete `LevelCalculator` with A1–C2 XP thresholds

[View full skill →](./skills/flutter-clean-architecture/SKILL.md)

---

### 4. [Flutter UI Animations](./skills/flutter-ui-animations/) ✨ New

60fps animation patterns for shimmer skeletons, staggered lists, Hero transitions, and the Level-Up celebration dialog.

**Use when:**
- Adding shimmer loading skeletons to Home, Profile, or Course List
- Implementing staggered entry animations for list/card content
- Building Hero shared-element transitions between course card and detail
- Triggering the Level-Up celebration on XP milestone

**Key topics:**
- ✅ `shimmer` package skeleton cards matching real widget dimensions
- ✅ Staggered FadeSlide entry with 50ms per-item delay, capped at 300ms
- ✅ Hero tag pattern: `'course-hero-${course.id}'` (never hardcoded)
- ✅ Level-Up dialog: `ScaleTransition` + `Curves.elasticOut` + auto-dismiss
- ✅ `RepaintBoundary` and `AnimatedBuilder` child-hoisting for 60fps

[View full skill →](./skills/flutter-ui-animations/SKILL.md)

---

### 5. [FastAPI LexiLingo Endpoints](./skills/fastapi-lexilingo-endpoints/) ✨ New

Backend endpoint conventions, Pydantic v2 schemas, async SQLAlchemy queries, and Alembic migration workflow.

**Use when:**
- Adding new routes to `backend-service/app/routes/`
- Creating Pydantic schemas or service classes
- Writing async SQLAlchemy 2.0 queries
- Running Alembic migrations for new models

**Key topics:**
- ✅ `ApiResponse[T]` envelope — every endpoint returns this shape
- ✅ Always `async/await` with `AsyncSession` (never sync)
- ✅ Service-layer pattern — no DB queries in route functions
- ✅ Existing endpoint map (check before adding duplicates)
- ✅ Alembic `--autogenerate` → review → `upgrade head` workflow

[View full skill →](./skills/fastapi-lexilingo-endpoints/SKILL.md)

---

### 6. [Flutter Notification System](./skills/flutter-notification-system/) ✨ New

FCM integration gaps for the existing notification feature (domain/data/provider layers already done).

**Use when:**
- Wiring up FCM background/terminated message handling
- Registering the FCM device token with the backend after login
- Displaying heads-up banners when a message arrives while app is open
- Implementing swipe-to-delete with Undo on the notifications page

**Key topics:**
- ✅ `@pragma('vm:entry-point')` on background handler (prevents release build tree-shaking)
- ✅ FCM token → `POST /api/devices/token` with dedup via `SharedPreferences`
- ✅ `flutter_local_notifications` foreground display with `Importance.high` channel
- ✅ `Dismissible` + `ValueKey` + `SnackBar` Undo pattern

[View full skill →](./skills/flutter-notification-system/SKILL.md)

---

## 🚀 Quick Start

### For AI Agents

These skills are automatically loaded when working on LexiLingo. Just reference them naturally:

```
"Implement a spaced repetition system for vocabulary review"
→ Agent will reference language-learning-patterns skill

"Add pronunciation feedback for speaking exercises"  
→ Agent will reference both skills
```

### For Developers

Browse the skills to understand best practices:

```bash
# Read language learning patterns
cat agent-skills/skills/language-learning-patterns/SKILL.md

# View specific rule
cat agent-skills/skills/language-learning-patterns/rules/srs-sm2-algorithm.md
```

### Install with skills CLI

If you're using an AI agent that supports skills.sh:

```bash
npx skills add InfinityZero3000/LexiLingo/agent-skills
```

## 📖 Skill Structure

Each skill follows this structure:

```
skills/
  {skill-name}/
    SKILL.md              # Overview and quick reference
    README.md             # Human-readable documentation
    metadata.json         # Version and metadata
    rules/
      _sections.md        # Category definitions
      _template.md        # Template for new rules
      {category}-{name}.md # Individual rule files
```

## 🎨 Rule Categories

### Language Learning Patterns
- **Spaced Repetition** (CRITICAL): Memory retention algorithms
- **Content Generation** (HIGH): CEFR leveling, examples, audio
- **Progress Tracking** (HIGH): Streaks, XP, milestones
- **Adaptive Learning** (HIGH): Difficulty adjustment, weak points
- **Pronunciation** (MEDIUM): Phoneme feedback, speech analysis
- **Gamification** (MEDIUM): Badges, leaderboards, rewards
- **Accessibility** (MEDIUM): Inclusive design patterns

### Speech Processing
- **Audio Quality** (CRITICAL): Sample rates, formats, preprocessing
- **STT Optimization** (HIGH): Streaming vs batch, confidence thresholds
- **TTS Implementation** (HIGH): Neural voices, SSML, caching
- **Pronunciation** (HIGH): Assessment APIs, alignment, metrics
- **Performance** (MEDIUM): Compression, VAD, offline support
- **Error Handling** (MEDIUM): Permissions, network, timeouts

## 🔧 Integration with LexiLingo

These skills integrate with all LexiLingo components:

| Component | Relevant Skills |
|-----------|----------------|
| **backend-service** | Language Learning (progress tracking, SRS) |
| **ai-service** | Both (content generation, STT/TTS) |
| **flutter-app** | Language Learning (UI patterns, gamification) |
| **DL-Model-Support** | Speech Processing (custom models, training) |

## 📝 Creating New Rules

Want to add a new best practice? Follow this process:

1. Choose the appropriate skill directory
2. Copy `rules/_template.md` to `rules/{category}-{description}.md`
3. Fill in:
   - Title and impact level
   - Explanation of why it matters
   - **Incorrect** example (anti-pattern)
   - **Correct** example (best practice)
   - References and additional tips
4. Update `SKILL.md` quick reference if needed

Example:

```bash
cd agent-skills/skills/language-learning-patterns/rules
cp _template.md adaptive-focus-weak-points.md
# Edit the file...
```

## 🎯 Impact Levels

Rules are prioritized by impact on learning outcomes:

- **CRITICAL**: Core algorithms, major UX issues (e.g., SRS algorithm)
- **HIGH**: Significant impact on engagement/learning (e.g., streaks, CEFR)
- **MEDIUM**: Moderate improvements (e.g., pronunciation feedback)
- **LOW**: Incremental optimizations

## 🧪 Testing

When implementing rules from these skills:

1. **Measure baseline** - Capture current metrics
2. **Implement pattern** - Follow the correct example
3. **A/B test** - Compare with control group
4. **Validate impact** - Verify the claimed improvement

Example metrics:
- Retention rate (30-day active users)
- Daily active users (DAU)
- Time to proficiency milestones
- User satisfaction scores

## 📚 References

### Language Learning
- [SuperMemo Research](https://www.supermemo.com/en/archives1990-2015/english/ol/sm2)
- [CEFR Framework](https://www.coe.int/en/web/common-european-framework-reference-languages)
- [Duolingo Research Blog](https://blog.duolingo.com/research/)
- [Anki Documentation](https://docs.ankiweb.net/)

### Speech Processing
- [Google Cloud Speech-to-Text](https://cloud.google.com/speech-to-text/docs)
- [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- [SSML Specification](https://www.w3.org/TR/speech-synthesis11/)
- [IPA Phonetic Alphabet](https://www.internationalphoneticassociation.org/content/full-ipa-chart)

### EdTech & Gamification
- [Nir Eyal - Hooked Model](https://www.nirandfar.com/hooked/)
- [Cognitive Load Theory](https://www.instructionaldesign.org/theories/cognitive-load/)

## 🤝 Contributing

To contribute new skills or rules:

1. Fork the repository
2. Create a feature branch
3. Add your skill/rule following the structure
4. Test with an AI agent to ensure it's useful
5. Submit a pull request

Guidelines:
- Provide concrete code examples (not pseudo-code)
- Include both incorrect and correct patterns
- Cite research or sources when available
- Keep rules focused (one pattern per file)
- Test examples work in actual codebase

## 📄 License

MIT License - Use these skills freely in your projects

## 🔗 Related

- [Main LexiLingo Repository](../)
- [skills.sh - Agent Skills Ecosystem](https://skills.sh/)
- [Backend Service Documentation](../backend-service/)
- [AI Service Documentation](../ai-service/)

---

**Built for**: Claude Code, GitHub Copilot, Cursor, and other AI coding assistants  
**Maintained by**: LexiLingo Team  
**Version**: 1.0.0
