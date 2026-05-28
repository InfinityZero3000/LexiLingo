"""
LexiLingo MCP Server - Coding Time Tools
Entry point for Model Context Protocol server, specifically designed for IDE assistance.
"""

import asyncio
import logging
import sys
import json
from pathlib import Path
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp import types

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from tools.i18n_manager import manage_i18n_key
from utils.logger import setup_logger

# Setup logging
logger = setup_logger(__name__)

# Create MCP server instance
server = Server("lexilingo-coding-mcp")

@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """List all available tools for code editors"""
    logger.info("Listing available DEV tools")
    
    return [
        types.Tool(
            name="manage_i18n_key",
            description="Add or update a localization key across all 7 language JSON files in Flutter.",
            inputSchema={
                "type": "object",
                "properties": {
                    "key_path": {
                        "type": "string",
                        "description": "Dot-separated key path, e.g., 'common.buttons.start'",
                    },
                    "english_text": {
                        "type": "string",
                        "description": "The English default text",
                    },
                },
                "required": ["key_path", "english_text"],
            },
        ),
        types.Tool(
            name="query_knowledge_graph",
            description="Query the KuzuDB graph to learn about connected grammar/vocab concepts.",
            inputSchema={
                "type": "object",
                "properties": {
                    "cypher_query": {
                        "type": "string",
                        "description": "Cypher query to execute on KuzuDB (local DB instance)",
                    }
                },
                "required": ["cypher_query"],
            },
        )
    ]

@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict[str, Any] | None
) -> list[types.TextContent]:
    """Handle DEV tool execution"""
    logger.info(f"Tool called: {name}")
    logger.debug(f"Arguments: {arguments}")
    
    if not arguments:
        arguments = {}
        
    try:
        if name == "manage_i18n_key":
            result = manage_i18n_key(arguments.get("key_path", ""), arguments.get("english_text", ""))
        elif name == "query_knowledge_graph":
            # Placeholder for KuzuDB local IDE runner
            result = {"message": f"Simulating query: {arguments.get('cypher_query')}. Implement full KuzuDB connection if needed."}
        else:
            raise ValueError(f"Unknown tool: {name}")
        
        return [types.TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]
    
    except Exception as e:
        logger.error(f"Tool execution error: {e}", exc_info=True)
        return [
            types.TextContent(
                type="text",
                text=json.dumps({"error": str(e), "tool": name}),
            )
        ]

@server.list_resources()
async def handle_list_resources() -> list[types.Resource]:
    """List available resources for coding context"""
    return [
        types.Resource(
            uri="lexilingo://architecture/openapi",
            name="Backend OpenAPI Schema",
            description="Latest FastAPI swagger/openapi specs for the backend",
            mimeType="application/json",
        ),
        types.Resource(
            uri="lexilingo://docs/rules",
            name="Global Rules",
            description="Project coding conventions and rules",
            mimeType="text/markdown",
        ),
    ]

async def main():
    async with stdio_server() as (read_stream, write_stream):
        logger.info("LexiLingo Coding MCP Server started")
        await server.run(read_stream, write_stream, server.create_initialization_options())

if __name__ == "__main__":
    asyncio.run(main())


@server.read_resource()
async def handle_read_resource(uri: str) -> str:
    """Read resource by URI"""
    logger.info(f"Resource requested: {uri}")
    
    try:
        if uri.startswith("learner_profile://"):
            user_id = uri.split("//")[1]
            return await learner_profile.get(user_id)
        
        elif uri.startswith("conversation_history://"):
            session_id = uri.split("//")[1]
            return await conversation.get(session_id)
        
        elif uri.startswith("lesson_context://"):
            lesson_id = uri.split("//")[1]
            return await lesson_context.get(lesson_id)
        
        else:
            raise ValueError(f"Unknown resource URI scheme: {uri}")
    
    except Exception as e:
        logger.error(f"Resource read error: {e}", exc_info=True)
        return json.dumps({"error": str(e), "uri": uri})


async def main():
    """Run MCP server with stdio transport"""
    logger.info("=" * 60)
    logger.info("Starting LexiLingo MCP Server")
    logger.info(f"Version: {config.get('server.version', '1.0.0')}")
    logger.info(f"Transport: {config.get('server.transport', 'stdio')}")
    logger.info("=" * 60)
    
    # Initialize resources (optional preloading)
    # await initialize_resources()
    
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="lexilingo-mcp",
                server_version=config.get("server.version", "1.0.0"),
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}", exc_info=True)
        sys.exit(1)
