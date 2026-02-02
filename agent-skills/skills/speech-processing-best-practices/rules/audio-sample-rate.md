---
title: Use 16kHz+ Sample Rate for Speech Recognition
impact: CRITICAL
impactDescription: Proper sample rate improves STT accuracy by 30-50%
tags: audio, stt, quality, sample-rate
---

## Use 16kHz+ Sample Rate for Speech Recognition

**Impact: CRITICAL (30-50% accuracy improvement)**

Most modern STT models are trained on 16kHz audio. Using lower sample rates (8kHz) significantly degrades accuracy, especially for phoneme distinction. Higher rates (48kHz) don't improve accuracy but waste bandwidth and storage.

**Incorrect (Low sample rate):**

```typescript
// Anti-pattern: 8kHz sample rate
async function recordAudio(): Promise<Blob> {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      sampleRate: 8000,  // ❌ Too low for modern STT
      channelCount: 1
    }
  });
  
  const mediaRecorder = new MediaRecorder(stream);
  const chunks: Blob[] = [];
  
  mediaRecorder.ondataavailable = (e) => chunks.push(e.data);
  
  return new Promise((resolve) => {
    mediaRecorder.onstop = () => {
      resolve(new Blob(chunks, { type: 'audio/webm' }));
    };
    mediaRecorder.start();
    setTimeout(() => mediaRecorder.stop(), 5000);
  });
}

// Result: Poor transcription accuracy, especially for similar phonemes
```

**Why this is incorrect:**
- 8kHz loses high-frequency information needed for consonants
- STT models trained on 16kHz+ audio perform poorly
- Can't distinguish similar sounds (f/th, s/sh)
- Wastes user time with poor recognition

**Correct (Optimal sample rate with validation):**

