# AI Service - TTS/STT Testing Guide

## Tổng Quan

AI Service của LexiLingo đã được tích hợp các tính năng Text-to-Speech (TTS) và Speech-to-Text (STT) không cần training. Tài liệu này hướng dẫn cách test và đánh giá các tính năng này.

## Tính Năng

### 🔊 Text-to-Speech (TTS)
- **Model**: Piper (en_US-lessac-medium)
- **Kích thước**: ~60 MB
- **Chất lượng**: 22050 Hz, mono channel
- **Ngôn ngữ**: English (US)
- **Đặc điểm**: Giọng nói tự nhiên, phát âm rõ ràng

### 🎙️ Speech-to-Text (STT)
- **Model**: Faster-Whisper (large-v3)
- **Kích thước**: ~3 GB
- **Độ chính xác**: Cao (90%+ trên audio chất lượng tốt)
- **Ngôn ngữ**: Auto-detect (hỗ trợ 99+ ngôn ngữ)
- **Đặc điểm**: Fast inference với quantization int8

## Cài Đặt & Thiết Lập

### 1. Kích hoạt Virtual Environment

```bash
cd ai-service
source venv/bin/activate  # hoặc ./venv/bin/activate
```

### 2. Kiểm Tra Dependencies

```bash
./venv/bin/python test_tts_stt_enhanced.py
# Chọn option 1: Check System & Dependencies
```

### 3. Tải Models (nếu chưa có)

```bash
./venv/bin/python test_tts_stt_enhanced.py
# Chọn option 2: Download Models
# Chọn option 3: Download both (khuyến nghị)
```

**Lưu ý:**
- TTS model (~60 MB): Tải nhanh (~30 giây)
- STT model (~3 GB): Tải lâu (~5-10 phút tùy tốc độ mạng)

## Sử Dụng Console Test Tool

### Khởi Chạy Tool

```bash
cd ai-service
./venv/bin/python test_tts_stt_enhanced.py
```

### Menu Chính

```
📋 MENU - Chọn chức năng:
  1. 🔍 Check System & Dependencies - Kiểm tra hệ thống
  2. 📦 Download Models - Tải AI models
  3. 🔊 Test TTS - Text to Speech
  4. 🎙️  Test STT - Speech to Text
  5. 🔄 Test Round-trip - TTS → STT
  6. 🧪 Batch Test - Test nhiều mẫu
  7. 📊 View Test Results - Xem lịch sử test
  8. 🧹 Clean Output Files - Dọn dẹp files
  9. ❌ Exit - Thoát
```

## Các Tình Huống Test

### Test 1: Text-to-Speech (TTS)

**Mục đích:** Kiểm tra khả năng chuyển text thành giọng nói

**Cách test:**
1. Chọn option `3` từ menu
2. Chọn một trong 4 mẫu câu có sẵn hoặc nhập custom
3. Chờ model synthesize (~1-2 giây)
4. Mở file `.wav` để nghe kết quả

**Mẫu câu test:**
- "Hello! This is LexiLingo." - Câu đơn giản
- "The quick brown fox jumps over the lazy dog" - Pangram
- "I can convert your text into natural speech" - Câu dài hơn
- Custom text - Nhập câu riêng của bạn

**Đánh giá:**
- ✅ Phát âm rõ ràng
- ✅ Ngữ điệu tự nhiên
- ✅ Tốc độ phù hợp
- ✅ Không có tiếng ồn artifacts

**Kết quả mẫu:**
```
✅ SUCCESS!
   📁 File: ./output_tts_20260129_194656.wav
   📊 Size: 84.50 KB
   ⏱️  Duration: 1.96s
   🎵 Quality: 22050 Hz, 1 channels
```

### Test 2: Speech-to-Text (STT)

**Mục đích:** Kiểm tra khả năng chuyển giọng nói thành text

**Cách test:**
1. Tạo audio file bằng TTS (Test 1) hoặc dùng file có sẵn
2. Chọn option `4` từ menu
3. Chọn file audio từ danh sách hoặc nhập đường dẫn
4. Chờ model transcribe (~5-10 giây với large-v3)
5. So sánh kết quả với text gốc

**Đánh giá:**
- ✅ Độ chính xác cao (>90% với audio rõ ràng)
- ✅ Auto-detect ngôn ngữ chính xác
- ✅ Xử lý được nhiễu nhẹ
- ✅ Tốc độ xử lý nhanh

