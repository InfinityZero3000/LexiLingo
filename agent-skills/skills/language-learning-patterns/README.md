# Language Learning Patterns

Best practices for building effective language learning applications optimized for AI agents and developers.

## Structure

- `rules/` - Individual rule files (one per rule)
  - `_sections.md` - Section metadata (titles, impacts, descriptions)
  - `_template.md` - Template for creating new rules
  - `[category]-[description].md` - Individual rule files
- `metadata.json` - Document metadata (version, organization, abstract)
- **`AGENTS.md`** - Compiled output (generated)
- **`SKILL.md`** - Skill definition for AI agents

## Rule Categories

### 1. Spaced Repetition (CRITICAL)
- SuperMemo-2 algorithm implementation
- Ease factor management
- Review scheduling optimization
- Lapse handling strategies

### 2. Content Generation (HIGH)
- CEFR difficulty leveling (A1-C2)
- Context-rich example sentences
- Native speaker audio integration
- Cultural context annotations

### 3. Progress Tracking (HIGH)
- Learning streak systems with protections
- Experience point mechanics
- Milestone celebrations
- Time tracking and analytics

### 4. Adaptive Learning (HIGH)
- Dynamic difficulty adjustment
- Weak point identification
- Review prioritization
- Personalized learning pace

### 5. Pronunciation (MEDIUM)
- Phoneme-level feedback
- Pitch and tone analysis
- Visual pronunciation aids
- Recording comparison tools

### 6. Gamification (MEDIUM)
- Achievement badge systems
- Leaderboards and social features
- Daily goal tracking
- Reward mechanisms

### 7. Accessibility (MEDIUM)
- Dyslexia-friendly design
- Keyboard navigation
- Screen reader support
- Visual impairment accommodations

## Creating a New Rule

1. Copy `rules/_template.md` to `rules/[category]-[description].md`
2. Choose the appropriate category prefix:
   - `srs-` for Spaced Repetition
   - `content-` for Content Generation
   - `progress-` for Progress Tracking
   - `adaptive-` for Adaptive Learning
   - `pronunciation-` for Pronunciation
   - `gamification-` for Gamification
   - `accessibility-` for Accessibility
3. Fill in the frontmatter (title, impact, tags)
4. Write clear explanations with code examples
5. Include both incorrect and correct implementations
6. Add references to research or documentation

## Rule File Structure

Each rule should include:
- **Frontmatter**: Title, impact level, impact description, tags
- **Explanation**: Why this rule matters for language learning
- **Incorrect example**: Anti-pattern with explanation
- **Correct example**: Best practice implementation
- **Additional tips**: Edge cases, advanced features
- **References**: Links to research, docs, or examples

## Impact Levels

- `CRITICAL` - Core algorithms, causes major UX/retention issues
- `HIGH` - Significant impact on learning outcomes or engagement
- `MEDIUM` - Moderate improvements to experience or efficiency
- `LOW` - Incremental optimizations

## Integration with LexiLingo

These patterns are designed to work with:
- **Backend Service** (FastAPI): User progress, analytics, API endpoints
- **AI Service** (Gemini): Content generation, pronunciation analysis
- **Flutter App**: UI/UX implementation, gamification
- **DL Models**: Speech recognition, NLP processing

## Usage

This skill is automatically available to AI agents working on the LexiLingo project. Agents will reference these patterns when:
- Implementing new learning features
- Optimizing existing algorithms
- Debugging user engagement issues
- Designing educational content flow

## Contributing

When adding rules:
1. Use the filename pattern: `[category]-[description].md`
2. Follow the template structure
3. Include realistic code examples
4. Cite research where applicable
5. Test examples before committing

## License

MIT - Use these patterns freely in your language learning projects
