---
title: Provide Phoneme-Level Pronunciation Feedback
impact: MEDIUM
impactDescription: Specific feedback improves pronunciation accuracy 2-3x faster
tags: pronunciation, speech, feedback, phonetics
---

## Provide Phoneme-Level Pronunciation Feedback

**Impact: MEDIUM (2-3x faster pronunciation improvement)**

Generic feedback like "try again" or overall scores don't help learners understand what specifically went wrong. Phoneme-level analysis identifies exactly which sounds need work, allowing targeted practice. This is especially critical for sounds that don't exist in the learner's native language.

**Incorrect (Generic scoring only):**

```typescript
// Anti-pattern: Vague pronunciation feedback
interface PronunciationResult {
  word: string;
  score: number;  // 0-100
  recording: Blob;
}

async function checkPronunciation(
  word: string,
  audioBlob: Blob
): Promise<PronunciationResult> {
  const score = await sttService.scorePronunciation(word, audioBlob);
  
  return {
    word,
    score,
    recording: audioBlob
  };
}

// UI shows: "Score: 65/100 - Try again!"
// User doesn't know WHAT to improve
```

**Why this is incorrect:**
- No actionable feedback on what went wrong
- Can't identify specific problematic sounds
- Learner repeats same mistakes
- No guidance on mouth position or technique
- Slow improvement through trial and error

**Correct (Phoneme-level analysis with actionable feedback):**

```typescript
// Best practice: Detailed phoneme analysis
interface PhonemeScore {
  phoneme: string;          // IPA symbol (e.g., "θ")
  score: number;            // 0-100
  position: number;         // Position in word (0-based)
  duration: number;         // Duration in ms
  expectedDuration: number; // Expected duration
  pitch: number;            // Pitch in Hz
  expectedPitch: number;    // Expected pitch range
  commonMistakes: string[]; // e.g., ["Often confused with /s/"]
}

interface DetailedPronunciationResult {
  word: string;
  overallScore: number;
  phonemes: PhonemeScore[];
  problematicPhonemes: PhonemeScore[];  // Score < 70
  recording: Blob;
  referenceAudio: string;   // URL to native pronunciation
  feedback: FeedbackItem[];
}

interface FeedbackItem {
  type: 'phoneme' | 'tone' | 'speed' | 'stress';
  severity: 'error' | 'warning' | 'info';
  message: string;
  position?: number;
  visualization?: {
    mouthDiagram: string;   // URL to mouth position image
    videoClip?: string;     // URL to pronunciation video
  };
  practice: {
    drills: string[];       // Minimal pair exercises
    examples: string[];     // Words with this sound
  };
}

async function analyzePronunciation(
  word: string,
  expectedPhonemes: string[],  // IPA transcription
  audioBlob: Blob
): Promise<DetailedPronunciationResult> {
  // Use STT with phoneme-level alignment
  const sttResult = await sttService.analyzeWithPhonemes(audioBlob);
  
  // Align detected phonemes with expected
  const alignment = alignPhonemes(expectedPhonemes, sttResult.phonemes);
  
  const phonemeScores: PhonemeScore[] = alignment.map((aligned, index) => {
    return {
      phoneme: aligned.expected,
      score: calculatePhonemeScore(aligned.expected, aligned.detected),
      position: index,
      duration: aligned.detected.duration,
      expectedDuration: aligned.expected.duration,
      pitch: aligned.detected.pitch,
      expectedPitch: aligned.expected.pitch,
      commonMistakes: getCommonMistakes(aligned.expected)
    };
  });
  
  // Identify problematic phonemes
  const problematic = phonemeScores.filter(p => p.score < 70);
  
  // Generate specific feedback
  const feedback = generateFeedback(problematic, word);
  
  return {
    word,
    overallScore: calculateOverallScore(phonemeScores),
    phonemes: phonemeScores,
    problematicPhonemes: problematic,
    recording: audioBlob,
    referenceAudio: await getNativeAudio(word),
    feedback
  };
}

function generateFeedback(
  problematicPhonemes: PhonemeScore[],
  word: string
): FeedbackItem[] {
  const feedback: FeedbackItem[] = [];
  
  for (const phoneme of problematicPhonemes) {
    const issue = diagnosePhonemeIssue(phoneme);
    
    feedback.push({
      type: 'phoneme',
      severity: phoneme.score < 50 ? 'error' : 'warning',
      message: generatePhonemeAdvice(phoneme, issue),
      position: phoneme.position,
      visualization: {
        mouthDiagram: getMouthDiagramUrl(phoneme.phoneme),
        videoClip: getPronunciationVideoUrl(phoneme.phoneme)
      },
      practice: {
        drills: getMinimalPairs(phoneme.phoneme),
        examples: getExampleWords(phoneme.phoneme)
      }
    });
  }
  
  // Add prosody feedback
  if (hasStressIssues(problematicPhonemes)) {
    feedback.push({
      type: 'stress',
      severity: 'info',
      message: `Try emphasizing the first syllable: "${word}".`,
      practice: {
        drills: [`Listen to the stress pattern in: "${word}"`],
        examples: []
      }
    });
  }
  
  return feedback;
}

function generatePhonemeAdvice(
  phoneme: PhonemeScore,
  issue: PhonemeIssue
): string {
  const advice = {
    'θ': {  // 'th' sound in "think"
      substitution: {
        's': 'Your tongue should be between your teeth, not behind them. Try saying "s" then move your tongue forward.',
        't': 'Keep your tongue touching your teeth while blowing air. Don\'t stop the airflow completely.'
      },
      duration: 'Hold the "th" sound a bit longer. It should feel like a gentle hiss.',
      general: 'Place tongue tip between teeth and blow gently.'
    },
    'r': {  // English 'r'
      substitution: {
        'l': 'Curl your tongue back without touching the roof of your mouth.',
        'w': 'Make your lips less rounded and focus on the tongue position.'
      },
      general: 'Curl tongue tip back, don\'t touch anything, make sound in throat.'
    }
    // Add more phonemes...
  };
  
  return advice[phoneme.phoneme]?.[issue] || 
         advice[phoneme.phoneme]?.general || 
         `Practice the "${phoneme.phoneme}" sound.`;
}

// Minimal pair exercises for specific sounds
function getMinimalPairs(phoneme: string): string[] {
  const pairs = {
    'θ': ['think/sink', 'bath/bass', 'path/pass'],
    'ð': ['that/dat', 'breathe/breeze', 'clothing/closing'],
    'r': ['red/led', 'right/light', 'rock/lock'],
    'l': ['lip/rip', 'long/wrong', 'lice/rice'],
    // Add more...
  };
  
  return pairs[phoneme] || [];
}

// Example implementation in UI
function renderPronunciationFeedback(result: DetailedPronunciationResult) {
  return {
    score: result.overallScore,
    visual: renderWaveformWithProblematicRegions(
      result.recording,
      result.problematicPhonemes
    ),
    feedback: result.feedback.map(f => ({
      icon: f.severity === 'error' ? '❌' : f.severity === 'warning' ? '⚠️' : 'ℹ️',
      message: f.message,
      mouthDiagram: f.visualization?.mouthDiagram,
      practiceButton: {
        label: 'Practice this sound',
        action: () => startMinimalPairDrill(f.practice.drills)
      }
    })),
    compareButton: {
      label: 'Compare with native speaker',
      action: () => playComparison(result.recording, result.referenceAudio)
    }
  };
}
```

