# MCP Use Cases - LexiLingo

## Công dụng thực tế của MCP trong LexiLingo

### 🎯 TL;DR

**MCP cho phép AI assistants (GitHub Copilot, Cursor, Claude) gọi trực tiếp các chức năng của LexiLingo, giúp developers làm việc nhanh hơn 10x.**

---

## 1. Vấn đề MCP giải quyết

### ❌ Trước khi có MCP:

```bash
# Scenario: Dev muốn test grammar checker
Step 1: Viết curl command hoặc Postman request
Step 2: Copy/paste user_id, session_id, các params
Step 3: Send request
Step 4: Parse JSON response
Step 5: Analyze kết quả thủ công
⏱️  Thời gian: 5-10 phút/test
```

### ✅ Sau khi có MCP:

```
# Trong VS Code với GitHub Copilot:
Developer: "Test grammar: I goes to school"
         ↓ (1 giây)
Copilot: "Error found: 'goes' → 'go' (subject-verb agreement)"
⏱️  Thời gian: 10 giây
```

---

## 2. Use Cases Cụ Thể

### A. 🐛 Debugging Real-time

**Scenario:** Debug tại sao pronunciation score thấp

```typescript
// Trong VS Code, chat với Copilot:
Developer: "@copilot Why does user 'john_doe' have low pronunciation scores?"

// Copilot tự động:
1. Call MCP: get_user_profile(user_id="john_doe")
   → Returns: common_errors = ["pronunciation", "intonation"]

2. Call MCP: assess_level(user_id="john_doe", days=7)
   → Returns: current_level="A2", confidence=0.6

3. Call MCP: get_due_reviews(user_id="john_doe")
   → Returns: 15 pronunciation concepts due

// Copilot analysis:
"User john_doe struggles with pronunciation because:
- Level A2 (beginner) with low confidence (60%)
- 15 pronunciation concepts not practiced
- Common errors: intonation patterns, word stress
Suggestion: Assign targeted pronunciation drills"
```

### B. 📊 Data Analysis

**Scenario:** Product Manager muốn hiểu user behavior

```python
# Trong Jupyter Notebook với MCP:
PM: "Show me how many B1 users completed present tense module"

# AI assistant via MCP:
users = mcp.tools.call("get_user_profile", {"level": "B1"})
concepts = mcp.resources.read("concepts://grammar/B1")
mastery = [mcp.resources.read(f"mastery://user/{u['user_id']}") 
           for u in users]

# Auto-generate analysis:
"32 B1 users, 28 completed present tense (87.5% completion rate)"
```

### C. 🧪 Automated Testing

**Scenario:** QA test grammar detection accuracy

```yaml
# GitHub Actions workflow với MCP:
- name: Test Grammar Accuracy
  run: |
    # AI-powered test generation via MCP
    mcp tools/call analyze_text --text "She don't like coffee"
    # Expected: error detection on "don't" → "doesn't"
    
    mcp tools/call analyze_text --text "They was here yesterday"
    # Expected: error detection on "was" → "were"
    
    # MCP tự động validate responses và report
```

### D. 🎓 Content Generation

**Scenario:** Tạo exercises tự động cho new topics

```javascript
// Content creator chat với AI:
Creator: "Generate 5 exercises for past continuous, B1 level"

// AI via MCP:
1. expand_concepts(["past_continuous"], hops=2)
   → Get related concepts: past_simple, time_expressions
   
2. resources/read("concepts://grammar/B1")
   → Get B1 vocabulary constraints
   
3. Auto-generate exercises:
   "1. While I _____ (walk) home, it started raining.
    2. They _____ (watch) TV when the phone rang.
    ..."
```

### E. 🔍 Production Monitoring

**Scenario:** DevOps monitor system health

```bash
# Slack bot với MCP integration:
/mcp-status

# Bot automatically:
1. ping → Check server alive
2. assess_level(sample_users) → Check AI accuracy
3. get_due_reviews(all_users) → Check spaced repetition
4. expand_concepts(["test_concept"]) → Check KG performance

Response:
"✅ All systems operational
- AI response time: 1.2s avg
- Spaced repetition: 234 reviews due (normal)
- Knowledge graph: 1,247 concepts indexed"
```

---

## 3. MCP vs Traditional REST API

| Aspect | REST API | MCP |
|--------|----------|-----|
| **Designed for** | Apps (human-written code) | AI assistants |
| **Discovery** | Read docs, OpenAPI | AI auto-discover from schemas |
| **Orchestration** | Developer writes logic | AI chains tools automatically |
| **Error handling** | HTTP status codes | Structured JSON-RPC errors |
| **Context** | Stateless | Protocol supports context |
| **Learning curve** | Medium (read docs) | Low (natural language) |

### Example: Get user weaknesses

**REST API approach:**
```bash
# Developer phải biết 3 endpoints và chain manually:
curl https://api.lexilingo.com/v1/users/123/profile
curl https://api.lexilingo.com/v1/learning-patterns/123
curl https://api.lexilingo.com/v1/assessments/123/history

# Phải parse 3 responses và merge data manually
```

