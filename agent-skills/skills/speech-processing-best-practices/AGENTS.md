# LexiLingo Team - Speech Processing Best Practices

**Version 1.0.0**  
LexiLingo Team  
February 2026

> **Note:**  
> This document is mainly for agents and LLMs to follow when maintaining,  
> generating, or refactoring code. Humans may also find it useful, but guidance  
> here is optimized for automation and consistency by AI-assisted workflows.

---

## Abstract

Technical best practices for implementing high-quality speech features in language learning applications. Covers STT/TTS optimization, audio processing, pronunciation scoring, and real-time voice interaction.

---

## Table of Contents

1. [Audio Quality](##1-audio-quality)
2. [STT Optimization](##2-stt-optimization)
3. [TTS Implementation](##3-tts-implementation)

---

## 1. Audio Quality

**Impact: CRITICAL**

Fundamental audio requirements for clear speech recognition and playback quality.

### 1.1 Use 16kHz+ Sample Rate for Speech Recognition

**Impact: CRITICAL (Proper sample rate improves STT accuracy by 30-50%)**

**Impact: CRITICAL (30-50% accuracy improvement)**

Most modern STT models are trained on 16kHz audio. Using lower sample rates (8kHz) significantly degrades accuracy, especially for phoneme distinction. Higher rates (48kHz) don't improve accuracy but waste bandwidth and storage.

**Incorrect: Low sample rate**

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

**Correct: Optimal sample rate with validation**

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

Reference: [https://cloud.google.com/speech-to-text/docs/encoding](https://cloud.google.com/speech-to-text/docs/encoding)

---

## 2. STT Optimization

**Impact: HIGH**

Best practices for speech-to-text accuracy, latency, and reliability.

### 2.1 Use Streaming STT for Real-time Feedback

**Impact: HIGH (Streaming reduces perceived latency by 60-80%)**

**Impact: HIGH (60-80% latency reduction)**

Batch STT processes entire audio after recording completes, creating noticeable delays. Streaming STT processes audio in real-time chunks, providing instant feedback as users speak. This is critical for conversational practice and pronunciation exercises where immediate feedback drives learning.

**Incorrect: Batch processing with delays**

```typescript
// Anti-pattern: Wait for complete recording, then transcribe
async function recordAndTranscribe(): Promise<string> {
  // Record entire utterance (could be 10-30 seconds)
  const audioBlob = await recordAudio(30000);  // 30 second max
  
  // Upload entire file
  const uploadedUrl = await uploadAudio(audioBlob);
  
  // Wait for transcription (can take 2-5 seconds)
  const transcription = await sttService.transcribe(uploadedUrl);
  
  // User has been waiting 35+ seconds!
  return transcription.text;
}

// Problems:
// - Long wait time before any feedback
// - Can't interrupt or provide real-time corrections
// - Poor UX for conversational practice
```

**Correct: Streaming with real-time feedback**

```typescript
// Best practice: Streaming STT with real-time updates
interface StreamingSTTConfig {
  language: string;
  sampleRate: number;
  interimResults: boolean;      // Get partial results
  singleUtterance: boolean;     // Stop after one sentence
  maxAlternatives: number;      // Number of alternatives
}

class StreamingSTTService {
  private mediaRecorder: MediaRecorder | null = null;
  private websocket: WebSocket | null = null;
  private audioContext: AudioContext | null = null;
  
  async startStreaming(
    onInterim: (text: string, isFinal: boolean) => void,
    onError: (error: Error) => void
  ): Promise<void> {
    // Setup audio recording
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: 16000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true
      }
    });
    
    // Create WebSocket connection to streaming STT service
    this.websocket = new WebSocket('wss://api.example.com/v1/speech/streaming');
    
    this.websocket.onopen = () => {
      // Send config
      this.websocket!.send(JSON.stringify({
        type: 'config',
        config: {
          language: 'en-US',
          encoding: 'LINEAR16',
          sampleRate: 16000,
          interimResults: true,
          model: 'latest_short'  // Optimized for low latency
        }
      }));
      
      console.log('✅ Streaming STT connected');
    };
    
    // Handle streaming results
    this.websocket.onmessage = (event) => {
      const response = JSON.parse(event.data);
      
      if (response.type === 'transcript') {
        const { text, isFinal, confidence } = response;
        
        // Call callback with interim or final result
        onInterim(text, isFinal);
        
        if (isFinal) {
          console.log(`📝 Final: "${text}" (${confidence})`);
        } else {
          console.log(`⏳ Interim: "${text}"`);
        }
      }
    };
    
    this.websocket.onerror = (error) => {
      onError(new Error('WebSocket error'));
    };
    
    // Setup MediaRecorder to stream audio chunks
    this.mediaRecorder = new MediaRecorder(stream, {
      mimeType: 'audio/webm;codecs=opus'
    });
    
    this.mediaRecorder.ondataavailable = async (event) => {
      if (event.data.size > 0 && this.websocket?.readyState === WebSocket.OPEN) {
        // Convert to base64 and send
        const reader = new FileReader();
        reader.onloadend = () => {
          const base64Audio = (reader.result as string).split(',')[1];
          this.websocket!.send(JSON.stringify({
            type: 'audio',
            audio: base64Audio
          }));
        };
        reader.readAsDataURL(event.data);
      }
    };
    
    // Collect audio every 100ms for low latency
    this.mediaRecorder.start(100);
  }
  
  stopStreaming(): void {
    if (this.mediaRecorder) {
      this.mediaRecorder.stop();
      this.mediaRecorder = null;
    }
    
    if (this.websocket) {
      this.websocket.close();
      this.websocket = null;
    }
  }
}

// Usage in conversational practice UI
class ConversationPractice {
  private sttService = new StreamingSTTService();
  private currentTranscript = '';
  
  async startListening() {
    this.currentTranscript = '';
    
    await this.sttService.startStreaming(
      (text, isFinal) => {
        // Update UI with real-time transcription
        this.updateTranscriptDisplay(text, isFinal);
        
        if (isFinal) {
          // Process complete sentence
          this.processFinalTranscript(text);
        }
      },
      (error) => {
        console.error('STT error:', error);
        this.showError('Could not transcribe audio');
      }
    );
  }
  
  private updateTranscriptDisplay(text: string, isFinal: boolean) {
    if (isFinal) {
      // Add to permanent transcript
      this.currentTranscript += text + ' ';
      this.renderFinalText(text);
    } else {
      // Show interim result (gray text)
      this.renderInterimText(text);
    }
  }
  
  private processFinalTranscript(text: string) {
    // Analyze pronunciation, grammar, etc.
    this.analyzeSpeech(text);
    
    // Generate AI response
    this.generateResponse(text);
  }
  
  private renderInterimText(text: string) {
    // Show in gray/italic to indicate it's not final
    const element = document.getElementById('interim-transcript');
    if (element) {
      element.textContent = text;
      element.style.color = '#999';
      element.style.fontStyle = 'italic';
    }
  }
  
  private renderFinalText(text: string) {
    // Show in black to indicate finalized
    const element = document.getElementById('final-transcript');
    if (element) {
      const span = document.createElement('span');
      span.textContent = text + ' ';
      span.style.color = '#000';
      element.appendChild(span);
    }
    
    // Clear interim text
    const interim = document.getElementById('interim-transcript');
    if (interim) interim.textContent = '';
  }
  
  private async analyzeSpeech(text: string) {
    // Provide instant feedback
  }
  
  private async generateResponse(text: string) {
    // Generate AI tutor response
  }
  
  stopListening() {
    this.sttService.stopStreaming();
  }
}

// Alternative: Using Google Cloud Speech-to-Text Streaming
import speech from '@google-cloud/speech';

class GoogleStreamingSTT {
  private client = new speech.SpeechClient();
  private recognizeStream: any = null;
  
  startStreaming(onResult: (text: string, isFinal: boolean) => void) {
    const request = {
      config: {
        encoding: 'LINEAR16' as const,
        sampleRateHertz: 16000,
        languageCode: 'en-US',
        enableAutomaticPunctuation: true,
        model: 'latest_short',  // Low latency model
        useEnhanced: true
      },
      interimResults: true  // Get partial results
    };
    
    this.recognizeStream = this.client
      .streamingRecognize(request)
      .on('data', (data: any) => {
        const result = data.results[0];
        const isFinal = result.isFinal;
        const transcript = result.alternatives[0].transcript;
        
        onResult(transcript, isFinal);
        
        if (isFinal) {
          console.log(`Final: ${transcript}`);
        }
      })
      .on('error', (error: Error) => {
        console.error('Streaming error:', error);
      });
  }
  
  sendAudio(audioChunk: Buffer) {
    if (this.recognizeStream) {
      this.recognizeStream.write(audioChunk);
    }
  }
  
  stop() {
    if (this.recognizeStream) {
      this.recognizeStream.end();
      this.recognizeStream = null;
    }
  }
}
```

Reference: [https://cloud.google.com/speech-to-text/docs/streaming-recognize](https://cloud.google.com/speech-to-text/docs/streaming-recognize)

---

## 3. TTS Implementation

**Impact: HIGH**

Text-to-speech strategies for natural, educational-quality voice output.

### 3.1 Use SSML for Prosody Control in TTS

**Impact: HIGH (SSML improves TTS naturalness by 40-60% for educational content)**

**Impact: HIGH (40-60% naturalness improvement)**

Plain text TTS often produces robotic, monotone speech. Speech Synthesis Markup Language (SSML) allows control over pronunciation, emphasis, pauses, and speed - critical for language learning where learners need to hear proper stress patterns and intonation.

**Incorrect: Plain text TTS**

```typescript
// Anti-pattern: Basic text-to-speech
async function speakWord(word: string, language: string) {
  const response = await ttsService.synthesize({
    text: word,
    voice: `${language}-Standard-A`,
    audioEncoding: 'MP3'
  });
  
  playAudio(response.audioContent);
}

// Examples of what goes wrong:
// - "read" (past tense) pronounced as "reed" (present)
// - No emphasis on stressed syllables
// - Awkward pauses in sentences
// - Wrong pronunciation of abbreviations
```

**Correct: SSML with prosody control**

```typescript
// Best practice: Use SSML for precise control
interface TTSOptions {
  text: string;
  language: string;
  useSSML?: boolean;
  rate?: number;      // 0.25 - 4.0, default 1.0
  pitch?: number;     // -20 - 20 semitones, default 0
  emphasis?: 'strong' | 'moderate' | 'reduced';
  phonemes?: { [word: string]: string }; // IPA pronunciations
}

function buildSSML(options: TTSOptions): string {
  let ssml = '<speak>';
  
  // Set voice gender and variant
  ssml += `<voice gender="neutral" name="${options.language}-Neural2-C">`;
  
  // Apply prosody (rate, pitch)
  if (options.rate !== 1.0 || options.pitch !== 0) {
    ssml += `<prosody rate="${options.rate || 1.0}" pitch="${options.pitch || 0}st">`;
  }
  
  // Process text with SSML markup
  let text = options.text;
  
  // Replace custom phonetic pronunciations
  if (options.phonemes) {
    for (const [word, ipa] of Object.entries(options.phonemes)) {
      const phonemeMarkup = `<phoneme alphabet="ipa" ph="${ipa}">${word}</phoneme>`;
      text = text.replace(new RegExp(`\\b${word}\\b`, 'g'), phonemeMarkup);
    }
  }
  
  // Add emphasis markers if specified
  if (options.emphasis) {
    text = `<emphasis level="${options.emphasis}">${text}</emphasis>`;
  }
  
  ssml += text;
  
  if (options.rate !== 1.0 || options.pitch !== 0) {
    ssml += '</prosody>';
  }
  
  ssml += '</voice>';
  ssml += '</speak>';
  
  return ssml;
}

// Enhanced TTS with SSML
async function speakWithProsody(options: TTSOptions): Promise<string> {
  const ssml = buildSSML(options);
  
  const response = await ttsService.synthesize({
    input: { ssml },
    voice: {
      languageCode: options.language,
      name: `${options.language}-Neural2-C`,
      ssmlGender: 'NEUTRAL'
    },
    audioConfig: {
      audioEncoding: 'MP3',
      effectsProfileId: ['headphone-class-device'],
      pitch: 0,
      speakingRate: 1.0
    }
  });
  
  return response.audioContent;
}

// Usage examples for language learning

// 1. Emphasize stressed syllable
async function speakWithStress(word: string, stressedSyllable: number) {
  const syllables = word.split('-');
  syllables[stressedSyllable] = `<emphasis level="strong">${syllables[stressedSyllable]}</emphasis>`;
  
  const ssml = `<speak>${syllables.join('')}</speak>`;
  return await ttsService.synthesize({ input: { ssml } });
}

// Example: "photograph" vs "photographer" stress difference
await speakWithStress('pho-to-graph', 0);    // PHOtograph
await speakWithStress('pho-to-gra-pher', 2); // photoGRApher

// 2. Control speaking rate for beginners vs advanced
async function speakAtLevel(text: string, level: 'beginner' | 'intermediate' | 'advanced') {
  const rates = {
    beginner: 0.75,      // 75% speed - slower for clarity
    intermediate: 1.0,   // Normal speed
    advanced: 1.2        // 120% speed - faster for challenge
  };
  
  return await speakWithProsody({
    text,
    language: 'en-US',
    rate: rates[level]
  });
}

// 3. Demonstrate intonation patterns
async function speakQuestion(text: string) {
  // Rising intonation for questions
  const ssml = `
    <speak>
      <prosody pitch="+5st">
        ${text}
      </prosody>
    </speak>
  `;
  
  return await ttsService.synthesize({ input: { ssml } });
}

// 4. Add pauses for comprehension
async function speakWithPauses(sentences: string[]) {
  const ssml = `
    <speak>
      ${sentences.map(s => `
        ${s}
        <break time="500ms"/>
      `).join('')}
    </speak>
  `;
  
  return await ttsService.synthesize({ input: { ssml } });
}

// 5. Correct pronunciation with IPA
async function speakWithCorrectPronunciation(word: string, ipa: string) {
  const ssml = `
    <speak>
      <phoneme alphabet="ipa" ph="${ipa}">
        ${word}
      </phoneme>
    </speak>
  `;
  
  return await ttsService.synthesize({ input: { ssml } });
}

// Example: "read" (past tense) vs "read" (present)
await speakWithCorrectPronunciation('read', 'ɹɛd');  // past: "red"
await speakWithCorrectPronunciation('read', 'ɹiːd'); // present: "reed"

// 6. Advanced: Demonstrate sentence stress patterns
interface SentenceWord {
  word: string;
  stress: 'none' | 'weak' | 'strong';
  pause?: number; // milliseconds after word
}

async function speakSentenceWithStress(words: SentenceWord[]) {
  const ssmlWords = words.map(w => {
    let ssml = '';
    
    if (w.stress === 'strong') {
      ssml = `<emphasis level="strong">${w.word}</emphasis>`;
    } else if (w.stress === 'weak') {
      ssml = `<emphasis level="reduced">${w.word}</emphasis>`;
    } else {
      ssml = w.word;
    }
    
    if (w.pause) {
      ssml += `<break time="${w.pause}ms"/>`;
    }
    
    return ssml;
  }).join(' ');
  
  const ssml = `<speak>${ssmlWords}</speak>`;
  return await ttsService.synthesize({ input: { ssml } });
}

// Example: "I DIDN'T take the money" vs "I didn't TAKE the money"
await speakSentenceWithStress([
  { word: 'I', stress: 'strong' },
  { word: "didn't", stress: 'none' },
  { word: 'take', stress: 'weak' },
  { word: 'the', stress: 'none' },
  { word: 'money', stress: 'none' }
]);

// 7. Numbers and ordinals
async function speakNumber(num: number, type: 'cardinal' | 'ordinal' | 'digits') {
  const interpretAs = {
    cardinal: 'cardinal',      // "twenty-one"
    ordinal: 'ordinal',        // "twenty-first"
    digits: 'characters'       // "two one"
  };
  
  const ssml = `
    <speak>
      <say-as interpret-as="${interpretAs[type]}">${num}</say-as>
    </speak>
  `;
  
  return await ttsService.synthesize({ input: { ssml } });
}

// 8. Spell out words letter by letter
async function spellWord(word: string) {
  const letters = word.split('').join(' ');
  const ssml = `
    <speak>
      <say-as interpret-as="characters">${word}</say-as>
      <break time="300ms"/>
      ${word}
    </speak>
  `;
  
  return await ttsService.synthesize({ input: { ssml } });
}
```

Reference: [https://www.w3.org/TR/speech-synthesis11/](https://www.w3.org/TR/speech-synthesis11/)

---

## References

1. [https://cloud.google.com/speech-to-text/docs](https://cloud.google.com/speech-to-text/docs)
2. [https://cloud.google.com/text-to-speech/docs](https://cloud.google.com/text-to-speech/docs)
3. [https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
4. [https://www.w3.org/TR/speech-synthesis11/](https://www.w3.org/TR/speech-synthesis11/)
