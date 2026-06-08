"""
LexiLingo MCP Server
Provides tools for IDE assistance: i18n management, web search, backend schema, Flutter utilities.
"""

import asyncio
import json
import logging
import sys
from pathlib import Path
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.server.models import InitializationOptions
from mcp.server import NotificationOptions
from mcp import types

sys.path.insert(0, str(Path(__file__).parent))

from tools.i18n_manager import manage_i18n_key
from tools.web_search import search_web
from tools.backend_schema import get_backend_schema
from tools.flutter_utils import list_flutter_screens
from resources import learner_profile, conversation, lesson_context
from utils.logger import setup_logger

logger = setup_logger(__name__)
server = Server("lexilingo-mcp")


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="manage_i18n_key",
            description="Add or update a localization key across all 7 language JSON files in Flutter app.",
            inputSchema={
                "type": "object",
                "properties": {
                    "key_path": {
                        "type": "string",
                        "description": "Dot-separated key path, e.g. 'common.buttons.start'",
                    },
                    "english_text": {
                        "type": "string",
                        "description": "The English default text for this key",
                    },
                },
                "required": ["key_path", "english_text"],
            },
        ),
        types.Tool(
            name="search_web",
            description=(
                "Search the web via Tavily for up-to-date information. "
                "Use for Flutter/Dart docs, package versions, language learning best practices, "
                "IELTS/CEFR references, or any real-time information."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Number of results to return (default: 5, max: 10)",
                        "default": 5,
                    },
                    "search_depth": {
                        "type": "string",
                        "enum": ["basic", "advanced"],
                        "description": "basic = fast, advanced = deeper (costs more API credits)",
                        "default": "basic",
                    },
                },
                "required": ["query"],
            },
        ),
        types.Tool(
            name="get_backend_schema",
            description=(
                "Get the FastAPI backend OpenAPI schema. Returns endpoints, request/response models. "
                "Use before implementing Flutter API calls to ensure correct types and routes."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "filter_path": {
                        "type": "string",
                        "description": "Optional path prefix to filter endpoints, e.g. '/vocabulary' or '/games'",
                    }
                },
                "required": [],
            },
        ),
        types.Tool(
            name="list_flutter_screens",
            description=(
                "List all Flutter screens/pages in the app with their file paths and route names. "
                "Use to understand navigation structure before adding new screens."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "feature": {
                        "type": "string",
                        "description": "Optional feature folder to filter by, e.g. 'games', 'learning', 'auth'",
                    }
                },
                "required": [],
            },
        ),
    ]


@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict[str, Any] | None
) -> list[types.TextContent]:
    logger.info(f"Tool called: {name} | args: {arguments}")

    if not arguments:
        arguments = {}

    try:
        if name == "manage_i18n_key":
            result = manage_i18n_key(
                arguments["key_path"],
                arguments["english_text"],
            )
        elif name == "search_web":
            result = await search_web(
                query=arguments["query"],
                max_results=arguments.get("max_results", 5),
                search_depth=arguments.get("search_depth", "basic"),
            )
        elif name == "get_backend_schema":
            result = get_backend_schema(
                filter_path=arguments.get("filter_path"),
            )
        elif name == "list_flutter_screens":
            result = list_flutter_screens(
                feature=arguments.get("feature"),
            )
        else:
            raise ValueError(f"Unknown tool: {name}")

        return [types.TextContent(type="text", text=json.dumps(result, ensure_ascii=False, indent=2))]

    except Exception as e:
        logger.error(f"Tool error [{name}]: {e}", exc_info=True)
        return [
            types.TextContent(
                type="text",
                text=json.dumps({"error": str(e), "tool": name}, ensure_ascii=False),
            )
        ]


@server.list_resources()
async def handle_list_resources() -> list[types.Resource]:
    return [
        types.Resource(
            uri="lexilingo://learner_profile/{user_id}",
            name="Learner Profile",
            description="User profile with CEFR level, weak areas, and progress",
            mimeType="application/json",
        ),
        types.Resource(
            uri="lexilingo://conversation/{session_id}",
            name="Conversation History",
            description="AI conversation history for a session",
            mimeType="application/json",
        ),
        types.Resource(
            uri="lexilingo://lesson_context/{lesson_id}",
            name="Lesson Context",
            description="Active lesson content and vocabulary",
            mimeType="application/json",
        ),
    ]


@server.read_resource()
async def handle_read_resource(uri: str) -> str:
    logger.info(f"Resource requested: {uri}")

    try:
        if uri.startswith("lexilingo://learner_profile/"):
            user_id = uri.split("/")[-1]
            return await learner_profile.get(user_id)
        elif uri.startswith("lexilingo://conversation/"):
            session_id = uri.split("/")[-1]
            return await conversation.get(session_id)
        elif uri.startswith("lexilingo://lesson_context/"):
            lesson_id = uri.split("/")[-1]
            return await lesson_context.get(lesson_id)
        else:
            raise ValueError(f"Unknown resource URI: {uri}")

    except Exception as e:
        logger.error(f"Resource error [{uri}]: {e}", exc_info=True)
        return json.dumps({"error": str(e), "uri": uri})


async def main():
    logger.info("LexiLingo MCP Server starting...")
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="lexilingo-mcp",
                server_version="1.1.0",
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
        logger.info("Server stopped")
    except Exception as e:
        logger.error(f"Server error: {e}", exc_info=True)
        sys.exit(1)
