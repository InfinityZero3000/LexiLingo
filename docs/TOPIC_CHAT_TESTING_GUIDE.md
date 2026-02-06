# Topic-Based Conversation: Manual Testing Guide

This document provides comprehensive manual testing scenarios for the Topic-Based Conversation feature. Use these scenarios to validate the end-to-end user experience.

## Prerequisites

Before testing, ensure:
1. AI Service is running on port 8001
2. Backend Service is running on port 8000  
3. Flutter app is running on port 8080
4. MongoDB has sample stories seeded (run `python scripts/seed_sample_stories.py`)
5. Ollama is running with Qwen model (or use Gemini fallback)

## Quick Start

```bash
# Start all services
make dev-all

# Or individually:
cd ai-service && source .venv/bin/activate && uvicorn api.main_lite:app --port 8001
cd backend-service && source venv/bin/activate && uvicorn app.main:app --port 8000
cd flutter-app && flutter run -d chrome --web-port=8080
```

---

## Testing Scenarios

### Scenario 1: Story Selection Flow

**Objective:** Verify users can browse and select stories for conversation.

**Steps:**
1. Navigate to the Topic Chat section in the app
2. Verify story list loads with cards showing:
   - Story title (English & Vietnamese)
   - Difficulty level badge (A1-C2)
   - Category tag
   - Estimated time
   - Cover image
3. Filter by difficulty level (select "A2")
4. Verify only A2 stories are shown
5. Filter by category (select "travel")
6. Verify only travel stories are shown
7. Tap on a story card
8. Verify story detail sheet opens with full information

**Expected Results:**
- [ ] Story list loads within 2 seconds
- [ ] Filtering works correctly
- [ ] Story details show all fields
- [ ] No errors in console

---

### Scenario 2: Start Conversation Session

**Objective:** Verify starting a new conversation session works correctly.

**Steps:**
1. Select "Airport Check-In" story
2. Tap "Start Conversation" button
3. Wait for AI opening message to load
4. Verify:
   - Session is created (session_id assigned)
   - AI persona name appears in chat
   - Opening message is contextually appropriate
   - Character is in-role for the scenario

**Expected Results:**
- [ ] Session starts within 3 seconds
- [ ] AI greeting is relevant to scenario (mentions airport/check-in)
- [ ] Persona name (e.g., "Sarah") appears in message header
- [ ] Chat UI is interactive and ready for input

---

### Scenario 3: Basic Conversation Flow

**Objective:** Verify multi-turn conversation works smoothly.

**Steps:**
1. Start a conversation session (any story)
2. Send message: "Hello, I need help"
3. Wait for AI response
4. Send message: "Can you explain what I need to do?"
5. Wait for AI response
6. Send message: "Thank you!"
7. Verify conversation history is maintained

**Expected Results:**
- [ ] Each response arrives within 5 seconds
- [ ] AI stays in character throughout
- [ ] Responses are contextually appropriate
- [ ] Conversation history scrolls properly
- [ ] Message timestamps are accurate

---

### Scenario 4: Grammar Error Detection

**Objective:** Verify AI detects and corrects grammar errors.

**Steps:**
1. Start a conversation (use A1/A2 difficulty story)
2. Send message with grammar error: "I goes to airport yesterday"
3. Wait for AI response
4. Check for educational hint display

**Expected Results:**
- [ ] AI responds naturally first
- [ ] Grammar correction appears as [💡 Tip] or separate hint card
- [ ] Correction explains: "I go" not "I goes" (subject-verb agreement)
- [ ] Correction is gentle and encouraging

---

### Scenario 5: Vocabulary Hint Detection

**Objective:** Verify AI provides vocabulary hints when appropriate.

**Steps:**
1. Start a conversation with "Airport Check-In" story
2. Send message: "What is a boarding pass?"
3. Wait for AI response
4. Check for vocabulary hint display

**Expected Results:**
- [ ] AI explains the term in context
- [ ] Vocabulary hint appears as [📘] or separate card
- [ ] Definition is clear and appropriate for level
- [ ] Example usage is provided

---

### Scenario 6: Difficulty Level Adaptation

**Objective:** Verify AI adapts language to difficulty level.

**Test A1 Level:**
1. Select an A1 story
2. Start conversation
3. Have 3-4 exchanges
4. Note vocabulary and sentence complexity

**Test C1 Level:**
1. Select a C1 story
2. Start conversation
3. Have 3-4 exchanges
4. Note vocabulary and sentence complexity

**Expected Results:**
- [ ] A1 responses use simple vocabulary (common words)
- [ ] A1 responses use short sentences
- [ ] C1 responses use more sophisticated vocabulary
- [ ] C1 responses have complex sentence structures
- [ ] Both maintain character role appropriately

