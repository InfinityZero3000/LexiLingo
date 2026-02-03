# Hướng dẫn test audio recording

## Các bước kiểm tra:

### 1. Reload trang dual-stream-tester.html (Cmd+R hoặc F5)

### 2. Kiểm tra microphone permission:
- Browser sẽ hỏi quyền truy cập microphone
- Phải click "Allow" để cấp quyền
- Kiểm tra System Preferences → Security & Privacy → Microphone
- Đảm bảo browser (Chrome/Safari/Firefox) có quyền truy cập microphone

### 3. Test recording:
1. Click **Connect** button
2. Đợi message "Connected to server" xuất hiện
3. Click **Start Recording**
4. Kiểm tra log messages:
   - "Requesting microphone access..."
   - "✓ Microphone access granted"
   - "MediaRecorder created: audio/webm"
   - "✓ MediaRecorder started"
   - "Recording started"
5. **NÓI VÀO MICROPHONE** (quan trọng!)
6. Sau 1-2 giây sẽ thấy messages:
   - "📤 Sent audio chunk: XXXX bytes"
   - Server sẽ phản hồi khi đủ 10KB
7. Click **Stop Recording**

### 4. Các vấn đề thường gặp:

**Lỗi: "Microphone access denied"**
- Browser không có quyền truy cập microphone
- Fix: System Preferences → Security & Privacy → Microphone → Bật cho browser

**Lỗi: "Cannot send: ws=false"**
- WebSocket chưa kết nối
- Fix: Click Connect trước khi Record

**Log không hiển thị "Sent audio chunk"**
- Không nói vào microphone
- Microphone bị mute
- Fix: Kiểm tra volume, nói to hơn

**Server không phản hồi**
- Audio chunks nhỏ hơn 10KB
- Fix: Nói lâu hơn (>10 giây)

### 5. Test với command line:

```bash
cd /Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/system-testing
python3 test_buffering.py
```

Sẽ thấy:
```
✓ WebSocket connected!
📤 Sending small audio chunks (1KB each)...
⏳ Waiting for response (should be none)...
   ✅ No spam messages (correct!)
📤 Sending large chunk (12KB)...
📥 Receiving responses:
   stt_partial: Hello...
   stt_final: Hello, I would like to practice English
```

### 6. Kiểm tra AI service có chạy:

```bash
curl http://localhost:8001/health
```

Nếu không response → AI service chưa chạy:
```bash
# Stop old processes
pkill -9 -f "uvicorn api.main_lite:app"

# Start AI service
cd /Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/ai-service
source /Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/.venv/bin/activate
python -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001
```
