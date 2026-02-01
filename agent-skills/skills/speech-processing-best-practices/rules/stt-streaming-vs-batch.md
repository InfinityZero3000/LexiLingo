---
title: Use Streaming STT for Real-time Feedback
impact: HIGH
impactDescription: Streaming reduces perceived latency by 60-80%
tags: stt, streaming, real-time, latency
---

## Use Streaming STT for Real-time Feedback

**Impact: HIGH (60-80% latency reduction)**

Batch STT processes entire audio after recording completes, creating noticeable delays. Streaming STT processes audio in real-time chunks, providing instant feedback as users speak. This is critical for conversational practice and pronunciation exercises where immediate feedback drives learning.

**Incorrect (Batch processing with delays):**

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

**Why this is incorrect:**
- High perceived latency (30+ seconds)
- No ability to interrupt or provide instant feedback
- User doesn't know if they're being heard
- Poor for conversation simulations
- Can't do real-time pronunciation correction

**Correct (Streaming with real-time feedback):**

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

**Why this is better:**
- Instant feedback as user speaks
- Can show interim results (gray text)
- Lower perceived latency (~100-500ms vs 30s)
- Better for conversational practice
- Can interrupt or provide real-time corrections
- User knows they're being heard

**When to use streaming vs batch:**

| Feature | Streaming | Batch |
|---------|-----------|-------|
| **Latency** | 100-500ms | 2-10s |
| **Use case** | Conversation, real-time | Pronunciation assessment |
| **Accuracy** | Good | Excellent |
| **Cost** | Higher | Lower |
| **Complexity** | High (WebSocket) | Low (REST API) |

**Best practices:**

1. **Use streaming for:**
   - Conversational practice
   - Real-time feedback
   - Long utterances (>10s)
   - Interactive exercises

2. **Use batch for:**
   - Short recordings (<5s)
   - Pronunciation scoring (need full audio)
   - Budget constraints
   - Asynchronous processing

3. **Optimization tips:**
   - Use `latest_short` model for streaming (faster)
   - Send audio chunks every 100-200ms
   - Show interim results in gray/italic
   - Debounce final results (wait 500ms for stability)
   - Handle network disconnections gracefully

4. **UX considerations:**
   - Visual indicator that mic is active
   - Show interim text differently from final
   - Smooth transitions between interim/final
   - Timeout after 30s of silence
   - Clear error messages

**Hybrid approach:**

```typescript
// Use streaming for transcription, batch for pronunciation scoring
async function conversationWithScoring() {
  const streamingSTT = new StreamingSTTService();
  const recordedAudio: Blob[] = [];
  
  // Start streaming for real-time transcription
  await streamingSTT.startStreaming(
    (text, isFinal) => {
      showTranscript(text, isFinal);
    },
    handleError
  );
  
  // Also record for later analysis
  const mediaRecorder = await startRecording();
  mediaRecorder.ondataavailable = (e) => {
    recordedAudio.push(e.data);
  };
  
  // When user stops speaking
  await waitForSilence();
  
  streamingSTT.stopStreaming();
  mediaRecorder.stop();
  
  // Use full recording for detailed pronunciation analysis
  const fullAudio = new Blob(recordedAudio);
  const pronunciationScore = await assessPronunciation(fullAudio);
  
  showScore(pronunciationScore);
}
```

**Performance monitoring:**

```typescript
// Track streaming performance
interface StreamingMetrics {
  firstChunkLatency: number;   // Time to first interim result
  avgChunkLatency: number;      // Average per-chunk latency
  finalLatency: number;         // Time to final result
  accuracy: number;             // Transcription accuracy
  disconnections: number;       // Network issues
}

function trackStreamingPerformance(metrics: StreamingMetrics) {
  // Alert if latency too high
  if (metrics.avgChunkLatency > 500) {
    console.warn('⚠️ High streaming latency:', metrics.avgChunkLatency);
  }
  
  // Log to analytics
  analytics.track('streaming_stt_performance', metrics);
}
```

Reference: [Google Cloud Streaming Speech-to-Text](https://cloud.google.com/speech-to-text/docs/streaming-recognize) | [WebSocket Streaming Guide](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
