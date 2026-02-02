---
name: lexilingo-speech-processing
description: Best practices for speech-to-text, text-to-speech, and audio processing in language learning apps. Use when implementing voice recognition, pronunciation scoring, audio playback, or real-time speech features. Triggers on tasks involving STT/TTS APIs, audio quality, or speech feedback systems.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# Speech Processing Best Practices

Technical guidelines for implementing high-quality speech features in language learning applications. Covers STT/TTS optimization, audio processing, pronunciation scoring, and real-time voice interaction.

## When to Apply

Use this skill when:
- Integrating speech-to-text (STT) or text-to-speech (TTS) services
- Building pronunciation assessment features
- Optimizing audio quality and performance
- Implementing voice-based exercises
- Processing user recordings
- Handling multilingual speech recognition

## Rule Categories by Priority

| Priority | Category           | Impact   | Prefix          |
| -------- | ------------------ | -------- | --------------- |
| 1        | Audio Quality      | CRITICAL | `audio-`        |
| 2        | STT Optimization   | HIGH     | `stt-`          |
| 3        | TTS Implementation | HIGH     | `tts-`          |
| 4        | Pronunciation      | HIGH     | `pronunciation-`|
| 5        | Performance        | MEDIUM   | `performance-`  |
| 6        | Error Handling     | MEDIUM   | `error-`        |

## Quick Reference

### 1. Audio Quality (CRITICAL)

- `audio-sample-rate` - Use 16kHz+ for speech recognition
- `audio-noise-reduction` - Apply preprocessing to remove background noise
- `audio-format-optimization` - Use appropriate codecs (WAV, OPUS)
- `audio-validation` - Validate audio before sending to STT

### 2. STT Optimization (HIGH)

- `stt-streaming-vs-batch` - Use streaming for real-time, batch for accuracy
- `stt-language-model-hints` - Provide context hints for domain vocabulary
- `stt-confidence-thresholds` - Set appropriate confidence levels
- `stt-profanity-filter` - Handle inappropriate content gracefully

### 3. TTS Implementation (HIGH)

- `tts-neural-voices` - Use neural TTS for natural pronunciation
- `tts-ssml-markup` - Use SSML for prosody control
- `tts-caching-strategy` - Cache common phrases to reduce costs
- `tts-speed-control` - Allow adjustable playback speed

### 4. Pronunciation Scoring (HIGH)

- `pronunciation-assessment-api` - Use specialized APIs for scoring
- `pronunciation-alignment` - Align phonemes with expected transcription
- `pronunciation-metrics` - Track accuracy, fluency, completeness
- `pronunciation-feedback-delay` - Provide immediate feedback (<500ms)

### 5. Performance (MEDIUM)

- `performance-audio-compression` - Compress audio for transmission
- `performance-client-side-vad` - Use voice activity detection
- `performance-request-pooling` - Pool requests to reduce latency
- `performance-offline-fallback` - Support offline mode

### 6. Error Handling (MEDIUM)

- `error-mic-permissions` - Handle permission denial gracefully
- `error-network-failures` - Retry with exponential backoff
- `error-unsupported-audio` - Validate browser/device capabilities
- `error-timeout-handling` - Set reasonable timeout limits

## Implementation Guide

### Basic STT Setup

```typescript
// Configure STT service with optimal settings
const sttConfig = {
  sampleRate: 16000,      // 16kHz minimum
  language: 'en-US',
  enableAutomaticPunctuation: true,
  model: 'latest_long',   // Or 'latest_short' for real-time
  useEnhanced: true       // Enhanced model for better accuracy
};
```

### Basic TTS Setup

```typescript
// Configure TTS with neural voices
const ttsConfig = {
  voice: 'en-US-Neural2-C',  // Neural voice
  audioEncoding: 'MP3',
  speakingRate: 1.0,
  pitch: 0.0,
  effectsProfileId: ['headphone-class-device']
};
```

## Integration with LexiLingo

This skill works with:
- **AI Service**: Gemini API for STT/TTS, pronunciation assessment
- **Backend Service**: Audio storage, processing pipelines
- **Flutter App**: Audio recording, playback, UI feedback
- **DL Models**: Custom speech models, accent detection

## Common Pitfalls to Avoid

1. ❌ Using low sample rates (<16kHz)
2. ❌ Not preprocessing audio (noise, silence trimming)
3. ❌ Synchronous STT calls blocking UI
4. ❌ Not caching TTS output
5. ❌ Poor error messages for mic issues
6. ❌ No offline fallback
7. ❌ Ignoring browser compatibility

## Performance Benchmarks

- **STT Latency**: Target <2s for batch, <500ms for streaming
- **TTS Latency**: Target <1s first audio chunk
- **Pronunciation Feedback**: Target <500ms response time
- **Audio File Size**: Keep <5MB for mobile uploads
- **Cache Hit Rate**: Target >70% for TTS common phrases

## References

- [Google Cloud Speech-to-Text](https://cloud.google.com/speech-to-text/docs)
- [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- [SSML Specification](https://www.w3.org/TR/speech-synthesis11/)
- [Opus Audio Codec](https://opus-codec.org/)
