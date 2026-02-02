# Speech Processing Best Practices

Technical guidelines for implementing high-quality speech features in language learning applications.

## Structure

- `rules/` - Individual rule files
  - `_sections.md` - Section metadata
  - `[category]-[description].md` - Individual rule files
- `metadata.json` - Document metadata
- **`AGENTS.md`** - Compiled output (generated)
- **`SKILL.md`** - Skill definition for AI agents

## Rule Categories

### 1. Audio Quality (CRITICAL)
- Sample rate requirements (16kHz+)
- Audio format optimization
- Noise reduction and preprocessing
- Audio validation before processing

### 2. STT Optimization (HIGH)
- Streaming vs batch processing
- Language model hints
- Confidence thresholds
- Real-time feedback strategies

### 3. TTS Implementation (HIGH)
- Neural voice selection
- SSML markup for prosody
- Caching strategies
- Speed and pitch control

### 4. Pronunciation (HIGH)
- Assessment API usage
- Phoneme alignment
- Scoring metrics (accuracy, fluency, completeness)
- Immediate feedback delivery

### 5. Performance (MEDIUM)
- Audio compression techniques
- Voice activity detection
- Request pooling
- Offline mode support

### 6. Error Handling (MEDIUM)
- Microphone permission management
- Network failure retry logic
- Browser compatibility checks
- Timeout handling

## Creating a New Rule

1. Copy `rules/_template.md` (if exists) or create from scratch
2. Choose appropriate category prefix:
   - `audio-` for Audio Quality
   - `stt-` for STT Optimization
   - `tts-` for TTS Implementation
   - `pronunciation-` for Pronunciation
   - `performance-` for Performance
   - `error-` for Error Handling
3. Fill in frontmatter and content
4. Include both incorrect and correct implementations
5. Add references to documentation

## Integration with LexiLingo

These patterns work with:
- **AI Service**: Gemini API for STT/TTS
- **Backend Service**: Audio storage and processing
- **Flutter App**: Audio recording, playback, UI
- **DL Models**: Custom speech models

## Common Patterns

### Sample Rate
Always use 16kHz or higher for speech recognition. Lower rates significantly degrade accuracy.

### Streaming vs Batch
- **Streaming**: Real-time conversation, low latency
- **Batch**: Pronunciation assessment, higher accuracy

### SSML
Use Speech Synthesis Markup Language for:
- Emphasis on stressed syllables
- Pauses for comprehension
- Pronunciation control with IPA
- Intonation patterns

### Error Handling
Always handle:
- Microphone permission denials
- Network failures (retry with backoff)
- Unsupported audio formats
- Timeout conditions

## Performance Targets

- **STT Latency**: <2s batch, <500ms streaming
- **TTS Latency**: <1s first audio chunk
- **Pronunciation Feedback**: <500ms response
- **Audio File Size**: <5MB for mobile
- **Cache Hit Rate**: >70% for common phrases

## References

- [Google Cloud Speech-to-Text](https://cloud.google.com/speech-to-text/docs)
- [Google Cloud Text-to-Speech](https://cloud.google.com/text-to-speech/docs)
- [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- [SSML Specification](https://www.w3.org/TR/speech-synthesis11/)
- [Opus Audio Codec](https://opus-codec.org/)

## License

MIT - Use these patterns freely in your projects
