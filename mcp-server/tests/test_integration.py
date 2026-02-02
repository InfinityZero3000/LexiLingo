"""Test basic MCP server functionality"""

import pytest
import asyncio
from mcp.client.stdio import stdio_client
from mcp import ClientSession, StdioServerParameters


@pytest.mark.asyncio
async def test_mcp_server_startup():
    """Test that MCP server starts and responds"""
    server_params = StdioServerParameters(
        command="python",
        args=["server.py"],
    )
    
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            
            # Server should respond to initialization
            assert session is not None


@pytest.mark.asyncio
async def test_list_tools():
    """Test listing available tools"""
    server_params = StdioServerParameters(
        command="python",
        args=["server.py"],
    )
    
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            
            tools = await session.list_tools()
            tool_names = [t.name for t in tools.tools]
            
            # Check that core tools are available
            assert "chat_with_ai" in tool_names
            assert "transcribe_audio" in tool_names
            assert "evaluate_grammar" in tool_names


@pytest.mark.asyncio
async def test_list_resources():
    """Test listing available resources"""
    server_params = StdioServerParameters(
        command="python",
        args=["server.py"],
    )
    
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            
            resources = await session.list_resources()
            resource_uris = [r.uri for r in resources.resources]
            
            # Check that core resources are available
            assert any("learner_profile" in uri for uri in resource_uris)
            assert any("conversation_history" in uri for uri in resource_uris)


@pytest.mark.asyncio
async def test_chat_tool():
    """Test chat tool execution"""
    server_params = StdioServerParameters(
        command="python",
        args=["server.py"],
    )
    
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            
            result = await session.call_tool(
                "chat_with_ai",
                {
                    "message": "Hello!",
                    "model": "qwen",
                },
            )
            
            assert result.content
            assert len(result.content) > 0
            # Response should be JSON string
            import json
            response = json.loads(result.content[0].text)
            assert "response" in response or "error" in response


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
