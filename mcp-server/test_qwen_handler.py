#!/usr/bin/env python3
"""
Test Qwen Handler with Ollama integration
"""

import asyncio
import logging
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from handlers.qwen import QwenHandler
from utils.config import Config

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def test_qwen():
    """Test Qwen handler"""
    print("\n" + "="*60)
    print("Testing Qwen Handler with Ollama")
    print("="*60 + "\n")
    
    # Load config
    config = Config.load("config.yaml")
    qwen_config = config.get("models.qwen", {})
    
    print(f"Config:")
    print(f"  - Model: {qwen_config.get('model')}")
    print(f"  - Base URL: {qwen_config.get('base_url')}")
    print(f"  - Timeout: {qwen_config.get('timeout')}s")
    print()
    
    # Initialize handler
    handler = QwenHandler(qwen_config)
    
    try:
        # Load handler
        print("1. Loading Qwen handler...")
        await handler.load()
        print("   ✓ Handler loaded\n")
        
        # Test simple chat
        print("2. Testing chat with simple question...")
        test_message = "What is the difference between 'affect' and 'effect'?"
        test_context = {
            "user_level": "B2",
            "session_id": "test-session-001"
        }
        
        print(f"   Question: {test_message}")
        print(f"   Context: {test_context}")
        print()
        
        response = await handler.chat(test_message, test_context)
        
        print("   Response:")
        print(f"   - Text: {response.get('text', '')[:200]}...")
        print(f"   - Confidence: {response.get('confidence')}")
        print(f"   - Suggestions: {response.get('suggestions')}")
        print(f"   - Model: {response.get('model')}")
        print("   ✓ Chat successful\n")
        
        # Test another question
        print("3. Testing with grammar correction...")
        test_message2 = "Can you help me correct this sentence: 'She don't like apples'"
        
        print(f"   Question: {test_message2}")
        print()
        
        response2 = await handler.chat(test_message2, test_context)
        
        print("   Response:")
        print(f"   - Text: {response2.get('text', '')[:200]}...")
        print("   ✓ Chat successful\n")
        
        print("="*60)
        print("✅ ALL TESTS PASSED")
        print("="*60)
        
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        logger.error("Test failed", exc_info=True)
        sys.exit(1)
    
    finally:
        # Cleanup
        await handler.unload()
        print("\n✓ Handler unloaded")


if __name__ == "__main__":
    asyncio.run(test_qwen())
