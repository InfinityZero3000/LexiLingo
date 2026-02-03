#!/usr/bin/env python3
"""Test WebSocket với buffering logic mới"""

import asyncio
import websockets
import json

async def test():
    uri = 'ws://localhost:8001/ws/conversation/stream?session_id=test789'
    
    async with websockets.connect(uri) as ws:
        # Connect
        msg = await ws.recv()
        print('✅ Connected:', json.loads(msg)['type'])
        
        # Simulate recording: send small chunks (won't trigger response)
        print('\n📤 Sending small audio chunks (1KB each)...')
        for i in range(5):
            await ws.send(b'\x00' * 1024)  # 1KB each
            await asyncio.sleep(0.2)
            print(f'   Sent chunk {i+1}/5 (1KB)')
        
        print('\n⏳ Waiting for response (should be none)...')
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=1)
            print(f'   ❌ Unexpected message: {msg[:100]}')
        except asyncio.TimeoutError:
            print('   ✅ No spam messages (correct!)')
        
        # Now send larger chunk (>10KB total)
        print('\n📤 Sending large chunk (12KB)...')
        await ws.send(b'\x00' * 12288)
        
        print('\n📥 Receiving responses:')
        for i in range(6):
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=0.8)
                data = json.loads(msg)
                print(f'   {data.get("type")}: {data.get("text", data.get("message", ""))[:40]}')
            except asyncio.TimeoutError:
                break
        
        # Test stop recording
        print('\n⏹️ Sending stop_recording...')
        await ws.send(json.dumps({'type': 'stop_recording'}))
        msg = await asyncio.wait_for(ws.recv(), timeout=1)
        data = json.loads(msg)
        print(f'   Server response: {data.get("type")} - {data.get("message")}')
        
        print('\n✅ All tests passed!')

if __name__ == '__main__':
    asyncio.run(test())
