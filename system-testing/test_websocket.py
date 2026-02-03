#!/usr/bin/env python3
"""
Quick WebSocket test for dual-stream endpoint
"""

import asyncio
import websockets
import json

async def test_websocket():
    uri = 'ws://localhost:8001/ws/conversation/stream?session_id=test456'
    
    try:
        async with websockets.connect(uri, open_timeout=3) as ws:
            print('🔌 Connecting...')
            
            # Nhận connected message
            msg1 = await asyncio.wait_for(ws.recv(), timeout=2)
            data1 = json.loads(msg1)
            print(f'✅ Connected: {data1.get("type")}')
            print(f'   Session: {data1.get("session_id")}')
            
            # Gửi fake audio data
            print('\n📤 Sending audio chunk...')
            await ws.send(b'\x00' * 1024)
            
            # Nhận các response messages
            print('\n📥 Receiving responses:')
            for i in range(10):
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=0.5)
                    
                    if isinstance(msg, bytes):
                        print(f'   🔊 Binary audio: {len(msg)} bytes')
                    else:
                        data = json.loads(msg)
                        msg_type = data.get('type')
                        text = data.get('text', data.get('message', ''))
                        
                        if msg_type == 'stt_partial':
                            print(f'   🎤 [Partial] {text}')
                        elif msg_type == 'stt_final':
                            print(f'   🎤 [Final] {text}')
                        elif msg_type == 'ai_thinking':
                            print(f'   🤔 Thinking...')
                        elif msg_type == 'ai_response':
                            print(f'   💬 Response: {text}')
                        elif msg_type == 'tts_start':
                            print(f'   🔊 TTS starting...')
                        elif msg_type == 'tts_chunk':
                            print(f'   🎵 TTS chunk {data.get("chunk_index", 0) + 1}/{data.get("total_chunks", 0)}')
                        elif msg_type == 'tts_end':
                            print(f'   ✅ TTS complete')
                        else:
                            print(f'   📦 {msg_type}: {text[:50]}')
                            
                except asyncio.TimeoutError:
                    break
            
            print('\n✅ Test completed successfully!')
            return True
            
    except Exception as e:
        print(f'\n❌ Test failed: {e}')
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    result = asyncio.run(test_websocket())
    exit(0 if result else 1)