**Kết quả mẫu:**
```
✅ SUCCESS!
   🌍 Language: en (probability: 99.8%)
   📝 Transcribed text:
   "Hello! This is LexiLingo."
```

### Test 3: Round-trip (TTS → STT)

**Mục đích:** Kiểm tra toàn bộ pipeline TTS→Audio→STT

**Cách test:**
1. Chọn option `5` từ menu
2. Chọn một mẫu câu hoặc nhập custom
3. Tool sẽ tự động:
   - TTS: Text → Audio
   - STT: Audio → Text
   - So sánh: Original vs Transcribed
4. Xem độ chính xác (accuracy %)

**Mẫu câu test:**
- "The quick brown fox jumps over the lazy dog" - Chuẩn mực
- "I love learning English with LexiLingo" - App-specific
- "Artificial intelligence is transforming education" - Phức tạp

**Đánh giá:**
- 🎯 Accuracy >= 90%: EXCELLENT
- 🎯 Accuracy 70-89%: GOOD
- ⚠️ Accuracy < 70%: NEEDS IMPROVEMENT

**Kết quả mẫu:**
```
📊 RESULTS:
   Original:    "The quick brown fox jumps over the lazy dog"
   Transcribed: "The quick brown fox jumps over the lazy dog."
   
   🎯 Accuracy: 88.9%
   ✓ Correct words: 8/9
   ✅ GOOD - Acceptable accuracy
```

**Phân tích:** Sự khác biệt nhỏ (dấu chấm cuối câu) là bình thường trong STT.

### Test 4: Batch Test

**Mục đích:** Test nhiều câu cùng lúc, đánh giá tổng thể

**Cách test:**
1. Chọn option `6` từ menu
2. Tool sẽ chạy 5 test cases có sẵn
3. Mỗi case: TTS → STT → Compare
4. Xem summary report với average accuracy

**Test cases:**
1. "Hello world" - Đơn giản
2. "The quick brown fox jumps over the lazy dog" - Pangram
3. "I love learning English" - Trung bình
4. "Technology is changing our lives" - Phức tạp
5. "Practice makes perfect" - Thành ngữ

**Kết quả mẫu:**
```
📈 Summary:
   Average accuracy: 87.3%
   Passed tests: 5/5
   💾 Report saved: ./batch_test_report_20260129_200800.json
```

## Đánh Giá Kết Quả

### Tiêu Chí Đánh Giá TTS

| Tiêu chí | Cách đánh giá | Điểm mục tiêu |
|----------|---------------|---------------|
| Phát âm | Nghe rõ từng từ | 9/10 |
| Ngữ điệu | Tự nhiên, không robot | 8/10 |
| Tốc độ | 140-160 wpm | ✅ |
| Chất lượng audio | 22050 Hz, rõ ràng | ✅ |
| Không có artifacts | Không tiếng tạp | ✅ |

### Tiêu Chí Đánh Giá STT

| Tiêu chí | Cách đánh giá | Điểm mục tiêu |
|----------|---------------|---------------|
| Word accuracy | So sánh từng từ | >90% |
| Language detection | Nhận dạng đúng | >98% |
| Speed | Thời gian xử lý | <5s/câu |
| Noise handling | Xử lý nhiễu nhẹ | Good |

### Tiêu Chí Đánh Giá Round-trip

| Accuracy Range | Rating | Ghi chú |
|----------------|--------|---------|
| 95-100% | Excellent | Perfect pipeline |
| 85-94% | Very Good | Production ready |
| 70-84% | Good | Acceptable |
| 60-69% | Fair | Cần cải thiện |
| <60% | Poor | Cần kiểm tra lại |

## Xem Lịch Sử Test

```bash
./venv/bin/python test_tts_stt_enhanced.py
# Chọn option 7: View Test Results
```

Tất cả kết quả test được lưu trong `test_results.json` với thông tin:
- Timestamp
- Test type (tts/stt/roundtrip)
- Input data
- Output file
- Metrics (accuracy, duration, etc.)

## Troubleshooting

### Lỗi: "piper-tts: NOT INSTALLED"

**Giải pháp:**
```bash
cd ai-service
source venv/bin/activate
pip install piper-tts
```

### Lỗi: "TTS model not found"

**Giải pháp:**
```bash
./venv/bin/python test_tts_stt_enhanced.py
# Chọn option 2, sau đó chọn 1 hoặc 3
```

