---
title: Use SSML for Prosody Control in TTS
impact: HIGH
impactDescription: SSML improves TTS naturalness by 40-60% for educational content
tags: tts, ssml, prosody, pronunciation
---

## Use SSML for Prosody Control in TTS

**Impact: HIGH (40-60% naturalness improvement)**

Plain text TTS often produces robotic, monotone speech. Speech Synthesis Markup Language (SSML) allows control over pronunciation, emphasis, pauses, and speed - critical for language learning where learners need to hear proper stress patterns and intonation.

**Incorrect (Plain text TTS):**

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

**Why this is incorrect:**
- Can't control pronunciation of ambiguous words
- No emphasis on important parts
- Unnatural pacing for learning
- Can't demonstrate stress patterns
- Numbers and abbreviations mispronounced

**Correct (SSML with prosody control):**

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

**Why this is better:**
- Precise pronunciation control with IPA
- Natural emphasis on stressed syllables
- Adjustable speed for different proficiency levels
- Proper intonation for questions/statements
- Strategic pauses for comprehension
- Correct handling of numbers, abbreviations
- Demonstrates real speech patterns

**Common SSML Tags for Language Learning:**

| Tag | Purpose | Example |
|-----|---------|---------|
| `<emphasis>` | Stress syllables/words | `<emphasis level="strong">THIS</emphasis>` |
| `<break>` | Add pauses | `<break time="500ms"/>` |
| `<prosody>` | Control rate/pitch | `<prosody rate="0.8" pitch="+2st">` |
| `<phoneme>` | IPA pronunciation | `<phoneme alphabet="ipa" ph="ˈrɛd">read</phoneme>` |
| `<say-as>` | Numbers, dates, etc | `<say-as interpret-as="ordinal">21</say-as>` |
| `<sub>` | Substitute pronunciation | `<sub alias="World Wide Web">WWW</sub>` |

**Performance optimization:**

```typescript
// Cache common phrases with SSML
const ttsCache = new Map<string, string>();

async function getCachedTTS(text: string, ssmlTemplate: string): Promise<string> {
  const cacheKey = `${text}:${ssmlTemplate}`;
  
  if (ttsCache.has(cacheKey)) {
    return ttsCache.get(cacheKey)!;
  }
  
  const ssml = ssmlTemplate.replace('{{text}}', text);
  const audio = await ttsService.synthesize({ input: { ssml } });
  
  ttsCache.set(cacheKey, audio);
  return audio;
}

// Pre-generate common words/phrases
const commonWords = ['hello', 'goodbye', 'thank you', 'please'];
await Promise.all(
  commonWords.map(word => getCachedTTS(word, '<speak>{{text}}</speak>'))
);
```

**Testing SSML:**
- Compare SSML vs plain text with native speakers
- A/B test learning outcomes with proper prosody
- Validate IPA pronunciations with linguists
- Test across different voices and languages

Reference: [SSML W3C Specification](https://www.w3.org/TR/speech-synthesis11/) | [Google Cloud TTS SSML](https://cloud.google.com/text-to-speech/docs/ssml)