---

### Scenario 7: LLM Fallback Behavior

**Objective:** Verify Gemini fallback works when Ollama is unavailable.

**Steps:**
1. Stop Ollama service: `ollama stop`
2. Start a conversation
3. Send a message
4. Check response metadata (if available)

**Expected Results:**
- [ ] Response still arrives (using Gemini)
- [ ] Response quality is comparable
- [ ] User experience is unaffected
- [ ] System logs show fallback was used

**Cleanup:**
- Restart Ollama: `ollama serve`

---

### Scenario 8: Error Handling - Network Issues

**Objective:** Verify graceful handling of network errors.

**Steps:**
1. Start a conversation
2. Disconnect network/wifi
3. Send a message
4. Check error handling

**Expected Results:**
- [ ] Error message is user-friendly
- [ ] No app crash
- [ ] Retry option is available
- [ ] Reconnecting allows conversation to continue

---

### Scenario 9: Long Conversation (10+ turns)

**Objective:** Verify performance with longer conversations.

**Steps:**
1. Start a conversation
2. Exchange 10+ messages with AI
3. Check for:
   - Response time consistency
   - Memory of earlier context
   - UI performance (scrolling)
   - No memory leaks

**Expected Results:**
- [ ] Response times remain consistent
- [ ] AI remembers earlier conversation points
- [ ] Scrolling remains smooth
- [ ] App remains responsive

---

### Scenario 10: Special Characters & Unicode

**Objective:** Verify handling of special characters and Vietnamese text.

**Steps:**
1. Start a conversation with Vietnamese-titled story
2. Send message: "Xin chào! Tôi muốn làm thủ tục"
3. Send message with special chars: "What about 'quotes' and $pecial ch@rs?"
4. Verify rendering

**Expected Results:**
- [ ] Vietnamese characters display correctly
- [ ] AI can respond in mixed language if appropriate
- [ ] Special characters don't break parsing
- [ ] No encoding errors

---

### Scenario 11: Session Persistence (Optional)

**Objective:** Verify conversation can be resumed.

**Steps:**
1. Start a conversation
2. Exchange 3-4 messages
3. Close the app (or navigate away)
4. Return to the conversation
5. Check if history is restored

**Expected Results:**
- [ ] Conversation history is visible
- [ ] Can continue from where left off
- [ ] AI context is maintained

---

## API Testing (Postman/curl)

### Test 1: List Stories
```bash
curl http://localhost:8001/api/v1/topics/stories
```

**Expected:** JSON array of stories with total count

### Test 2: Get Single Story
```bash
curl http://localhost:8001/api/v1/topics/stories/airport_checkin_001
```

**Expected:** Full story object with all fields

### Test 3: Start Session
```bash
curl -X POST http://localhost:8001/api/v1/topics/start \
  -H "Content-Type: application/json" \
  -d '{"story_id": "airport_checkin_001", "user_id": "test_user_123"}'
```

**Expected:** Response with session_id and opening message

### Test 4: Chat Message
```bash
curl -X POST http://localhost:8001/api/v1/topics/chat \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "SESSION_ID_FROM_ABOVE",
    "story_id": "airport_checkin_001",
    "user_id": "test_user_123",
    "message": "Hello, I need to check in for my flight"
  }'
```

**Expected:** AI response with optional educational hints

---

## Performance Benchmarks

| Metric | Target | Acceptable |
|--------|--------|------------|
| Story list load time | < 1s | < 3s |
| Session start time | < 2s | < 5s |
| Message response time (Qwen) | < 3s | < 5s |
| Message response time (Gemini) | < 4s | < 7s |
| UI response (scroll, input) | < 100ms | < 300ms |

---

## Bug Reporting Template

When reporting issues, include:

```
**Summary:** Brief description

**Steps to Reproduce:**
1. 
2. 
3. 

**Expected Result:**

**Actual Result:**

**Environment:**
- Device/Browser:
- AI Service Log:
- Screenshot/Video:

**Severity:** Critical / Major / Minor / Cosmetic
```

---

## Checklist Summary

### Before Release
- [ ] All 11 scenarios pass
- [ ] Performance benchmarks met
- [ ] No critical bugs open
- [ ] Error messages are user-friendly
- [ ] Fallback LLM works correctly
- [ ] Vietnamese support verified

### Smoke Test (Quick Check)
- [ ] Stories load
- [ ] Can start session
- [ ] Can send/receive messages
- [ ] Educational hints appear
- [ ] No console errors

---

*Last Updated: 2024-02-06*
*Version: 1.0*
