"""
LexiLingo MCP Server
Entry point for Model Context Protocol server
"""

import asyncio
import logging
import sys
from pathlib import Path
from typing import Any

from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
from mcp.server.stdio import stdio_server
from mcp import types

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from tools import chat, stt, pronunciation, tts, knowledge_graph, exercise, grammar
from resources import learner_profile, conversation, lesson_context
from utils.config import Config
from utils.logger import setup_logger

# Setup logging
logger = setup_logger(__name__)

# Load config
config = Config.load("config.yaml")

# Create MCP server instance
server = Server("lexilingo-mcp")


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """List all available tools"""
    logger.info("Listing available tools")
    
    return [
        types.Tool(
            name="chat_with_ai",
            description="Chat with AI tutor using Qwen or Gemini. Provides personalized English learning assistance.",
            inputSchema={
                "type": "object",
                "properties": {
                    "message": {
                        "type": "string",
                        "description": "User's message or question",
                    },
                    "context": {
                        "type": "object",
                        "description": "Conversation context",
                        "properties": {
                            "session_id": {"type": "string"},
                            "user_id": {"type": "string"},
                            "user_level": {
                                "type": "string",
                                "enum": ["A1", "A2", "B1", "B2", "C1", "C2"],
                                "description": "CEFR level",
                            },
                            "lesson_id": {"type": "string"},
                        },
                    },
                    "model": {
                        "type": "string",
                        "enum": ["qwen", "gemini"],
                        "default": "qwen",
                        "description": "AI model to use",
                    },
                },
                "required": ["message"],
            },
        ),
        types.Tool(
            name="transcribe_audio",
            description="Transcribe audio to text using Whisper STT. Returns text and word-level timestamps.",
            inputSchema={
                "type": "object",
                "properties": {
                    "audio_bytes": {
                        "type": "string",
                        "description": "Base64 encoded audio (WAV/MP3)",
                    },
                    "language": {
                        "type": "string",
                        "default": "en",
                        "description": "Language code (en, vi, etc.)",
                    },
                    "return_timestamps": {
                        "type": "boolean",
                        "default": True,
                        "description": "Include word-level timestamps",
                    },
                },
                "required": ["audio_bytes"],
            },
        ),
        types.Tool(
            name="analyze_pronunciation",
            description="Analyze pronunciation accuracy using HuBERT. Returns phoneme-level scores and feedback.",
            inputSchema={
                "type": "object",
                "properties": {
                    "audio_bytes": {
                        "type": "string",
                        "description": "Base64 encoded audio",
                    },
                    "reference_text": {
                        "type": "string",
                        "description": "Expected text to pronounce",
                    },
                    "return_phonemes": {
                        "type": "boolean",
                        "default": True,
                        "description": "Include phoneme-level analysis",
                    },
                },
                "required": ["audio_bytes", "reference_text"],
            },
        ),
        types.Tool(
            name="generate_speech",
            description="Generate speech from text using Piper TTS. Returns audio bytes.",
            inputSchema={
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "Text to convert to speech",
                    },
                    "voice_id": {
                        "type": "string",
                        "default": "en_US-lessac-medium",
                        "description": "Voice identifier",
                    },
                    "speed": {
                        "type": "number",
                        "default": 1.0,
                        "description": "Speech speed (0.5 to 2.0)",
                    },
                },
                "required": ["text"],
            },
        ),
        types.Tool(
            name="query_knowledge_graph",
            description="Query knowledge graph for concept relationships and prerequisites.",
            inputSchema={
                "type": "object",
                "properties": {
                    "concept": {
                        "type": "string",
                        "description": "Concept to query (e.g., 'present perfect')",
                    },
                    "relation_type": {
                        "type": "string",
                        "enum": ["prerequisite", "related", "all"],
                        "default": "all",
                        "description": "Type of relations to retrieve",
                    },
                    "depth": {
                        "type": "integer",
                        "default": 2,
                        "description": "Depth of graph traversal",
                    },
                },
                "required": ["concept"],
            },
        ),
        types.Tool(
            name="generate_exercise",
            description="Generate exercise based on concept and difficulty level.",
            inputSchema={
                "type": "object",
                "properties": {
                    "concept": {
                        "type": "string",
                        "description": "Grammar/vocab concept",
                    },
                    "difficulty": {
                        "type": "string",
                        "enum": ["easy", "medium", "hard"],
                        "description": "Difficulty level",
                    },
                    "exercise_type": {
                        "type": "string",
                        "enum": ["mcq", "fill_blank", "translation", "reorder"],
                        "description": "Type of exercise",
                    },
                    "count": {
                        "type": "integer",
                        "default": 1,
                        "description": "Number of exercises to generate",
                    },
                },
                "required": ["concept", "difficulty", "exercise_type"],
            },
        ),
        types.Tool(
            name="evaluate_grammar",
            description="Evaluate grammar and provide corrections with explanations.",
            inputSchema={
                "type": "object",
                "properties": {
                    "sentence": {
                        "type": "string",
                        "description": "Sentence to evaluate",
                    },
                    "detailed": {
                        "type": "boolean",
                        "default": True,
                        "description": "Include detailed explanations",
                    },
                    "user_level": {
                        "type": "string",
                        "enum": ["A1", "A2", "B1", "B2", "C1", "C2"],
                        "description": "User's CEFR level for appropriate explanations",
                    },
                },
                "required": ["sentence"],
            },
        ),
    ]


@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict[str, Any] | None
) -> list[types.TextContent | types.ImageContent]:
    """Handle tool execution"""
    logger.info(f"Tool called: {name}")
    logger.debug(f"Arguments: {arguments}")
    
    try:
        # Route to appropriate tool
        if name == "chat_with_ai":
            result = await chat.execute(arguments or {})
        elif name == "transcribe_audio":
            result = await stt.execute(arguments or {})
        elif name == "analyze_pronunciation":
            result = await pronunciation.execute(arguments or {})
        elif name == "generate_speech":
            result = await tts.execute(arguments or {})
        elif name == "query_knowledge_graph":
            result = await knowledge_graph.execute(arguments or {})
        elif name == "generate_exercise":
            result = await exercise.execute(arguments or {})
        elif name == "evaluate_grammar":
            result = await grammar.execute(arguments or {})
        else:
            raise ValueError(f"Unknown tool: {name}")
        
        # Return result as text
        import json
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
    """List available resources"""
    logger.info("Listing available resources")
    
    return [
        types.Resource(
            uri="learner_profile://{user_id}",
            name="Learner Profile",
            description="User's learning profile, preferences, and progress",
            mimeType="application/json",
        ),
        types.Resource(
            uri="conversation_history://{session_id}",
            name="Conversation History",
            description="Chat history and context for a session",
            mimeType="application/json",
        ),
        types.Resource(
            uri="lesson_context://{lesson_id}",
            name="Lesson Context",
            description="Current lesson vocabulary, grammar points, and objectives",
            mimeType="application/json",
        ),
    ]


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
