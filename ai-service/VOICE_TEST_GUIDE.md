# 🎤 Hướng Dẫn Test Giọng Nói Interactive

## Tổng Quan

Script `test_voice_interactive.py` cho phép bạn test toàn bộ pipeline:
- 🎤 **Thu âm** giọng nói của bạn
- 📝 **Chuyển đổi** giọng nói thành text (STT)
- 🤖 **Phân tích** grammar và fluency với AI Orchestrator
- 🔊 **Phản hồi** bằng giọng nói (TTS)

## Cài Đặt Dependencies

```bash
# Cài đặt các thư viện cần thiết
pip install sounddevice soundfile numpy faster-whisper pyttsx3

# Hoặc để script tự động cài khi chạy
```

## Cách Sử Dụng

### Mode 1: Interactive Mode (Thu âm thật)

```bash
python3 test_voice_interactive.py
# Chọn: 1

# Sau đó:
# 1. Nhấn ENTER để bắt đầu
# 2. Hệ thống thu âm 5 giây
# 3. Nói câu tiếng Anh của bạn
# 4. Đợi phân tích
# 5. Nghe phản hồi qua loa/headphones
```

**Ví dụ câu nói:**
- "I go to school yesterday" (lỗi thì)
- "She don't like apples" (lỗi subject-verb)
- "I have a good day" (đúng)

### Mode 2: Demo Mode (Không cần micro)

```bash
python3 test_voice_interactive.py
# Chọn: 2

# Hệ thống sẽ test với 5 câu có sẵn:
# - "I goes to school yesterday"
# - "She don't like apples"
# - "I have went to the park"
# - "They was very happy"
# - "I ate a apple"
```

## Pipeline Flow

```
┌─────────────┐
│ 1. Record   │  🎤 Thu âm 5 giây
│   Audio     │
└─────┬───────┘
      │
      ▼
┌─────────────┐
│ 2. STT      │  📝 Whisper chuyển audio → text
│  (Whisper)  │
└─────┬───────┘
      │
      ▼
┌─────────────┐
│ 3. Analyze  │  🤖 RuleBasedChecker phân tích grammar
│(Orchestrator│
└─────┬───────┘
      │
      ▼
┌─────────────┐
│ 4. TTS      │  🔊 pyttsx3 đọc phản hồi
│ (pyttsx3)   │
└─────────────┘
```

## Output Mẫu

### Demo Mode Output

```
🎯 LexiLingo Voice Interactive Test
======================================================================

Select Mode:
  1. Interactive Mode - Record your voice and get feedback
  2. Demo Mode - Test with pre-defined texts (no microphone)

Enter mode (1 or 2): 2

[Step 1] Checking dependencies...
✅ sounddevice installed
✅ numpy installed
✅ pyttsx3 installed

[Step 2] Loading Text-to-Speech model (Piper)...
✅ TTS engine loaded successfully!

📝 DEMO MODE (No Audio Recording)
======================================================================

Test 1/5
User says: "I goes to school yesterday"

[Step 6] Analyzing with AI Orchestrator...
ℹ️  Using RuleBasedChecker (fallback mode)
✅ Analysis completed!
   Fluency Score: 0.5
   Errors Found: 2
   1. subject_verb_agreement: Don't use singular verbs with I/you/we/they
   2. tense: Use past tense with 'yesterday'

[Step 7] Converting response to speech...
🔊 AI: I found 2 errors across different areas. Let me help you improve!
✅ Audio playback completed!
```

### Interactive Mode Output

```
🎤 INTERACTIVE VOICE TEST SESSION 🔊
======================================================================

How this works:
1. You speak a sentence in English
2. System transcribes your speech
3. AI analyzes your grammar and fluency
4. System responds with feedback via speech

Press ENTER to start, 'q' to quit:

[Step 4] Recording for 5 seconds...
ℹ️  🎤 Start speaking now!
   █████ 5/5s

✅ Recording completed!

[Step 5] Converting speech to text...
✅ Transcribed: "Hello I want to practice English"

[Step 6] Analyzing with AI Orchestrator...
✅ Analysis completed!
   Fluency Score: 0.7
✅    No errors detected!

[Step 7] Converting response to speech...
🔊 AI: Good job! I didn't detect any obvious errors.
✅ Audio playback completed!

✅ ✨ Session completed!
```

## Troubleshooting

### Lỗi: No module named 'sounddevice'

```bash
pip install sounddevice soundfile
```

### Lỗi: Whisper download fails

```bash
# Whisper sẽ tự download model 'tiny.en' (~75MB) lần đầu chạy
# Đợi vài phút để download hoàn tất
```

### Lỗi: Microphone not found

```bash
# Kiểm tra microphone có được kết nối không
# Trên Mac: System Preferences → Security & Privacy → Microphone
# Cấp quyền cho Terminal/Python
```

### Không nghe thấy âm thanh TTS

```bash
# Kiểm tra volume
# Kiểm tra speaker/headphones đã kết nối
# Thử chạy lại với sudo (nếu cần quyền audio)
```

## Advanced Usage

### Tùy chỉnh thời gian thu âm

Mở file `test_voice_interactive.py` và sửa:

```python
# Line ~280
duration = 5  # Đổi thành 3, 7, 10, ...
```

### Sử dụng Whisper model lớn hơn (chính xác hơn)

```python
# Line ~115
self.whisper_model = WhisperModel(
    "base.en",  # Đổi từ 'tiny.en' thành 'base.en' hoặc 'small.en'
    device="cpu",
    compute_type="int8"
)
```

### Tùy chỉnh giọng đọc TTS

```python
# Line ~147
self.piper_model.setProperty('rate', 150)  # Tốc độ (100-200)
self.piper_model.setProperty('volume', 0.9)  # Âm lượng (0.0-1.0)

# Chọn giọng (nếu có nhiều giọng)
voices = self.piper_model.getProperty('voices')
self.piper_model.setProperty('voice', voices[0].id)  # Chọn giọng đầu tiên
```

## Testing Tips

1. **Nói rõ ràng**: Phát âm từng từ rõ ràng để STT nhận dạng tốt
2. **Môi trường yên tĩnh**: Tránh ồn background để tăng độ chính xác
3. **Test nhiều loại lỗi**: 
   - Subject-verb agreement: "I goes", "She don't"
   - Tense: "I go yesterday", "I will went"
   - Articles: "I ate a apple", "an house"
4. **Kiểm tra kết quả**: So sánh transcription với những gì bạn nói

## Next Steps

Sau khi test thành công, bạn có thể:

1. **Integrate vào API**: Tạo endpoint `/voice-analyze` nhận audio input
2. **Add real Orchestrator**: Thay `RuleBasedChecker` bằng full orchestrator
3. **Improve TTS**: Sử dụng Piper TTS chất lượng cao hơn
4. **Add UI**: Tạo web interface với microphone button

## System Requirements

- **OS**: macOS, Linux, Windows
- **Python**: 3.8+
- **RAM**: Minimum 2GB (4GB recommended for Whisper)
- **Microphone**: Built-in hoặc external
- **Audio output**: Speakers/headphones

---

**Happy Testing! 🎉**
