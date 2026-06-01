# LexiLingo Coding-Time MCP Server

Model Context Protocol server strictly meant for **IDE assistance** (Cursor, Copilot CLI, Claude Desktop).

> **Note**: For actual app runtime AI logic (Tutor, STT, TTS, KuzuDB API), please refer to `ai-service/api/mcp/` instead.

## 🎯 Overview

This MCP server provides standardized tools and resources for:
- Writing and mapping `.json` strings across 7 localization files in `flutter-app`
- Querying and validating KuzuDB Knowledge Graph structures.

## 📦 Installation

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## 🚀 Usage

### Start MCP Server (for IDE integration)

Configure your IDE's `cline_mcp.json` or Copilot setting to run:
```bash
python server.py
```

## 🛠️ Available DEV Tools

| Tool | Description |
|------|-------------|
| `manage_i18n_key` | Write and sync keys across `en.json`, `vi.json`, `ko.json`, etc. |
| `query_knowledge_graph` | Query local DB during dev (Placeholder for developers) |

## 📚 Resources

| URI | Description |
|-----|-------------|
| `learner_profile://{user_id}` | User profile & progress |
| `conversation_history://{session_id}` | Chat history |
| `lesson_context://{lesson_id}` | Lesson vocabulary |

## 🧪 Testing

```bash
# Run unit tests
pytest tests/test_tools.py -v

# Run integration test
python tests/test_integration.py
```

## 📖 Documentation

See [MCP_IMPLEMENTATION_GUIDE.md](../docs/MCP_IMPLEMENTATION_GUIDE.md) for detailed guide.

## 🔗 Links

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [LexiLingo Architecture](../architecture.md)
