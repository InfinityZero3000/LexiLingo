# MCP Server - Model Context Protocol

## Tổng quan

MCP (Model Context Protocol) là giao thức chuẩn hóa để AI assistants (như GitHub Copilot, Claude, Cursor) tương tác với LexiLingo API.

### Lợi ích
- ✅ **Chuẩn hóa**: Tuân thủ JSON-RPC 2.0
- ✅ **Type-safe**: Pydantic schemas cho input/output
- ✅ **Extensible**: Dễ dàng thêm tools và resources mới
- ✅ **Integration**: Tích hợp với VS Code, Cursor, GitHub Copilot

## Kiến trúc

```
┌──────────────────────────────────────────────┐
│          MCP Server (FastAPI)                │
├──────────────────────────────────────────────┤
│  Routes (HTTP/WebSocket)                     │
│  ├── POST /api/v1/mcp       (JSON-RPC)       │
│  ├── GET  /api/v1/mcp/tools                  │
│  ├── GET  /api/v1/mcp/resources              │
│  └── WS   /api/v1/mcp/ws                     │
├──────────────────────────────────────────────┤
│  Server.py (Protocol Handler)                │
│  ├── initialize                              │
│  ├── tools/list, tools/call                  │
│  ├── resources/list, resources/read          │
│  └── ping                                    │
├──────────────────────────────────────────────┤
│  Tools Handler                               │
│  ├── analyze_text     → GraphCAG             │
│  ├── get_user_profile → LearningPatternRepo  │
│  ├── expand_concepts  → KnowledgeGraph       │
│  ├── assess_level     → AssessmentService    │
│  └── get_due_reviews  → SpacedRepetition     │
├──────────────────────────────────────────────┤
│  Resources Handler                            │
│  ├── learner://profile/{user_id}            │
│  ├── concepts://grammar/{level}              │
│  ├── concepts://vocabulary/{category}        │
│  └── mastery://user/{user_id}                │
└──────────────────────────────────────────────┘
```

## Tools

### 1. analyze_text
Phân tích văn bản tiếng Anh: grammar, fluency, vocabulary

**Input:**
```json
{
  "text": "I goes to school yesterday",
  "user_id": "user123",
  "session_id": "sess456",
  "level": "A2"
}
```

**Output:**
```json
{
  "tutor_response": "Good try! Let's fix some errors...",
  "grammar_errors": [
    {"type": "verb_form", "original": "goes", "correction": "went"}
  ],
  "fluency_score": 0.75,
  "vocabulary_level": "A2",
  "corrections": [...]
}
```

### 2. get_user_profile
Lấy hồ sơ học viên

**Input:**
```json
{
  "user_id": "user123"
}
```

**Output:**
```json
{
  "user_id": "user123",
  "level": "B1",
  "common_errors": ["subject_verb_agreement", "tense_usage"],
  "strengths": ["vocabulary", "reading"],
  "areas_to_improve": ["grammar", "speaking"],
  "total_interactions": 456
}
```

### 3. expand_concepts
Mở rộng concepts qua knowledge graph

**Input:**
```json
{
  "concepts": ["present_simple", "verb_be"],
  "hops": 2
}
```

**Output:**
```json
{
  "expanded": [
    {"id": "present_simple", "title": "Present Simple Tense"},
    {"id": "verb_be", "title": "Verb 'To Be'"},
    {"id": "present_continuous", "title": "Present Continuous"}
  ],
  "total_concepts": 3
}
```

### 4. assess_level
Đánh giá CEFR level của user

**Input:**
```json
{
  "user_id": "user123",
  "days": 30
}
```

**Output:**
```json
{
  "current_level": "B1",
  "confidence": 0.85,
  "progress_to_next": 0.45,
  "recommendations": [
    "Practice conditional sentences",
    "Focus on passive voice"
  ]
}
```

### 5. get_due_reviews
Lấy concepts cần ôn tập (spaced repetition)

**Input:**
```json
{
  "user_id": "user123",
  "limit": 10
}
```

**Output:**
```json
{
  "due_items": [
    {
      "concept_id": "past_simple",
      "title": "Past Simple Tense",
      "due_date": "2026-02-05T10:00:00Z",
      "ease_factor": 2.5
    }
  ],
  "total_due": 10
}
```