```typescript
// Best practice: 16kHz sample rate with Web Audio API
interface AudioConfig {
  sampleRate: number;
  channelCount: number;
  echoCancellation: boolean;
  noiseSuppression: boolean;
  autoGainControl: boolean;
}

const OPTIMAL_CONFIG: AudioConfig = {
  sampleRate: 16000,         // 16kHz - optimal for STT
  channelCount: 1,           // Mono sufficient for speech
  echoCancellation: true,    // Remove echo from speakers
  noiseSuppression: true,    // Reduce background noise
  autoGainControl: true      // Normalize volume
};

async function recordHighQualityAudio(
  durationMs: number = 5000
): Promise<{ blob: Blob; actualSampleRate: number }> {
  // Request optimal audio constraints
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: OPTIMAL_CONFIG
  });
  
  // Check what sample rate we actually got
  const audioContext = new AudioContext({ sampleRate: 16000 });
  const source = audioContext.createMediaStreamSource(stream);
  const actualSampleRate = audioContext.sampleRate;
  
  console.log(`Recording at ${actualSampleRate}Hz`);
  
  // Use MediaRecorder with appropriate MIME type
  const options = getSupportedMimeType();
  const mediaRecorder = new MediaRecorder(stream, options);
  
  const chunks: Blob[] = [];
  mediaRecorder.ondataavailable = (e) => {
    if (e.data.size > 0) chunks.push(e.data);
  };
  
  // Start recording
  mediaRecorder.start(100); // Collect data every 100ms
  
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      if (mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
      }
    }, durationMs);
    
    mediaRecorder.onstop = () => {
      clearTimeout(timeout);
      stream.getTracks().forEach(track => track.stop());
      audioContext.close();
      
      const blob = new Blob(chunks, { type: options.mimeType });
      resolve({ blob, actualSampleRate });
    };
    
    mediaRecorder.onerror = (error) => {
      clearTimeout(timeout);
      reject(error);
    };
  });
}

function getSupportedMimeType(): { mimeType: string } {
  // Prefer Opus codec (efficient, good quality)
  const types = [
    'audio/webm;codecs=opus',
    'audio/ogg;codecs=opus',
    'audio/webm',
    'audio/ogg',
    'audio/mp4'
  ];
  
  for (const type of types) {
    if (MediaRecorder.isTypeSupported(type)) {
      return { mimeType: type };
    }
  }
  
  throw new Error('No supported audio MIME type found');
}

// If browser doesn't support 16kHz, resample on server
async function preprocessAudio(
  audioBlob: Blob,
  actualSampleRate: number,
  targetSampleRate: number = 16000
): Promise<Blob> {
  if (actualSampleRate === targetSampleRate) {
    return audioBlob;
  }
  
  console.log(`Resampling from ${actualSampleRate}Hz to ${targetSampleRate}Hz`);
  
  // Load audio into AudioContext
  const arrayBuffer = await audioBlob.arrayBuffer();
  const audioContext = new AudioContext({ sampleRate: actualSampleRate });
  const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
  
  // Create offline context at target rate
  const offlineContext = new OfflineAudioContext(
    1, // mono
    (audioBuffer.duration * targetSampleRate),
    targetSampleRate
  );
  
  const source = offlineContext.createBufferSource();
  source.buffer = audioBuffer;
  source.connect(offlineContext.destination);
  source.start();
  
  const resampled = await offlineContext.startRendering();
  
  // Convert back to blob
  const wav = audioBufferToWav(resampled);
  return new Blob([wav], { type: 'audio/wav' });
}

// Convert AudioBuffer to WAV format
function audioBufferToWav(buffer: AudioBuffer): ArrayBuffer {
  const length = buffer.length * buffer.numberOfChannels * 2;
  const arrayBuffer = new ArrayBuffer(44 + length);
  const view = new DataView(arrayBuffer);
  const channels: Float32Array[] = [];
  let offset = 0;
  let pos = 0;
  
  // Write WAV header
  setString(view, pos, 'RIFF'); pos += 4;
  view.setUint32(pos, 36 + length, true); pos += 4;
  setString(view, pos, 'WAVE'); pos += 4;
  setString(view, pos, 'fmt '); pos += 4;
  view.setUint32(pos, 16, true); pos += 4; // fmt chunk size
  view.setUint16(pos, 1, true); pos += 2;  // PCM format
  view.setUint16(pos, buffer.numberOfChannels, true); pos += 2;
  view.setUint32(pos, buffer.sampleRate, true); pos += 4;
  view.setUint32(pos, buffer.sampleRate * buffer.numberOfChannels * 2, true); pos += 4;
  view.setUint16(pos, buffer.numberOfChannels * 2, true); pos += 2;
  view.setUint16(pos, 16, true); pos += 2; // bits per sample
  setString(view, pos, 'data'); pos += 4;
  view.setUint32(pos, length, true); pos += 4;
  
  // Write audio data
  for (let i = 0; i < buffer.numberOfChannels; i++) {
    channels.push(buffer.getChannelData(i));
  }
  
  while (pos < arrayBuffer.byteLength) {
    for (let i = 0; i < buffer.numberOfChannels; i++) {
      const sample = Math.max(-1, Math.min(1, channels[i][offset]));
      view.setInt16(pos, sample < 0 ? sample * 0x8000 : sample * 0x7FFF, true);
      pos += 2;
    }
    offset++;
  }
  
  return arrayBuffer;
  
  function setString(view: DataView, offset: number, str: string) {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }
}

// Usage in component
async function recordPronunciation() {
  try {
    const { blob, actualSampleRate } = await recordHighQualityAudio(3000);
    
    // Ensure 16kHz for STT
    const processedBlob = await preprocessAudio(blob, actualSampleRate, 16000);
    
    // Send to STT service
    const transcription = await sttService.transcribe(processedBlob);
    
    return transcription;
  } catch (error) {
    if (error.name === 'NotAllowedError') {
      throw new Error('Microphone permission denied');
    }
    throw error;
  }
}
```

**Why this is better:**
- 16kHz captures all phonetic information
- Optimal balance of quality vs file size
- Browser enhancement features (noise suppression, echo cancellation)
- Resampling fallback if browser doesn't support 16kHz
- Proper error handling

**Sample Rate Guidelines:**

| Rate  | Use Case | Quality | File Size |
|-------|----------|---------|-----------|
| 8kHz  | ❌ Telephone | Poor | Small |
| 16kHz | ✅ Speech recognition | Excellent | Optimal |
| 22kHz | ⚠️ Music (low quality) | Good | Medium |
| 44.1kHz | ⚠️ Music (CD quality) | Excellent | Large |
| 48kHz | ❌ Professional audio | Overkill | Very Large |

**Additional optimizations:**
1. Use Opus codec (better compression than AAC/MP3)
2. Enable browser audio enhancements
3. Validate audio before upload (check silence, clipping)
4. Monitor actual vs requested sample rate
5. Cache audio context to avoid reinitialization

Reference: [Google Speech-to-Text Audio Requirements](https://cloud.google.com/speech-to-text/docs/encoding) | [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
