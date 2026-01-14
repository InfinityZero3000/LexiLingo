# 🧪 Test AI Chat - Quick Guide

## ✅ Đã Chuẩn Bị

- ✅ API Key loaded từ `.env`
- ✅ Model: `gemini-1.5-flash`
- ✅ App running on Chrome
- ✅ Hot reload enabled

## 🎯 Test Cases

### Test 1: Basic Response
**Input:** `hi`  
**Expected:** AI responds with greeting in English  
**Purpose:** Verify API connection working

### Test 2: Grammar Check
**Input:** `I go to school yesterday`  
**Expected:** AI gently corrects: "went" (past tense)  
**Purpose:** Verify AI English tutor behavior

### Test 3: Simple Conversation
**Input:** `What is your name?`  
**Expected:** AI introduces itself as English learning assistant  
**Purpose:** Verify system prompt working

### Test 4: Vocabulary Help
**Input:** `What does "accomplish" mean?`  
**Expected:** Simple explanation at A2-B1 level  
**Purpose:** Verify A2-B1 level responses

### Test 5: Multiple Messages
**Input:** 
1. `Hello!`
2. `I like coffee`
3. `Do you like coffee?`

**Expected:** Conversation context maintained  
**Purpose:** Verify conversation history working

## 🔍 Debugging

### If Error: "Could not get response"

**Check 1: API Key**
```dart
// In browser console:
// Should see: "API Key loaded: AIzaSy..."
```

**Check 2: Network**
- Open DevTools (F12)
- Go to Network tab
- Look for requests to `generativelanguage.googleapis.com`
- Status should be 200

**Check 3: Console Errors**
```bash
# In terminal running flutter:
# Look for errors like:
# - "API key not valid"
# - "Rate limit exceeded"
```

## 🐛 Common Issues

### Issue 1: "API key not valid"
**Solution:**
1. Check `.env` file has correct key
2. Hot restart (Shift+R in terminal)
3. Verify key at https://ai.google.dev/

### Issue 2: Empty response
**Solution:**
1. Check internet connection
2. Verify Gemini API is not rate limited
3. Try shorter message

### Issue 3: Slow response
**Normal:** First request ~3-5 seconds  
**Subsequent:** ~1-3 seconds  
**If > 10s:** Check network/API status

## ✅ Success Criteria

- [ ] App loads without crash
- [ ] Can navigate to Chat screen
- [ ] Can type and send message
- [ ] AI responds within 5 seconds
- [ ] Response is relevant to input
- [ ] Multiple messages work
- [ ] No console errors

## 🎨 UI Elements to Check

**Chat Screen:**
- [ ] AppBar with title
- [ ] Message list view
- [ ] User messages (blue, right-aligned)
- [ ] AI messages (grey, left-aligned)
- [ ] Input field at bottom
- [ ] Send button
- [ ] Loading indicator when sending

## 📊 Expected Behavior

### Message Flow:
```
1. User types → Input field
2. Press send → Message appears (blue bubble)
3. Loading indicator → Shows "..."
4. AI response → Grey bubble appears
5. Ready for next message
```

### Error Handling:
```
1. No internet → "Please check connection"
2. API error → "Could not get response"
3. Empty input → Send button disabled
```

## 🚀 Advanced Tests

### Test Context Memory:
```
User: My name is John
AI: (responds)
User: What's my name?
AI: (should remember: John)
```

### Test Long Message:
```
User: [Paste 2-3 paragraphs]
AI: (should handle and respond appropriately)
```

### Test Special Characters:
```
User: Hello! 😊 How are you?
AI: (should handle emoji)
```

## 📝 Report Template

```markdown
## Test Results

**Date:** 2026-01-14
**Browser:** Chrome
**OS:** macOS

### Basic Response
- Status: ✅/❌
- Response time: X seconds
- Notes: ...

### Grammar Check
- Status: ✅/❌
- Correction accuracy: ...
- Notes: ...

### Conversation Flow
- Status: ✅/❌
- Context maintained: Yes/No
- Notes: ...

### Issues Found
1. ...
2. ...
```

---

**Quick Start:**
1. App should be open in Chrome
2. Navigate to Chat tab (bottom nav)
3. Type "hi" and send
4. Wait 2-3 seconds
5. See AI response → ✅ Success!

**Status:** Ready to test 🚀
