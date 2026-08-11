# LexiLingo — Multi-Agent Coordination

## Agent Roles

| Agent | File | Trigger |
|-------|------|---------|
| Code Reviewer | `.claude/agents/code-reviewer.md` | After any non-trivial change |
| Test Writer | `.claude/agents/test-writer.md` | New feature or bug fix |
| Security Reviewer | `.claude/agents/security-reviewer.md` | Auth, API, DB schema changes |
| Kaiser | `.claude/agents/kaiser.md` | Technical debt audits, pre-sprint cleanup, when a service feels "heavy" |

## Ownership Map

| Area | Owner agent | Notes |
|------|-------------|-------|
| `flutter-app/` | main Claude | UI + state |
| `backend-service/api/` | main Claude | FastAPI routes, models |
| `backend-service/scripts/` | main Claude | Seed scripts (idempotent) |
| `ai-service/` | main Claude | AI pipeline, STT |
| Tests | test-writer | Never let main agent skip tests |
| Security surface | security-reviewer | Routes, auth middleware, env vars |
| Technical debt | kaiser | Debt register, architecture violations, dead code, complexity hotspots |

## Coordination Protocol

1. **Plan first** — use `sequential-thinking` MCP for tasks spanning >2 files or services.
2. **Graph before grep** — always query `code-review-graph` before opening files.
3. **Spawn test-writer** after every feature implementation.
4. **Spawn security-reviewer** when touching: auth routes, JWT handling, DB migrations, env/config files.
5. **Spawn code-reviewer** before any PR — use `/code-review` skill.
6. **Spawn kaiser** for quarterly debt audits, before major refactors, or when a module starts accumulating complexity.

## Task Decomposition (Large Tasks)

For tasks like "implement STT streaming":
```
1. Main agent: architecture plan using sequential-thinking
2. Main agent: implement core changes
3. test-writer: write unit + integration tests
4. security-reviewer: review new endpoints
5. code-reviewer: final review + PR comment
```

## Shared Memory

Agents write findings to the `memory` MCP knowledge graph:
- Entity type `Bug`: bugs found during review
- Entity type `Decision`: architectural decisions with rationale
- Entity type `TodoItem`: deferred work flagged during review

Query before starting: `memory.search_nodes("LexiLingo")` to load prior context.

## Do NOT

- Spawn agents for tasks under 30 min of single-agent work.
- Have two agents edit the same file concurrently.
- Skip the test-writer for any new public API endpoint.
- Commit without running `flutter analyze` (Flutter) or `pytest` (backend).

<!-- ASTRYX:START -->
Astryx v0.1.3 · 90+ components
CLI: run every command as `npx astryx <cmd>` (shown below as `astryx ...`).

SETUP (once, in your app entry e.g. main.tsx) — without these, components render unstyled:
  import "@astryxdesign/core/reset.css";
  import "@astryxdesign/core/astryx.css";

WORKFLOW — discover, don't guess. Before writing UI:
1. `astryx build "<idea>"` — START HERE: returns a kit (closest [page] + [block]s + [component]s). No args = full playbook.
2. `astryx template <name> [--skeleton]` — scaffold the [page]/[block]s it named, or study their layout. Templates are reference code.
3. `astryx component <Name>` — props + examples for every component you use.

RULES:
- No <div> — components do all layout/spacing. Full page → AppShell; sidebar nav → SideNav.
- Frame first: pick the shell (AppShell / Layout+LayoutPanel) and budget regions in px BEFORE writing content (`astryx docs layout`).
- Dense data = rows (Table, List/Item) edge-to-edge — never Card-wrapped list items. Card = dashboard widgets, galleries, settings groups only.
- Status → StatusDot/Token; Badge only for counts and enumerated states, never decoration.
- Custom styling: component props first; else style/className with tokens — var(--color-*|--spacing-*|--radius-*). No raw hex/px. (No StyleX/Tailwind compiler here — don't use xstyle/utility classes.)
- Tokens for every value (`astryx docs tokens`). Brand/accent via `astryx theme` — never override --color-* in :root.

MORE CLI:
  search "<query>"   find any component / hook / doc / template / block
  component --list   90+ components by category
  template --list    page + block recipes
  docs <topic>       color, elevation, icons, illustrations, layout, migration, motion, principles, shape, spacing, styling, theme, tokens, typography
  swizzle <Name>     eject component source for deep customization
  upgrade --apply    run after any @astryxdesign/core bump
<!-- ASTRYX:END -->
