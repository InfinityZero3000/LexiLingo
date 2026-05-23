# LexiLingo MCP Server

Model Context Protocol server for LexiLingo AI services.

## 🎯 Overview

This MCP server provides standardized tools and resources for:
- Chat with AI tutor (Qwen/Gemini)
- Speech-to-Text (Whisper)
- Text-to-Speech (Piper)
- Pronunciation analysis (HuBERT)
- Grammar evaluation
- Knowledge graph queries
- Exercise generation

## 📦 Installation

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export GEMINI_API_KEY="your_api_key_here"
```

## ⚙️ Configuration

Edit `config.yaml` to configure:
- Models (Qwen, Whisper, Piper, etc.)
- Storage (Redis, MongoDB, KuzuDB)
- Features (caching, logging)

## 🚀 Usage

### Start MCP Server

```bash
python server.py
```

### Test with MCP Client

```python
from mcp.client.stdio import stdio_client
from mcp import ClientSession, StdioServerParameters

async def test():
    server_params = StdioServerParameters(
        command="python",
        args=["server.py"],
    )
    
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            
            # List tools
            tools = await session.list_tools()
            print(f"Available: {[t.name for t in tools.tools]}")
            
            # Call chat tool
            result = await session.call_tool(
                "chat_with_ai",
                {"message": "Hello!", "model": "qwen"},
            )
            print(result.content[0].text)
```

## 🛠️ Available Tools

| Tool | Description | Status |
|------|-------------|--------|
| `chat_with_ai` | Chat with Qwen/Gemini | ✅ Ready |
| `transcribe_audio` | Whisper STT | ✅ Ready |
| `generate_speech` | Piper TTS | ✅ Ready |
| `evaluate_grammar` | Grammar check | ✅ Ready |
| `analyze_pronunciation` | HuBERT scoring | 🚧 TODO |
| `query_knowledge_graph` | KuzuDB queries | 🚧 TODO |
| `generate_exercise` | Exercise gen | 🚧 TODO |

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
