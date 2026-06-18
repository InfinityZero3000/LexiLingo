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
