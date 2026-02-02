"""
Thinking Buffer

Smart pause/resume logic for LLM thinking with:
- Utterance continuation detection
- Context merging when user adds to input
- Cancellation when user changes topic
- Timing-based decisions for natural conversation

This is the brain of the Dual-Stream interruption handling.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Callable, Awaitable

from api.services.dual_stream.dual_stream_state import ThinkingAction

logger = logging.getLogger(__name__)


# ============================================================
# CONFIGURATION
# ============================================================

@dataclass
class ThinkingConfig:
    """Configuration for thinking buffer behavior."""
    
    # Timing
    pause_timeout_s: float = 1.5        # Wait time for more input
    merge_window_s: float = 0.8         # Window for context merging
    quick_response_threshold_s: float = 0.3  # Fast response if under this
    
    # Continuation detection
    min_word_overlap: int = 2           # Words to detect continuation
    continuation_keywords: List[str] = field(default_factory=lambda: [
        "and", "but", "also", "then", "so", "because",
        "however", "although", "moreover", "furthermore",
        "actually", "wait", "oh", "um", "uh",
    ])
    
    # Cancellation detection
    cancel_keywords: List[str] = field(default_factory=lambda: [
        "no", "stop", "cancel", "wait", "never mind",
        "hold on", "forget it", "scratch that",
    ])
    
    # Topic change detection
    topic_change_threshold: float = 0.7  # Semantic similarity threshold


class ThinkingState(str, Enum):
    """Current state of thinking process."""
    IDLE = "idle"               # Not thinking
    WAITING = "waiting"         # Waiting for input to settle
    THINKING = "thinking"       # LLM processing
    PAUSED = "paused"           # Paused, waiting for more
    COMPLETING = "completing"   # Generating final response


# ============================================================
# THINKING BUFFER
# ============================================================

class ThinkingBuffer:
    """
    Manages LLM thinking state with smart pause/resume.
    
    Key scenarios:
    1. User finishes speaking → Wait briefly → Start thinking
    2. User continues speaking → Pause thinking, merge context
    3. User corrects themselves → Cancel thinking, restart
    4. User asks new question → Cancel thinking, new context
    5. User says "wait" → Pause and hold
    
    The buffer accumulates partial transcripts and decides
    when/how to proceed with LLM processing.
    """
    
    def __init__(self, config: Optional[ThinkingConfig] = None):
        self.config = config or ThinkingConfig()
        
        # State
        self._state = ThinkingState.IDLE
        self._partial_texts: List[str] = []
        self._last_partial_time: float = 0.0
        self._thinking_start_time: float = 0.0
        
        # Context
        self._current_context: str = ""
        self._previous_context: str = ""
        self._previous_response: str = ""
        self._pending_text: str = ""
        
        # Tasks
        self._wait_task: Optional[asyncio.Task] = None
        self._thinking_task: Optional[asyncio.Task] = None
        
        # Callbacks
        self._on_action: Optional[Callable[[ThinkingAction, str], Awaitable[None]]] = None
    
    @property
    def state(self) -> ThinkingState:
        return self._state
    
    @property
    def is_thinking(self) -> bool:
        return self._state in (ThinkingState.THINKING, ThinkingState.COMPLETING)
    
    @property
    def current_text(self) -> str:
        """Get current accumulated text."""
        return " ".join(self._partial_texts).strip()
    
    def set_callback(
        self,
        on_action: Callable[[ThinkingAction, str], Awaitable[None]],
    ) -> None:
        """Set callback for thinking actions."""
        self._on_action = on_action
    
    async def add_partial(self, text: str) -> ThinkingAction:
        """
        Add partial transcript from STT.
        
        Decides whether to:
        - Continue waiting
        - Start thinking
        - Pause current thinking
        - Cancel and restart
        
        Returns:
            ThinkingAction indicating what to do next
        """
        self._partial_texts.append(text)
        self._last_partial_time = time.time()
        self._pending_text = self.current_text
        
        # Check for cancel keywords
        if self._detect_cancel(text):
            return await self._cancel()
        
        # If already thinking, check if should pause
        if self._state == ThinkingState.THINKING:
            return await self._pause()
        
        # If waiting, reset timer
        if self._state == ThinkingState.WAITING:
            if self._wait_task:
                self._wait_task.cancel()
            self._wait_task = asyncio.create_task(self._wait_and_decide())
        
        return ThinkingAction.WAIT
    
    async def finalize(self, text: str) -> ThinkingAction:
        """
        Finalize utterance when STT detects end of speech.
        
        This is called when VAD detects silence after speech,
        indicating the user has finished (for now).
        
        Returns:
            ThinkingAction for next step
        """
        self._partial_texts.append(text)
        self._pending_text = self.current_text
        
        # Cancel wait timer
        if self._wait_task:
            self._wait_task.cancel()
            self._wait_task = None
        
        # Check state
        if self._state == ThinkingState.PAUSED:
            # Resume with merged context
            return await self._resume()
        
        # Start new thinking
        return await self._start()
    
    async def _wait_and_decide(self) -> None:
        """Wait for pause timeout then decide action."""
        try:
            await asyncio.sleep(self.config.pause_timeout_s)
            
            # If still waiting, start thinking
            if self._state == ThinkingState.WAITING:
                await self._start()
                
        except asyncio.CancelledError:
            pass  # Timer cancelled, new input arrived
    
    async def _start(self) -> ThinkingAction:
        """Start new thinking process."""
        self._state = ThinkingState.THINKING
        self._thinking_start_time = time.time()
        self._current_context = self._pending_text
        
        logger.info(f"[ThinkingBuffer] START: {self._current_context[:50]}...")
        
        if self._on_action:
            await self._on_action(ThinkingAction.START, self._current_context)
        
        return ThinkingAction.START
    
    async def _pause(self) -> ThinkingAction:
        """Pause thinking to wait for more input."""
        if self._state != ThinkingState.THINKING:
            return ThinkingAction.WAIT
        
        self._state = ThinkingState.PAUSED
        
        logger.info(f"[ThinkingBuffer] PAUSE: waiting for more input")
        
        if self._on_action:
            await self._on_action(ThinkingAction.PAUSE, self._pending_text)
        
        # Start wait timer
        self._wait_task = asyncio.create_task(self._wait_for_resume())
        
        return ThinkingAction.PAUSE
    
    async def _wait_for_resume(self) -> None:
        """Wait for resume timeout."""
        try:
            await asyncio.sleep(self.config.merge_window_s)
            
            # If still paused with no new input, resume
            if self._state == ThinkingState.PAUSED:
                await self._resume()
                
        except asyncio.CancelledError:
            pass
    
    async def _resume(self) -> ThinkingAction:
        """Resume thinking with merged context."""
        if self._state not in (ThinkingState.PAUSED, ThinkingState.WAITING):
            return ThinkingAction.WAIT
        
        # Determine if continuation or new context
        is_continuation = self._detect_continuation(
            self._current_context,
            self._pending_text,
        )
        
        if is_continuation:
            # Merge contexts
            merged = self._merge_contexts(
                self._current_context,
                self._pending_text,
            )
            self._current_context = merged
            action = ThinkingAction.CONTINUE
            logger.info(f"[ThinkingBuffer] CONTINUE: merged context")
        else:
            # New context - restart
            self._current_context = self._pending_text
            action = ThinkingAction.START
            logger.info(f"[ThinkingBuffer] RESTART: new context")
        
        self._state = ThinkingState.THINKING
        self._partial_texts.clear()
        
        if self._on_action:
            await self._on_action(action, self._current_context)
        
        return action
    
    async def _cancel(self) -> ThinkingAction:
        """Cancel current thinking."""
        if self._thinking_task:
            self._thinking_task.cancel()
            self._thinking_task = None
        
        if self._wait_task:
            self._wait_task.cancel()
            self._wait_task = None
        
        self._state = ThinkingState.IDLE
        self._partial_texts.clear()
        self._current_context = ""
        
        logger.info("[ThinkingBuffer] CANCEL: user cancelled")
        
        if self._on_action:
            await self._on_action(ThinkingAction.CANCEL, "")
        
        return ThinkingAction.CANCEL
    
    def _detect_cancel(self, text: str) -> bool:
        """Detect if user wants to cancel."""
        text_lower = text.lower().strip()
        return any(
            kw in text_lower 
            for kw in self.config.cancel_keywords
        )
    
    def _detect_continuation(
        self,
        previous: str,
        current: str,
    ) -> bool:
        """
        Detect if current text is a continuation of previous.
        
        Checks:
        - Continuation keywords at start
        - Word overlap
        - Semantic similarity (future: use embeddings)
        """
        if not previous or not current:
            return False
        
        current_words = current.lower().split()
        if not current_words:
            return False
        
        # Check continuation keywords at start
        first_word = current_words[0]
        if first_word in self.config.continuation_keywords:
            return True
        
        # Check word overlap
        prev_words = set(previous.lower().split())
        curr_words = set(current_words)
        overlap = len(prev_words & curr_words)
        
        return overlap >= self.config.min_word_overlap
    
    def _merge_contexts(
        self,
        previous: str,
        current: str,
    ) -> str:
        """
        Merge previous and current contexts intelligently.
        
        Handles:
        - Simple concatenation with proper punctuation
        - Removing false starts / corrections
        - Maintaining grammatical flow
        """
        if not previous:
            return current
        if not current:
            return previous
        
        # Check if current replaces last part of previous
        prev_words = previous.split()
        curr_words = current.split()
        
        # Find overlap point
        for i in range(len(prev_words) - 1, -1, -1):
            if prev_words[i:] == curr_words[:len(prev_words) - i]:
                # Found overlap - merge
                merged = " ".join(prev_words[:i] + curr_words)
                return merged
        
        # No overlap - concatenate with proper punctuation
        previous = previous.rstrip()
        if previous and previous[-1] not in ".!?,;:":
            previous += ","
        
        return f"{previous} {current}"
    
    def complete(self, response: str) -> None:
        """Mark thinking as complete with response."""
        self._state = ThinkingState.IDLE
        self._previous_context = self._current_context
        self._previous_response = response
        self._current_context = ""
        self._partial_texts.clear()
        self._pending_text = ""
    
    def reset(self) -> None:
        """Reset buffer to initial state."""
        if self._wait_task:
            self._wait_task.cancel()
        if self._thinking_task:
            self._thinking_task.cancel()
        
        self._state = ThinkingState.IDLE
        self._partial_texts.clear()
        self._current_context = ""
        self._pending_text = ""
        self._last_partial_time = 0.0
        self._thinking_start_time = 0.0


# ============================================================
# FACTORY
# ============================================================

def create_thinking_buffer(
    pause_timeout: float = 1.5,
    merge_window: float = 0.8,
) -> ThinkingBuffer:
    """Create configured ThinkingBuffer instance."""
    config = ThinkingConfig(
        pause_timeout_s=pause_timeout,
        merge_window_s=merge_window,
    )
    return ThinkingBuffer(config)
