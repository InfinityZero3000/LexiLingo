"""
Simple WebSocket endpoint for testing

Minimal WebSocket implementation without heavy dependencies.
For production dual-stream testing.
"""

import asyncio
import json
import logging
from typing import Dict

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ws", tags=["WebSocket"])


# Simple connection manager
class SimpleConnectionManager:
    """Lightweight connection manager."""
    
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
    
    async def connect(self, websocket: WebSocket, session_id: str):
        """Accept connection."""
        await websocket.accept()
        self.active_connections[session_id] = websocket
        logger.info(f"[WS] Connected: {session_id} (total: {len(self.active_connections)})")
    
    def disconnect(self, session_id: str):
        """Remove connection."""
        self.active_connections.pop(session_id, None)
        logger.info(f"[WS] Disconnected: {session_id} (total: {len(self.active_connections)})")
    
    async def send_json(self, session_id: str, data: dict):
        """Send JSON message."""
        websocket = self.active_connections.get(session_id)
        if websocket:
            await websocket.send_json(data)
    
    async def send_bytes(self, session_id: str, data: bytes):
        """Send binary data."""
        websocket = self.active_connections.get(session_id)
        if websocket:
            await websocket.send_bytes(data)


manager = SimpleConnectionManager()


@router.websocket("/conversation/stream")
async def websocket_conversation_stream(
    websocket: WebSocket,
    session_id: str = Query(default="default"),
    user_id: str = Query(default="guest"),
):
    """
    Simple WebSocket endpoint for dual-stream testing.
    
    Protocol:
    - Client → Server: Binary audio chunks or JSON control messages
    - Server → Client: JSON status messages + Binary audio chunks
    
    Messages:
    - {"type": "connected"} - Connection established
    - {"type": "audio_start"} - Audio recording started
    - {"type": "audio_stop"} - Audio recording stopped
    - {"type": "stt_partial", "text": "..."} - Partial STT result
    - {"type": "stt_final", "text": "..."} - Final STT result
    - {"type": "ai_thinking"} - AI processing
    - {"type": "ai_response", "text": "..."} - AI text response
    - {"type": "tts_start"} - TTS audio starting
    - {"type": "tts_chunk"} - Audio chunk (binary)
    - {"type": "tts_end"} - TTS complete
    - {"type": "error", "message": "..."} - Error occurred
    """
    
    try:
        # Connect
        await manager.connect(websocket, session_id)
        
        # Send connected message
        await manager.send_json(session_id, {
            "type": "connected",
            "session_id": session_id,
            "user_id": user_id,
            "message": "WebSocket connected successfully",
        })
        
        # Main message loop
        while True:
            # Receive data (binary or text)
            try:
                data = await websocket.receive()
                
                # Handle text/JSON messages
                if "text" in data:
                    message = json.loads(data["text"])
                    await handle_json_message(session_id, message)
                
                # Handle binary audio data
                elif "bytes" in data:
                    audio_data = data["bytes"]
                    await handle_audio_data(session_id, audio_data)
                
            except json.JSONDecodeError as e:
                await manager.send_json(session_id, {
                    "type": "error",
                    "message": f"Invalid JSON: {e}",
                })
            
    except WebSocketDisconnect:
        logger.info(f"[WS] Client disconnected: {session_id}")
        manager.disconnect(session_id)
    
    except Exception as e:
        logger.error(f"[WS] Error in session {session_id}: {e}", exc_info=True)
        await manager.send_json(session_id, {
            "type": "error",
            "message": str(e),
        })
        manager.disconnect(session_id)


async def handle_json_message(session_id: str, message: dict):
    """Handle JSON control messages from client."""
    
    msg_type = message.get("type", "")
    
    if msg_type == "start_recording":
        # Client started recording
        await manager.send_json(session_id, {
            "type": "audio_start",
            "message": "Recording started",
        })
        logger.info(f"[WS] {session_id}: Recording started")
    
    elif msg_type == "stop_recording":
        # Client stopped recording
        await manager.send_json(session_id, {
            "type": "audio_stop",
            "message": "Recording stopped",
        })
        logger.info(f"[WS] {session_id}: Recording stopped")
    
    elif msg_type == "ping":
        # Heartbeat
        await manager.send_json(session_id, {
            "type": "pong",
            "timestamp": message.get("timestamp"),
        })
    
    else:
        logger.warning(f"[WS] {session_id}: Unknown message type: {msg_type}")


async def handle_audio_data(session_id: str, audio_data: bytes):
    """
    Handle binary audio data from client.
    
    In production:
    1. Process audio with STT (streaming)
    2. Send partial/final transcripts
    3. Generate AI response
    4. Stream TTS audio back
    
    For testing:
    - Echo back mock responses
    """
    
    audio_size_kb = len(audio_data) / 1024
    logger.info(f"[WS] {session_id}: Received {audio_size_kb:.1f}KB audio")
    
    # Send STT partial result (mock)
    await manager.send_json(session_id, {
        "type": "stt_partial",
        "text": "Hello...",
        "confidence": 0.85,
    })
    
    await asyncio.sleep(0.1)
    
    # Send STT final result (mock)
    await manager.send_json(session_id, {
        "type": "stt_final",
        "text": "Hello, I would like to practice English",
        "confidence": 0.92,
    })
    
    # Send AI thinking
    await manager.send_json(session_id, {
        "type": "ai_thinking",
        "message": "Processing...",
    })
    
    await asyncio.sleep(0.3)
    
    # Send AI response
    await manager.send_json(session_id, {
        "type": "ai_response",
        "text": "Great! I'm happy to help you practice English. What would you like to talk about?",
    })
    
    # Send TTS start
    await manager.send_json(session_id, {
        "type": "tts_start",
        "message": "Generating speech...",
    })
    
    # Simulate TTS chunks (mock audio data)
    for i in range(3):
        await asyncio.sleep(0.15)
        mock_audio = b'\x00' * 4096  # Mock audio chunk
        await manager.send_bytes(session_id, mock_audio)
        await manager.send_json(session_id, {
            "type": "tts_chunk",
            "chunk_index": i,
            "total_chunks": 3,
        })
    
    # Send TTS end
    await manager.send_json(session_id, {
        "type": "tts_end",
        "message": "Speech complete",
    })
    
    logger.info(f"[WS] {session_id}: Mock conversation complete")
