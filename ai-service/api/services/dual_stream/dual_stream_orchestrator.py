"""
Dual-Stream Orchestrator

Main coordinator for the three concurrent streams:
1. Listening Stream - Real-time STT with VAD
2. Thinking Stream - GraphCAG + LLM reasoning
3. Speaking Stream - Chunked TTS output

Handles:
- Stream synchronization via shared state
- Interruption handling and context switching
- Smart thinking with pause/resume
- GraphCAG integration for knowledge-grounded responses
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import (
    AsyncGenerator,
    Awaitable,
    Callable,
    Dict,
    Any,
    List,
    Optional,
)

from api.services.dual_stream.dual_stream_state import (
    DualStreamState,
    StreamStatus,
    ThinkingAction,
    TranscriptResult,
    AudioChunk,
    create_dual_stream_state,
)
from api.services.dual_stream.streaming_stt_service import (
    StreamingSTTService,
    get_streaming_stt_service,
)
from api.services.dual_stream.streaming_tts_service import (
    StreamingTTSService,
    get_streaming_tts_service,
)
from api.services.dual_stream.thinking_buffer import (
    ThinkingBuffer,
    ThinkingConfig,
    ThinkingState,
)
from api.services.dual_stream.protocol import (
    MessageType,
    StreamMessage,
    msg_transcript_partial,
    msg_transcript_final,
    msg_thinking_start,
    msg_thinking_stop,
    msg_response_text,
    msg_response_complete,
    msg_audio_start,
    msg_audio_end,
    msg_audio_interrupted,
    msg_analysis_errors,
    msg_analysis_scores,
    msg_error,
)

logger = logging.getLogger(__name__)


# ============================================================
# CALLBACK TYPES
# ============================================================

# Audio output callback: sends audio bytes to client
AudioOutputCallback = Callable[[bytes], Awaitable[None]]

# Message output callback: sends JSON messages to client
MessageOutputCallback = Callable[[StreamMessage], Awaitable[None]]

# Audio input type: async generator of audio bytes
AudioInputStream = AsyncGenerator[bytes, None]


# ============================================================
# ORCHESTRATOR CONFIGURATION
# ============================================================

@dataclass
class OrchestratorConfig:
    """Configuration for DualStreamOrchestrator."""
    
    # Stream control
    enable_streaming_stt: bool = True
    enable_streaming_tts: bool = True
    enable_interruption: bool = True
    
    # Thinking
    thinking_pause_timeout_s: float = 1.5
    thinking_merge_window_s: float = 0.8
    
    # Response
    include_vietnamese: bool = True
    include_scores: bool = True
    include_analysis: bool = True
    
    # Tutor personality
    tutor_personality: str = "warm"  # warm, encouraging, strict
    response_style: str = "brief"    # brief, detailed, socratic


# ============================================================
# DUAL-STREAM ORCHESTRATOR
# ============================================================

class DualStreamOrchestrator:
    """
    Coordinates Listening, Thinking, and Speaking streams.
    
    Architecture:
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │  LISTENING  │───▶│  THINKING   │───▶│  SPEAKING   │
    │   Stream    │    │   Stream    │    │   Stream    │
    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
           │                  │                  │
           └──────────────────┼──────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   SHARED STATE    │
                    │  (DualStreamState)│
                    └───────────────────┘
    
    Usage:
        orchestrator = DualStreamOrchestrator(session_id="xxx")
        
        await orchestrator.start_conversation(
            audio_input=audio_stream,
            on_audio=send_audio,
            on_message=send_message,
        )
    """
    
    def __init__(
        self,
        session_id: str,
        user_id: Optional[str] = None,
        config: Optional[OrchestratorConfig] = None,
        learner_profile: Optional[Dict[str, Any]] = None,
    ):
        self.session_id = session_id
        self.user_id = user_id
        self.config = config or OrchestratorConfig()
        
        # Initialize state
        self.state = create_dual_stream_state(
            session_id=session_id,
            user_id=user_id,
            learner_profile=learner_profile,
            tutor_personality=self.config.tutor_personality,
        )
        
        # Initialize services
        self.stt = get_streaming_stt_service()
        self.tts = get_streaming_tts_service()
        self.thinking_buffer = ThinkingBuffer(
            ThinkingConfig(
                pause_timeout_s=self.config.thinking_pause_timeout_s,
                merge_window_s=self.config.thinking_merge_window_s,
            )
        )
        
        # GraphCAG pipeline (lazy loaded)
        self._graph_cag = None
        
        # Stream tasks
        self._listening_task: Optional[asyncio.Task] = None
        self._thinking_task: Optional[asyncio.Task] = None
        self._speaking_task: Optional[asyncio.Task] = None
        
        # Callbacks
        self._on_audio: Optional[AudioOutputCallback] = None
        self._on_message: Optional[MessageOutputCallback] = None
        
        # Control flags
        self._is_running = False
        self._stop_requested = False
        
        # Queues for inter-stream communication
        self._thinking_queue: asyncio.Queue = asyncio.Queue()
        self._speaking_queue: asyncio.Queue = asyncio.Queue()
        
        # Lock for state access
        self._state_lock = asyncio.Lock()
        
        logger.info(f"[Orchestrator] Created for session {session_id}")
    
    async def _get_graph_cag(self):
        """Get or initialize GraphCAG pipeline."""
        if self._graph_cag is None:
            from api.services.graph_cag.graph import get_graph_cag
            self._graph_cag = await get_graph_cag()
        return self._graph_cag
    
    # ============================================================
    # MAIN ENTRY POINT
    # ============================================================
    
    async def start_conversation(
        self,
        audio_input: AudioInputStream,
        on_audio: AudioOutputCallback,
        on_message: MessageOutputCallback,
    ) -> None:
        """
        Start dual-stream conversation.
        
        Args:
            audio_input: Async generator yielding audio bytes
            on_audio: Callback to send audio to client
            on_message: Callback to send messages to client
        """
        self._on_audio = on_audio
        self._on_message = on_message
        self._is_running = True
        self._stop_requested = False
        
        stream_id = self.state["stream_id"]
        logger.info(f"[Orchestrator] Starting conversation: {stream_id}")
        
        # Set up thinking buffer callback
        self.thinking_buffer.set_callback(self._on_thinking_action)
        
        try:
            # Start all three streams concurrently
            await asyncio.gather(
                self._listening_stream(audio_input),
                self._thinking_stream(),
                self._speaking_stream(),
                return_exceptions=True,
            )
        except asyncio.CancelledError:
            logger.info("[Orchestrator] Conversation cancelled")
        except Exception as e:
            logger.error(f"[Orchestrator] Error: {e}")
            if self._on_message:
                await self._on_message(msg_error(str(e), "ORCHESTRATOR_ERROR"))
        finally:
            self._is_running = False
            logger.info(f"[Orchestrator] Conversation ended: {stream_id}")
    
    async def stop(self) -> None:
        """Stop all streams gracefully."""
        self._stop_requested = True
        
        # Cancel stream tasks
        for task in [self._listening_task, self._thinking_task, self._speaking_task]:
            if task and not task.done():
                task.cancel()
        
        # Stop TTS immediately
        self.tts.stop()
        
        self._is_running = False
        logger.info("[Orchestrator] Stop requested")
    
    # ============================================================
    # STREAM 1: LISTENING
    # ============================================================
    
    async def _listening_stream(
        self,
        audio_input: AudioInputStream,
    ) -> None:
        """
        Listening stream: processes incoming audio.
        
        Flow:
        1. Receive audio chunks
        2. Run through STT with VAD
        3. Send partial transcripts to client
        4. On final, queue for thinking
        5. Detect interruptions and stop TTS
        """
        logger.info("[Listening] Stream started")
        
        async with self._state_lock:
            self.state["is_listening"] = True
            self.state["listening_status"] = StreamStatus.ACTIVE.value
        
        stream_id = self.state["stream_id"]
        
        try:
            # Set up interruption handler
            def on_interruption():
                asyncio.create_task(self._handle_interruption())
            
            async for result in self.stt.stream_transcribe(
                audio_input,
                on_interruption=on_interruption,
            ):
                if self._stop_requested:
                    break
                
                if result.is_interruption:
                    await self._handle_interruption()
                    
                elif result.is_partial:
                    # Send partial to client
                    if self._on_message:
                        await self._on_message(
                            msg_transcript_partial(
                                result.text,
                                result.confidence,
                                stream_id,
                            )
                        )
                    
                    # Update thinking buffer
                    await self.thinking_buffer.add_partial(result.text)
                    
                    async with self._state_lock:
                        self.state["current_partial"] = result.text
                        self.state["partial_text_buffer"].append(result.text)
                    
                elif result.is_final:
                    # Send final to client
                    if self._on_message:
                        await self._on_message(
                            msg_transcript_final(
                                result.text,
                                result.confidence,
                                result.duration_ms,
                                stream_id,
                            )
                        )
                    
                    # Finalize in thinking buffer
                    action = await self.thinking_buffer.finalize(result.text)
                    
                    async with self._state_lock:
                        self.state["user_input"] = result.text
                        self.state["audio_chunks_received"] += 1
                    
                    # Queue for thinking if action is START
                    if action in (ThinkingAction.START, ThinkingAction.CONTINUE):
                        await self._thinking_queue.put(result.text)
        
        except asyncio.CancelledError:
            logger.info("[Listening] Cancelled")
        except Exception as e:
            logger.error(f"[Listening] Error: {e}")
        finally:
            async with self._state_lock:
                self.state["is_listening"] = False
                self.state["listening_status"] = StreamStatus.STOPPED.value
            logger.info("[Listening] Stream ended")
    
    # ============================================================
    # STREAM 2: THINKING
    # ============================================================
    
    async def _thinking_stream(self) -> None:
        """
        Thinking stream: processes user input through GraphCAG.
        
        Flow:
        1. Receive text from thinking queue
        2. Run GraphCAG pipeline
        3. Stream response chunks to speaking queue
        4. Handle pause/resume from thinking buffer
        """
        logger.info("[Thinking] Stream started")
        
        async with self._state_lock:
            self.state["thinking_status"] = StreamStatus.IDLE.value
        
        stream_id = self.state["stream_id"]
        
        try:
            while not self._stop_requested:
                try:
                    # Wait for input from listening stream
                    text = await asyncio.wait_for(
                        self._thinking_queue.get(),
                        timeout=0.1,
                    )
                except asyncio.TimeoutError:
                    continue
                
                # Start thinking
                async with self._state_lock:
                    self.state["is_thinking"] = True
                    self.state["thinking_status"] = StreamStatus.ACTIVE.value
                    self.state["user_input"] = text
                
                if self._on_message:
                    await self._on_message(msg_thinking_start(text, stream_id))
                
                thinking_start = time.time()
                
                try:
                    # Run GraphCAG pipeline
                    graph_cag = await self._get_graph_cag()
                    
                    result = await graph_cag.analyze(
                        user_input=text,
                        session_id=self.session_id,
                        user_id=self.user_id,
                        learner_profile=self.state.get("learner_profile"),
                    )
                    
                    # Check if interrupted
                    if self.state.get("thinking_interrupted"):
                        logger.info("[Thinking] Interrupted, discarding result")
                        async with self._state_lock:
                            self.state["thinking_interrupted"] = False
                        continue
                    
                    # Update state with results
                    async with self._state_lock:
                        self.state["tutor_response"] = result.get("tutor_response", "")
                        self.state["diagnosis_errors"] = result.get("corrections", [])
                        self.state["grammar_score"] = result.get("scores", {}).get("grammar", 0.0)
                        self.state["fluency_score"] = result.get("scores", {}).get("fluency", 0.0)
                        self.state["overall_score"] = result.get("scores", {}).get("overall", 0.0)
                        self.state["strategy"] = result.get("action", {}).get("strategy", "scaffold")
                        self.state["vietnamese_hint"] = result.get("vietnamese_hint")
                        self.state["thinking_latency_ms"] = int((time.time() - thinking_start) * 1000)
                    
                    # Send analysis results
                    if self.config.include_analysis and result.get("corrections"):
                        if self._on_message:
                            await self._on_message(
                                msg_analysis_errors(result["corrections"], stream_id)
                            )
                    
                    if self.config.include_scores:
                        scores = result.get("scores", {})
                        if self._on_message:
                            await self._on_message(
                                msg_analysis_scores(
                                    fluency=scores.get("fluency", 0.0),
                                    grammar=scores.get("grammar", 0.0),
                                    overall=scores.get("overall", 0.0),
                                    vocabulary_level=scores.get("vocabulary_level", "B1"),
                                    stream_id=stream_id,
                                )
                            )
                    
                    # Send response text
                    response = result.get("tutor_response", "")
                    if response:
                        if self._on_message:
                            await self._on_message(
                                msg_response_text(response, is_partial=False, stream_id=stream_id)
                            )
                        
                        # Queue for speaking
                        await self._speaking_queue.put(response)
                    
                    # Mark thinking complete
                    self.thinking_buffer.complete(response)
                    
                    if self._on_message:
                        await self._on_message(
                            msg_thinking_stop("complete", stream_id)
                        )
                
                except Exception as e:
                    logger.error(f"[Thinking] Pipeline error: {e}")
                    if self._on_message:
                        await self._on_message(msg_error(str(e), "THINKING_ERROR", stream_id))
                
                finally:
                    async with self._state_lock:
                        self.state["is_thinking"] = False
                        self.state["thinking_status"] = StreamStatus.IDLE.value
        
        except asyncio.CancelledError:
            logger.info("[Thinking] Cancelled")
        except Exception as e:
            logger.error(f"[Thinking] Error: {e}")
        finally:
            logger.info("[Thinking] Stream ended")
    
    # ============================================================
    # STREAM 3: SPEAKING
    # ============================================================
    
    async def _speaking_stream(self) -> None:
        """
        Speaking stream: generates and sends TTS audio.
        
        Flow:
        1. Receive response text from speaking queue
        2. Generate TTS audio in chunks
        3. Send audio chunks to client
        4. Handle interruptions
        """
        logger.info("[Speaking] Stream started")
        
        async with self._state_lock:
            self.state["speaking_status"] = StreamStatus.IDLE.value
        
        stream_id = self.state["stream_id"]
        
        try:
            while not self._stop_requested:
                try:
                    # Wait for response from thinking stream
                    response = await asyncio.wait_for(
                        self._speaking_queue.get(),
                        timeout=0.1,
                    )
                except asyncio.TimeoutError:
                    continue
                
                # Start speaking
                async with self._state_lock:
                    self.state["is_speaking"] = True
                    self.state["speaking_status"] = StreamStatus.ACTIVE.value
                
                # Inform STT that AI is speaking (for interruption detection)
                self.stt.set_ai_speaking(True)
                
                if self._on_message:
                    await self._on_message(msg_audio_start(stream_id=stream_id))
                
                tts_start = time.time()
                chunks_sent = 0
                total_duration_ms = 0
                first_audio_sent = False
                
                try:
                    async for chunk in self.tts.stream_speak(response):
                        if self._stop_requested:
                            break
                        
                        # Track first audio latency
                        if not first_audio_sent:
                            async with self._state_lock:
                                self.state["first_audio_latency_ms"] = int(
                                    (time.time() - tts_start) * 1000
                                )
                            first_audio_sent = True
                        
                        # Send audio to client
                        if self._on_audio:
                            await self._on_audio(chunk.audio_bytes)
                        
                        chunks_sent += 1
                        total_duration_ms += chunk.duration_ms
                        
                        async with self._state_lock:
                            self.state["audio_chunks_sent"] = chunks_sent
                    
                    # Audio complete
                    if self._on_message:
                        await self._on_message(
                            msg_audio_end(chunks_sent, total_duration_ms, stream_id)
                        )
                    
                    async with self._state_lock:
                        self.state["tts_latency_ms"] = int((time.time() - tts_start) * 1000)
                
                except asyncio.CancelledError:
                    # Interrupted
                    if self._on_message:
                        await self._on_message(
                            msg_audio_interrupted(chunks_sent, "cancelled", stream_id)
                        )
                
                finally:
                    self.stt.set_ai_speaking(False)
                    async with self._state_lock:
                        self.state["is_speaking"] = False
                        self.state["speaking_status"] = StreamStatus.IDLE.value
        
        except asyncio.CancelledError:
            logger.info("[Speaking] Cancelled")
        except Exception as e:
            logger.error(f"[Speaking] Error: {e}")
        finally:
            logger.info("[Speaking] Stream ended")
    
    # ============================================================
    # INTERRUPTION HANDLING
    # ============================================================
    
    async def _handle_interruption(self) -> None:
        """Handle user interruption (speaking while AI is talking)."""
        logger.info("[Orchestrator] Handling interruption")
        
        # Stop TTS immediately
        self.tts.stop()
        
        # Mark thinking as interrupted
        async with self._state_lock:
            self.state["thinking_interrupted"] = True
            self.state["tts_interrupted_at"] = self.state.get("audio_chunks_sent", 0)
        
        # Notify client
        if self._on_message:
            await self._on_message(
                msg_audio_interrupted(
                    self.state.get("audio_chunks_sent", 0),
                    "user_speaking",
                    self.state["stream_id"],
                )
            )
    
    async def _on_thinking_action(
        self,
        action: ThinkingAction,
        context: str,
    ) -> None:
        """Callback from thinking buffer when action is decided."""
        logger.info(f"[Orchestrator] Thinking action: {action.value}")
        
        async with self._state_lock:
            self.state["thinking_action"] = action.value
            
            if action == ThinkingAction.PAUSE:
                self.state["thinking_status"] = StreamStatus.PAUSED.value
            elif action == ThinkingAction.CANCEL:
                self.state["thinking_interrupted"] = True
    
    # ============================================================
    # STATE ACCESSORS
    # ============================================================
    
    def get_state(self) -> DualStreamState:
        """Get current state (thread-safe copy)."""
        return dict(self.state)
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get performance metrics."""
        return {
            "stream_id": self.state.get("stream_id"),
            "session_id": self.session_id,
            "is_running": self._is_running,
            "latency": {
                "first_audio_ms": self.state.get("first_audio_latency_ms", 0),
                "stt_ms": self.state.get("stt_latency_ms", 0),
                "thinking_ms": self.state.get("thinking_latency_ms", 0),
                "tts_ms": self.state.get("tts_latency_ms", 0),
            },
            "audio": {
                "chunks_received": self.state.get("audio_chunks_received", 0),
                "chunks_sent": self.state.get("audio_chunks_sent", 0),
            },
            "thinking": {
                "current_action": self.state.get("thinking_action", "wait"),
                "was_interrupted": self.state.get("thinking_interrupted", False),
            },
        }


# ============================================================
# FACTORY
# ============================================================

def create_orchestrator(
    session_id: str,
    user_id: Optional[str] = None,
    learner_profile: Optional[Dict[str, Any]] = None,
    config: Optional[OrchestratorConfig] = None,
) -> DualStreamOrchestrator:
    """Create a new DualStreamOrchestrator instance."""
    return DualStreamOrchestrator(
        session_id=session_id,
        user_id=user_id,
        learner_profile=learner_profile,
        config=config,
    )
