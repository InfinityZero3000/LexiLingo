
import asyncio
import sys
import os
from pathlib import Path

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).parent))

from api.services.trace_cag.nodes_v2 import retrieve_node
from api.services.trace_cag.state import TraceCAGState

async def test_dynamic_intent():
    print("\n--- TEST 1: Common Greeting (Should NOT force search) ---")
    state1 = TraceCAGState(user_input="Hello, how are you?")
    # Pass a dummy docs service if needed, but retrieve_node calls get_doc_intel_service() internally
    # We just want to see the logs
    await retrieve_node(state1)
    
    print("\n--- TEST 2: Dynamic Intent (Should force search) ---")
    state2 = TraceCAGState(user_input="Bạn có biết tin tức về ông Elon Musk mới đây không?")
    await retrieve_node(state2)

    print("\n--- TEST 3: Specific Tech (Clawbot) ---")
    state3 = TraceCAGState(user_input="Do you know the latest technology called Clawbot?")
    await retrieve_node(state3)

if __name__ == "__main__":
    # Mock environment variables
    os.environ["TAVILY_API_KEY"] = "mock_key"
    asyncio.run(test_dynamic_intent())
