"""
WebSocket Streaming Endpoint

Real-time dual-stream conversation via WebSocket.

Protocol:
- Client → Server: Binary audio chunks (PCM 16kHz mono)
- Server → Client: JSON messages + Binary audio chunks

Supports:
- Streaming STT with partial results
- Streaming TTS with chunked audio
- Interruption handling
- Smart thinking pause/resume
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from fastapi.websockets import WebSocketState

from api.services.dual_stream.dual_stream_orchestrator import (
    DualStreamOrchestrator,
    OrchestratorConfig,
    create_orchestrator,
)
from api.services.dual_stream.protocol import (
    MessageType,
    StreamMessage,
    msg_connected,
    msg_error,
)

logger = logging.getLogger(__name__)

router = APIRouter()


# ============================================================
# WEBSOCKET CONNECTION MANAGER
# ============================================================

class ConnectionManager:
    """
    Manages active WebSocket connections.
    
    Tracks:
    - Active connections by session
    - Connection state
    - Graceful disconnection
    """
    
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}
        self.orchestrators: dict[str, DualStreamOrchestrator] = {}
    
    async def connect(
        self,
        websocket: WebSocket,
        session_id: str,
    ) -> None:
        """Accept WebSocket connection."""
        await websocket.accept()
        self.active_connections[session_id] = websocket
        logger.info(f"[WS] Connected: {session_id}")
    
    def disconnect(self, session_id: str) -> None:
        """Remove connection."""
        self.active_connections.pop(session_id, None)
        orchestrator = self.orchestrators.pop(session_id, None)
        if orchestrator:
            asyncio.create_task(orchestrator.stop())
        logger.info(f"[WS] Disconnected: {session_id}")
    
    def get_orchestrator(self, session_id: str) -> Optional[DualStreamOrchestrator]:
        """Get orchestrator for session."""
        return self.orchestrators.get(session_id)
    
    def set_orchestrator(
        self,
        session_id: str,
        orchestrator: DualStreamOrchestrator,
    ) -> None:
        """Set orchestrator for session."""
        self.orchestrators[session_id] = orchestrator


# Global connection manager
manager = ConnectionManager()


# ============================================================
# AUDIO INPUT ADAPTER
# ============================================================

async def audio_input_generator(
    websocket: WebSocket,
    stop_event: asyncio.Event,
):
    """
    Async generator that yields audio chunks from WebSocket.
    
    Filters out JSON control messages and yields only binary audio.
    """
    try:
        while not stop_event.is_set():
            try:
                # Receive with timeout
                message = await asyncio.wait_for(
                    websocket.receive(),
                    timeout=0.1,
                )
                
                if message["type"] == "websocket.disconnect":
                    break
                
                # Binary = audio chunk
                if "bytes" in message:
                    yield message["bytes"]
                
                # Text = control message (skip)
                elif "text" in message:
                    # Parse control messages
                    try:
                        data = json.loads(message["text"])
                        msg_type = data.get("type")
                        
                        if msg_type == "stop_listening":
                            break
                        elif msg_type == "cancel":
                            break
                        # Other control messages handled elsewhere
                    except json.JSONDecodeError:
                        pass
                        
            except asyncio.TimeoutError:
                continue
            except WebSocketDisconnect:
                break
                
    except Exception as e:
        logger.warning(f"[WS] Audio input error: {e}")


# ============================================================
# OUTPUT CALLBACKS
# ============================================================

async def create_audio_callback(websocket: WebSocket):
    """Create callback for sending audio bytes."""
    async def send_audio(audio_bytes: bytes) -> None:
        try:
            if websocket.client_state == WebSocketState.CONNECTED:
                await websocket.send_bytes(audio_bytes)
        except Exception as e:
            logger.warning(f"[WS] Audio send error: {e}")
    
    return send_audio


async def create_message_callback(websocket: WebSocket):
    """Create callback for sending JSON messages."""
    async def send_message(message: StreamMessage) -> None:
        try:
            if websocket.client_state == WebSocketState.CONNECTED:
                await websocket.send_text(message.to_json())
        except Exception as e:
            logger.warning(f"[WS] Message send error: {e}")
    
    return send_message


# ============================================================
# WEBSOCKET ENDPOINT
# ============================================================

@router.websocket("/ws/conversation/stream")
async def dual_stream_conversation(
    websocket: WebSocket,
    session_id: str = Query(..., description="Unique session identifier"),
    user_id: Optional[str] = Query(None, description="User ID for personalization"),
    level: str = Query("B1", description="Learner level (A1-C2)"),
    personality: str = Query("warm", description="Tutor personality"),
):
    """
    WebSocket endpoint for real-time dual-stream conversation.
    
    Protocol:
    - Send binary audio chunks to start transcription
    - Receive JSON messages with transcripts, responses, and events
    - Receive binary audio chunks for TTS output
    
    Query Parameters:
    - session_id: Required unique session identifier
    - user_id: Optional user ID for personalization
    - level: Learner level (A1, A2, B1, B2, C1, C2)
    - personality: Tutor style (warm, encouraging, strict)
    
    JSON Message Types (Server → Client):
    - transcript_partial: Intermediate STT result
    - transcript_final: Complete utterance
    - thinking_start: AI started processing
    - thinking_stop: AI processing complete
    - response_text: Tutor response text
    - audio_start: TTS stream beginning
    - audio_end: TTS stream complete
    - audio_interrupted: TTS was interrupted
    - analysis_errors: Grammar errors found
    - analysis_scores: Fluency/grammar scores
    - error: Error occurred
    """
    # Accept connection
    await manager.connect(websocket, session_id)
    
    try:
        # Create learner profile
        learner_profile = {
            "level": level,
            "native_language": "vi",  # Default Vietnamese
        }
        
        # Create orchestrator config
        config = OrchestratorConfig(
            tutor_personality=personality,
            include_vietnamese=(level in ("A1", "A2")),
        )
        
        # Create orchestrator
        orchestrator = create_orchestrator(
            session_id=session_id,
            user_id=user_id,
            learner_profile=learner_profile,
            config=config,
        )
        manager.set_orchestrator(session_id, orchestrator)
        
        # Create callbacks
        on_audio = await create_audio_callback(websocket)
        on_message = await create_message_callback(websocket)
        
        # Send connected message
        await on_message(msg_connected(
            stream_id=orchestrator.state["stream_id"],
            session_id=session_id,
        ))
        
        # Create stop event
        stop_event = asyncio.Event()
        
        # Create audio input generator
        audio_input = audio_input_generator(websocket, stop_event)
        
        # Start conversation
        await orchestrator.start_conversation(
            audio_input=audio_input,
            on_audio=on_audio,
            on_message=on_message,
        )
        
    except WebSocketDisconnect:
        logger.info(f"[WS] Client disconnected: {session_id}")
    except Exception as e:
        logger.error(f"[WS] Error: {e}")
        try:
            await websocket.send_text(
                msg_error(str(e), "WEBSOCKET_ERROR", session_id).to_json()
            )
        except Exception:
            pass
    finally:
        manager.disconnect(session_id)


# ============================================================
# HEALTH CHECK ENDPOINT
# ============================================================

@router.get("/ws/health")
async def websocket_health():
    """Check WebSocket service health."""
    return {
        "status": "healthy",
        "active_connections": len(manager.active_connections),
        "active_orchestrators": len(manager.orchestrators),
    }


# ============================================================
# METRICS ENDPOINT
# ============================================================

@router.get("/ws/metrics/{session_id}")
async def get_session_metrics(session_id: str):
    """Get metrics for a specific session."""
    orchestrator = manager.get_orchestrator(session_id)
    
    if not orchestrator:
        return {"error": "Session not found"}
    
    return orchestrator.get_metrics()
