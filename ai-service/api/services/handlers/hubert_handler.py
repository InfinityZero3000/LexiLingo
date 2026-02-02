"""
HuBERT Handler - Pronunciation Analysis

Manages HuBERT model for pronunciation assessment.
"""

import logging
import asyncio
from typing import Optional, Dict, Any, Union, List
from dataclasses import dataclass
import os
import tempfile
import base64

logger = logging.getLogger(__name__)


@dataclass
class HuBERTConfig:
    """Configuration for HuBERT pronunciation model."""
    model_id: str = "facebook/hubert-large-ls960-ft"
    model_path: Optional[str] = None
    device: str = "auto"
    sample_rate: int = 16000
    chunk_length: float = 30.0  # Max audio chunk in seconds


class HuBERTHandler:
    """
    Handler for HuBERT pronunciation analysis.
    
    Uses HuBERT for phoneme recognition and pronunciation scoring.
    """
    
    def __init__(self, config: Optional[HuBERTConfig] = None):
        self.config = config or HuBERTConfig()
        self.model = None
        self.processor = None
        self._loaded = False
        self._loading = False
        self._lock = asyncio.Lock()
        
    @property
    def is_loaded(self) -> bool:
        return self._loaded
    
    @property
    def memory_usage_mb(self) -> float:
        """HuBERT large is ~2GB."""
        if not self._loaded:
            return 0.0
        return 2000.0
    
    async def load(self) -> bool:
        """Load the HuBERT model."""
        if self._loaded:
            return True
            
        async with self._lock:
            if self._loaded:
                return True
                
            if self._loading:
                while self._loading:
                    await asyncio.sleep(0.1)
                return self._loaded
            
            self._loading = True
            try:
                logger.info("[HuBERTHandler] Loading HuBERT model...")
                
                from transformers import (
                    HubertForCTC,
                    Wav2Vec2Processor,
                )
                import torch
                
                # Detect device
                device = self._detect_device()
                
                # Load model
                model_path = self.config.model_path or self.config.model_id
                
                self.processor = Wav2Vec2Processor.from_pretrained(model_path)
                self.model = HubertForCTC.from_pretrained(model_path)
                
                # Move to device
                if device == "cuda":
                    self.model = self.model.cuda()
                elif device == "mps":
                    self.model = self.model.to("mps")
                
                self.model.eval()
                self._device = device
                
                self._loaded = True
                logger.info(f"[HuBERTHandler] ✓ HuBERT loaded on {device}")
                return True
                
            except Exception as e:
                logger.error(f"[HuBERTHandler] Failed to load: {e}")
                self._loaded = False
                return False
            finally:
                self._loading = False
    
    def _detect_device(self) -> str:
        """Detect best available device."""
        if self.config.device != "auto":
            return self.config.device
            
        import torch
        if torch.cuda.is_available():
            return "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        return "cpu"
    
    async def unload(self) -> None:
        """Unload model to free memory."""
        if self.model is not None:
            del self.model
            self.model = None
        if self.processor is not None:
            del self.processor
            self.processor = None
            
        self._loaded = False
        
        import gc
        gc.collect()
        
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except:
            pass
            
        logger.info("[HuBERTHandler] Model unloaded")
    
    async def analyze_pronunciation(
        self,
        audio: Union[str, bytes],
        reference_text: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Analyze pronunciation from audio.
        
        Args:
            audio: Audio file path, bytes, or base64
            reference_text: Expected text for comparison
            
        Returns:
            {
                "transcription": "recognized text",
                "phonemes": ["f", "oʊ", "n", ...],
                "pronunciation_score": 0.85,
                "word_scores": [
                    {"word": "hello", "score": 0.9, "phonemes": [...]},
                ],
                "feedback": ["Tips for improvement..."],
            }
        """
        if not await self.load():
            raise RuntimeError("Failed to load HuBERT model")
        
        # Load audio
        waveform = await self._load_audio(audio)
        
        # Run analysis in executor
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            self._analyze_sync,
            waveform,
            reference_text,
        )
        
        return result
    
    def _analyze_sync(
        self,
        waveform,
        reference_text: Optional[str],
    ) -> Dict[str, Any]:
        """Synchronous pronunciation analysis."""
        import torch
        import numpy as np
        
        # Process audio
        inputs = self.processor(
            waveform,
            sampling_rate=self.config.sample_rate,
            return_tensors="pt",
            padding=True,
        )
        
        # Move to device
        if self._device == "cuda":
            inputs = {k: v.cuda() for k, v in inputs.items()}
        elif self._device == "mps":
            inputs = {k: v.to("mps") for k, v in inputs.items()}
        
        # Get predictions
        with torch.no_grad():
            logits = self.model(**inputs).logits
        
        # Decode
        predicted_ids = torch.argmax(logits, dim=-1)
        transcription = self.processor.batch_decode(predicted_ids)[0]
        
        # Extract phonemes (simplified - real implementation would use g2p)
        phonemes = self._text_to_phonemes(transcription)
        
        # Calculate scores
        if reference_text:
            pronunciation_score = self._calculate_score(
                transcription, reference_text
            )
            word_scores = self._calculate_word_scores(
                transcription, reference_text
            )
            feedback = self._generate_feedback(word_scores)
        else:
            pronunciation_score = 0.8
            word_scores = []
            feedback = []
        
        return {
            "transcription": transcription,
            "phonemes": phonemes,
            "pronunciation_score": pronunciation_score,
            "word_scores": word_scores,
            "feedback": feedback,
        }
    
    def _text_to_phonemes(self, text: str) -> List[str]:
        """Convert text to phonemes (simplified)."""
        # This is a simplified version
        # Real implementation should use a proper G2P library
        phonemes = []
        text = text.lower()
        
        # Simple phoneme mapping
        phoneme_map = {
            "a": "æ", "e": "ɛ", "i": "ɪ", "o": "ɒ", "u": "ʌ",
            "th": "θ", "sh": "ʃ", "ch": "tʃ", "ng": "ŋ",
        }
        
        i = 0
        while i < len(text):
            # Check digraphs first
            if i + 1 < len(text):
                digraph = text[i:i+2]
                if digraph in phoneme_map:
                    phonemes.append(phoneme_map[digraph])
                    i += 2
                    continue
            
            # Single character
            char = text[i]
            if char.isalpha():
                phonemes.append(phoneme_map.get(char, char))
            i += 1
        
        return phonemes
    
    def _calculate_score(
        self,
        transcription: str,
        reference: str,
    ) -> float:
        """Calculate pronunciation score using Levenshtein similarity."""
        trans_clean = transcription.lower().strip()
        ref_clean = reference.lower().strip()
        
        # Levenshtein distance
        m, n = len(trans_clean), len(ref_clean)
        if m == 0 or n == 0:
            return 0.0
            
        dp = [[0] * (n + 1) for _ in range(m + 1)]
        
        for i in range(m + 1):
            dp[i][0] = i
        for j in range(n + 1):
            dp[0][j] = j
            
        for i in range(1, m + 1):
            for j in range(1, n + 1):
                if trans_clean[i-1] == ref_clean[j-1]:
                    dp[i][j] = dp[i-1][j-1]
                else:
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
        
        distance = dp[m][n]
        max_len = max(m, n)
        score = 1.0 - (distance / max_len)
        
        return round(max(0.0, min(1.0, score)), 2)
    
    def _calculate_word_scores(
        self,
        transcription: str,
        reference: str,
    ) -> List[Dict[str, Any]]:
        """Calculate per-word scores."""
        trans_words = transcription.lower().split()
        ref_words = reference.lower().split()
        
        word_scores = []
        
        for i, ref_word in enumerate(ref_words):
            if i < len(trans_words):
                trans_word = trans_words[i]
                score = self._calculate_score(trans_word, ref_word)
            else:
                trans_word = ""
                score = 0.0
            
            word_scores.append({
                "word": ref_word,
                "recognized": trans_word,
                "score": score,
                "phonemes": self._text_to_phonemes(ref_word),
            })
        
        return word_scores
    
    def _generate_feedback(
        self,
        word_scores: List[Dict[str, Any]],
    ) -> List[str]:
        """Generate pronunciation feedback."""
        feedback = []
        
        for ws in word_scores:
            if ws["score"] < 0.7:
                word = ws["word"]
                feedback.append(
                    f"Practice '{word}' - try speaking more slowly and clearly."
                )
            elif ws["score"] < 0.85:
                word = ws["word"]
                feedback.append(
                    f"Good attempt at '{word}' - keep practicing for more clarity."
                )
        
        if not feedback:
            feedback.append("Excellent pronunciation! Keep up the good work.")
        
        return feedback[:3]  # Limit to 3 tips
    
    async def _load_audio(self, audio: Union[str, bytes]) -> any:
        """Load audio and resample if needed."""
        import numpy as np
        
        # Handle different input types
        if isinstance(audio, str):
            if audio.startswith("data:audio") or len(audio) > 500:
                # Try base64
                try:
                    if "base64," in audio:
                        audio = audio.split("base64,")[1]
                    audio = base64.b64decode(audio)
                except:
                    pass
        
        # Load with librosa or soundfile
        if isinstance(audio, bytes):
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                f.write(audio)
                audio_path = f.name
            
            try:
                waveform = await self._load_audio_file(audio_path)
            finally:
                os.remove(audio_path)
        else:
            waveform = await self._load_audio_file(audio)
        
        return waveform
    
    async def _load_audio_file(self, path: str):
        """Load audio file."""
        import numpy as np
        
        try:
            import librosa
            waveform, sr = librosa.load(path, sr=self.config.sample_rate)
        except ImportError:
            import soundfile as sf
            waveform, sr = sf.read(path)
            if sr != self.config.sample_rate:
                # Simple resampling (not ideal but works)
                import scipy.signal as signal
                waveform = signal.resample(
                    waveform,
                    int(len(waveform) * self.config.sample_rate / sr),
                )
        
        return waveform
    
    async def invoke(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Unified invoke interface for ModelGateway.
        
        Args:
            params: {
                "audio": file path, bytes, or base64,
                "reference_text": expected text for comparison
            }
            
        Returns:
            Pronunciation analysis result
        """
        audio = params.get("audio")
        if not audio:
            raise ValueError("Missing 'audio' parameter")
            
        return await self.analyze_pronunciation(
            audio=audio,
            reference_text=params.get("reference_text"),
        )


# Singleton instance
_handler: Optional[HuBERTHandler] = None


def get_hubert_handler(config: Optional[HuBERTConfig] = None) -> HuBERTHandler:
    """Get or create HuBERT handler singleton."""
    global _handler
    if _handler is None:
        _handler = HuBERTHandler(config)
    return _handler