### Lỗi: "STT model not found"

**Giải pháp:**
```bash
./venv/bin/python test_tts_stt_enhanced.py
# Chọn option 2, sau đó chọn 2 hoặc 3
# Đợi 5-10 phút để tải 3GB
```

### Lỗi: "No audio data generated"

**Nguyên nhân:** Text input trống hoặc model chưa load

**Giải pháp:**
1. Kiểm tra text input không empty
2. Restart tool và load lại model

### Low Accuracy (<70%)

**Nguyên nhân:**
- Audio quality kém
- Background noise
- Accent/pronunciation issues

**Giải pháp:**
1. Test với audio rõ ràng hơn
2. Sử dụng mẫu câu đơn giản
3. Kiểm tra lại TTS output quality

## Tích Hợp Vào API

### Sử Dụng TTS trong Code

```python
from piper.voice import PiperVoice

# Load model
voice = PiperVoice.load(
    "./models/piper/en_US-lessac-medium.onnx",
    config_path="./models/piper/en_US-lessac-medium.onnx.json"
)

# Synthesize
text = "Hello, this is a test."
audio_chunks = []
for chunk in voice.synthesize(text):
    audio_chunks.append(chunk.audio_int16_bytes)

# Save to file
audio_data = b''.join(audio_chunks)
with wave.open("output.wav", "wb") as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(22050)
    wav_file.writeframes(audio_data)
```

### Sử Dụng STT trong Code

```python
from faster_whisper import WhisperModel

# Load model
model = WhisperModel(
    "large-v3",
    device="cpu",
    compute_type="int8",
    download_root="./models/whisper"
)

# Transcribe
segments, info = model.transcribe(
    "audio.wav",
    beam_size=5,
    language=None,  # Auto-detect
    vad_filter=True
)

# Get text
text = "".join(segment.text for segment in segments).strip()
print(f"Transcribed: {text}")
print(f"Language: {info.language}")
```

## Best Practices

### Cho TTS:
1. ✅ Sử dụng text ngắn gọn, rõ ràng
2. ✅ Tránh ký tự đặc biệt không cần thiết
3. ✅ Thêm dấu chấm câu để ngữ điệu tự nhiên
4. ✅ Test với nhiều độ dài câu khác nhau

### Cho STT:
1. ✅ Sử dụng audio chất lượng cao (>16kHz)
2. ✅ Giảm background noise
3. ✅ Phát âm rõ ràng, không quá nhanh
4. ✅ Enable VAD filter để cải thiện độ chính xác

### Cho Production:
1. ✅ Cache models đã load (singleton pattern)
2. ✅ Sử dụng async/await cho non-blocking I/O
3. ✅ Implement timeout cho STT (long audio)
4. ✅ Add error handling và retry logic
5. ✅ Monitor accuracy metrics và log failures

## Performance Benchmarks

### TTS (Piper)
- **Model load time**: ~500ms (first time)
- **Synthesis speed**: ~10x realtime
- **Memory usage**: ~200 MB
- **Example**: 10-word sentence = ~100ms

### STT (Faster-Whisper large-v3)
- **Model load time**: ~20-30s (first time)
- **Transcription speed**: ~5x realtime on CPU
- **Memory usage**: ~4 GB
- **Example**: 10-second audio = ~2s transcription

## Kết Luận

✅ **TTS (Piper)**: Hoạt động tốt, chất lượng cao, phù hợp production

✅ **STT (Faster-Whisper)**: Độ chính xác cao, hỗ trợ nhiều ngôn ngữ

✅ **Round-trip pipeline**: Đạt 85-90% accuracy, sẵn sàng tích hợp

## Next Steps

1. Tích hợp TTS/STT vào API endpoints
2. Implement caching và optimization
3. Add support cho Vietnamese (nếu cần)
4. Test với real user audio recordings
5. Monitor và improve accuracy dựa trên user feedback

## Related Files

- **Console Tool**: `test_tts_stt_enhanced.py`
- **Original Tool**: `tts_stt_console.py`
- **Download Script**: `scripts/download_models.py`
- **Voice Test Guide**: `VOICE_TEST_GUIDE.md`
- **Orchestrator Guide**: `ORCHESTRATOR_GUIDE.md`

---

**Trạng thái:** ✅ Fully functional (Tested 2026-01-29)
**Maintainer:** LexiLingo Team
