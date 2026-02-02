# Agent Skills Build System

Python build system for compiling skill rules into AGENTS.md documents.

## Installation

```bash
# Python 3.8+ required
python3 --version
```

## Usage

### Build all skills

```bash
python3 build.py
```

### Build specific skill

```bash
python3 build.py language-learning-patterns
python3 build.py speech-processing-best-practices
```

### With npm scripts

```bash
npm run build              # Build all skills
npm run build:skill -- language-learning-patterns
```

## Output

Each skill generates an `AGENTS.md` file in its directory:
- `skills/language-learning-patterns/AGENTS.md`
- `skills/speech-processing-best-practices/AGENTS.md`

## Skill Structure

```
skills/
  {skill-name}/
    SKILL.md              # Overview for AI agents
    README.md             # Human documentation
    metadata.json         # Version and metadata
    AGENTS.md            # Generated comprehensive guide
    rules/
      _sections.md        # Section definitions
      _template.md        # Rule template
      {category}-{name}.md # Rule files
```

## Rule File Format

```markdown
---
title: Rule Title
impact: HIGH
impactDescription: Brief impact description
tags: tag1, tag2, tag3
---

## Rule Title

**Impact: HIGH (impact description)**

Explanation of the rule...

**Incorrect (what not to do):**

\`\`\`typescript
// Bad code
\`\`\`

**Correct (best practice):**

\`\`\`typescript
// Good code
\`\`\`

Reference: [Link](https://example.com)
```

## Creating New Rules

1. Copy template:
   ```bash
   cp skills/{skill-name}/rules/_template.md \
      skills/{skill-name}/rules/{category}-{description}.md
   ```

2. Edit the file with your content

3. Build to regenerate AGENTS.md:
   ```bash
   python3 build.py {skill-name}
   ```

## Impact Levels

- **CRITICAL**: Core algorithms, major issues
- **HIGH**: Significant improvements
- **MEDIUM**: Moderate enhancements
- **LOW**: Incremental optimizations

## License

MIT