## Resources

### 1. Learner Profile
```
URI: learner://profile/{user_id}
```

### 2. Grammar Concepts
```
URI: concepts://grammar/{level}
Level: A1, A2, B1, B2, C1, C2
```

### 3. Vocabulary Concepts
```
URI: concepts://vocabulary/{category}
Category: daily_life, work, travel, etc.
```

### 4. User Mastery
```
URI: mastery://user/{user_id}
```

## Sử dụng

### 1. HTTP (JSON-RPC)

```bash
curl -X POST http://localhost:8001/api/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "tools/call",
    "params": {
      "name": "analyze_text",
      "arguments": {
        "text": "Hello world",
        "level": "A1"
      }
    }
  }'
```

### 2. WebSocket

```javascript
const ws = new WebSocket('ws://localhost:8001/api/v1/mcp/ws');

ws.onopen = () => {
  ws.send(JSON.stringify({
    jsonrpc: "2.0",
    id: "1",
    method: "initialize",
    params: {
      clientInfo: {
        name: "my-client",
        version: "1.0.0"
      }
    }
  }));
};

ws.onmessage = (event) => {
  const response = JSON.parse(event.data);
  console.log(response.result);
};
```

### 3. Python Client

```python
import httpx
import asyncio

async def call_mcp_tool():
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "http://localhost:8001/api/v1/mcp",
            json={
                "jsonrpc": "2.0",
                "id": "1",
                "method": "tools/call",
                "params": {
                    "name": "analyze_text",
                    "arguments": {
                        "text": "I am learning English",
                        "level": "A2"
                    }
                }
            }
        )
        return response.json()

result = asyncio.run(call_mcp_tool())
print(result)
```

## Testing

Chạy test script:
```bash
cd ai-service
./test_mcp.sh
```

Hoặc test từng endpoint:

```bash
# 1. Initialize
curl -X POST http://localhost:8001/api/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}'

# 2. List tools
curl http://localhost:8001/api/v1/mcp/tools | jq

# 3. List resources
curl http://localhost:8001/api/v1/mcp/resources | jq

# 4. Call tool
curl -X POST http://localhost:8001/api/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":"2",
    "method":"tools/call",
    "params":{
      "name":"get_user_profile",
      "arguments":{"user_id":"test123"}
    }
  }' | jq
```

## Tích hợp VS Code

### 1. Cấu hình MCP trong VS Code

Thêm vào `.vscode/settings.json`:

```json
{
  "mcp.servers": {
    "lexilingo": {
      "url": "http://localhost:8001/api/v1/mcp",
      "protocol": "jsonrpc",
      "capabilities": ["tools", "resources"]
    }
  }
}
```

### 2. Sử dụng với GitHub Copilot

MCP tools sẽ tự động xuất hiện trong Copilot suggestions khi AI service đang chạy.

## Error Handling

MCP tuân thủ JSON-RPC 2.0 error codes:

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "error": {
    "code": -32601,
    "message": "Method not found",
    "data": null
  }
}
```

### Error Codes:
- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error
- `-32001`: Tool not found
- `-32002`: Resource not found

## Mở rộng

### Thêm Tool mới

1. Định nghĩa schema trong `tools.py`:
```python
class MyToolInput(BaseModel):
    param1: str
    param2: int

class MyToolOutput(BaseModel):
    result: str

TOOL_DEFINITIONS.append({
    "name": "my_tool",
    "description": "My custom tool",
    "input_schema": MyToolInput.model_json_schema(),
    "output_schema": MyToolOutput.model_json_schema(),
})
```

2. Thêm handler:
```python
async def _handle_my_tool(self, args: Dict[str, Any]) -> Dict[str, Any]:
    input_data = MyToolInput(**args)
    # Process...
    return MyToolOutput(result="done").model_dump()
```

### Thêm Resource mới

1. Định nghĩa trong `resources.py`:
```python
RESOURCE_TEMPLATES.append({
    "uri_template": "my-resource://{id}",
    "name": "My Resource",
    "description": "Custom resource",
    "mime_type": "application/json",
})
```

2. Thêm handler trong `MCPResourceHandler.read_resource()`

## Tham khảo

- [MCP Specification](https://modelcontextprotocol.io)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [LexiLingo API Docs](http://localhost:8001/docs)