**MCP approach:**
```
Developer: "What are user 123's weaknesses?"

AI via MCP:
- get_user_profile(123) → common_errors
- assess_level(123) → areas_to_improve
- Auto-merge và summarize

Response: "User struggles with: articles (60% error rate), 
prepositions (45%), verb tenses (30%)"
```

---

## 4. Integration Examples

### A. VS Code + GitHub Copilot

```json
// .vscode/mcp-config.json
{
  "servers": {
    "lexilingo": {
      "url": "http://localhost:8001/api/v1/mcp/",
      "capabilities": ["tools", "resources"]
    }
  }
}
```

**Usage:**
```
Developer typing in VS Code:

def test_grammar():
    # @copilot test subject-verb agreement
    
// Copilot auto-generates:
def test_grammar():
    response = mcp.tools.call("analyze_text", {
        "text": "He don't like pizza",
        "level": "A2"
    })
    assert "don't" in response["grammar_errors"][0]["error"]
```

### B. Cursor Editor

```typescript
// Cursor chat:
"Show me all A2 grammar concepts and which ones user 'alice' hasn't mastered"

// Cursor via MCP:
const concepts = await mcp.resources.read("concepts://grammar/A2");
const mastery = await mcp.resources.read("mastery://user/alice");
const unmastered = concepts.filter(c => 
  !mastery.mastered_concepts.includes(c.id)
);
```

### C. Claude Desktop App

```python
# Claude MCP config (~/.config/Claude/config.json):
{
  "mcpServers": {
    "lexilingo": {
      "command": "curl",
      "args": [
        "-X", "POST",
        "http://localhost:8001/api/v1/mcp/",
        "-H", "Content-Type: application/json"
      ]
    }
  }
}
```

**Usage:**
```
User: "Claude, analyze this sentence: I will going tomorrow"

Claude (via MCP):
- Call analyze_text → Detect "will going" error
- Get grammar rule from concepts://grammar/future-tense
- Explain: "Use 'will go' (base form) or 'will be going' (continuous)"
```

---

## 5. Real Production Examples

### Example 1: A/B Testing Grammar Detection

```python
# Data scientist trong notebook:
"""
Test if new grammar model is better than old one
"""

# Với MCP - AI assistant tự động:
test_sentences = [
    "She don't like coffee",
    "They was happy",
    "I have went there"
]

for sentence in test_sentences:
    result = mcp_call("analyze_text", {
        "text": sentence,
        "model": "v2"  # new model
    })
    print(f"Accuracy: {result['fluency_score']}")

# Compare với old model...
```

### Example 2: User Onboarding Flow

```javascript
// App backend:
async function onboardUser(userId) {
  // AI assistant via MCP suggests best starting level
  const assessment = await mcp.tools.call("assess_level", {
    user_id: userId,
    days: 1  // First day
  });
  
  // Get appropriate concepts
  const concepts = await mcp.resources.read(
    `concepts://grammar/${assessment.current_level}`
  );
  
  return {
    recommended_level: assessment.current_level,
    first_lessons: concepts.slice(0, 5)
  };
}
```

### Example 3: Automated Content Moderation

```typescript
// Check if user-generated content has appropriate grammar level
async function validateUserEssay(essay: string, userLevel: string) {
  const analysis = await mcp.tools.call("analyze_text", {
    text: essay,
    level: userLevel
  });
  
  if (analysis.vocabulary_level > userLevel) {
    return {
      valid: false,
      reason: "Vocabulary too advanced - possible plagiarism"
    };
  }
  
  return { valid: true };
}
```

---

## 6. Benefits Summary

### For Developers 👨‍💻
- ⚡ **10x faster** testing and debugging
- 🤖 AI writes test code automatically
- 🔍 Easy data exploration
- 📊 Quick performance analysis

### For Product Managers 📈
- 💡 Answer product questions instantly
- 📉 Monitor user progress without SQL
- 🎯 Validate features with real data
- 🚀 Faster A/B test analysis

### For Data Scientists 🔬
- 🧪 Rapid experimentation
- 📊 Easy access to user behavior data
- 🤖 AI-assisted data analysis
- 📈 Quick hypothesis validation

### For QA Engineers 🧪
- ✅ Automated test generation
- 🐛 Faster bug reproduction
- 📝 Natural language test cases
- 🔄 Continuous testing with AI

---

## 7. Kết luận

### MCP không thay thế REST API
- REST API: Cho production apps (Flutter, Web, Mobile)
- MCP: Cho AI-assisted development, testing, monitoring

### MCP = "AI-first API"
- Thiết kế cho AI assistants, không phải humans
- Enable natural language interaction với system
- Tự động discovery và orchestration

### ROI
- **Before MCP:** 1 feature test = 30 phút
- **After MCP:** 1 feature test = 30 giây
- **Time saved:** 60x efficiency trong development workflow

---

## 8. Try It Yourself

```bash
# 1. Start AI service with MCP
cd ai-service
python -m uvicorn api.main:app --host 0.0.0.0 --port 8001

# 2. Run demo
./demo_mcp_usecase.sh

# 3. In VS Code/Cursor:
@copilot Analyze this: "I goes to school yesterday"
```

**Kết quả:** AI tự động gọi MCP tool và trả về analysis chi tiết trong vài giây! 🚀