**Why this is better:**
- Pinpoints exact sounds that need work
- Provides visual guidance (mouth diagrams, videos)
- Offers targeted practice exercises (minimal pairs)
- Tracks improvement over time per phoneme
- Adapts difficulty based on learner's native language
- Gives actionable, specific advice

**Implementation tips:**
1. **Language-specific**: Pre-identify difficult phonemes for each L1→L2 pair
   - Spanish→English: 'v/b', 'j/y', 'sh/ch' confusion
   - Japanese→English: 'r/l', 'th' sounds, final consonants
   - English→Vietnamese: Tones, 'tr/ch', 'kh'

2. **Visual aids**: Use mouth position diagrams and videos
3. **Minimal pairs**: Practice distinguishing similar sounds (think/sink)
4. **Progressive difficulty**: Start with isolated sounds, then words, then sentences
5. **Native language transfer**: Explain using sounds they already know

**Advanced features:**
```typescript
// Track phoneme mastery over time
interface PhonemeProgress {
  phoneme: string;
  attempts: number;
  averageScore: number;
  trend: 'improving' | 'stable' | 'declining';
  lastPracticed: Date;
}

// Recommend practice based on weak phonemes
function getRecommendedPractice(
  userId: string,
  progress: PhonemeProgress[]
): string[] {
  return progress
    .filter(p => p.averageScore < 80)
    .sort((a, b) => a.averageScore - b.averageScore)
    .slice(0, 3)
    .map(p => p.phoneme);
}
```

**Integration with speech models:**
- Use wav2vec 2.0 or similar for phoneme-level alignment
- Fine-tune models on accented speech from target demographics
- Collect native speaker samples for comparison
- Use forced alignment to map audio to expected phonemes

Reference: [Phoneme Recognition in ASR](https://arxiv.org/abs/2006.11477) | [TIMIT Phoneme Dataset](https://catalog.ldc.upenn.edu/LDC93s1)
