"""
MCP Server

Model Context Protocol server implementation for LexiLingo.
Provides standardized interface for AI assistants to interact
with the English tutoring system.
"""

import json
import logging
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from api.mcp.tools import TOOL_DEFINITIONS, get_tool_handler
from api.mcp.resources import RESOURCE_TEMPLATES, get_resource_handler

logger = logging.getLogger(__name__)


# ============================================================
# MCP PROTOCOL MESSAGES
# ============================================================


class MCPRequest(BaseModel):
    """MCP request envelope."""
    jsonrpc: str = "2.0"
    id: Optional[str] = None
    method: str
    params: Optional[Dict[str, Any]] = None


class MCPResponse(BaseModel):
    """MCP response envelope."""
    jsonrpc: str = "2.0"
    id: Optional[str] = None
    result: Optional[Any] = None
    error: Optional[Dict[str, Any]] = None


class MCPError(BaseModel):
    """MCP error structure."""
    code: int
    message: str
    data: Optional[Any] = None


# Error codes (JSON-RPC 2.0 + MCP extensions)
class ErrorCode:
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    TOOL_NOT_FOUND = -32001
    RESOURCE_NOT_FOUND = -32002


# ============================================================
# MCP SERVER
# ============================================================


class MCPServer:
    """
    MCP Server implementation.

    Implements the Model Context Protocol for exposing
    LexiLingo AI capabilities to external clients.

    Protocol methods:
    - initialize: Negotiate capabilities
    - tools/list: List available tools
    - tools/call: Call a tool
    - resources/list: List available resources
    - resources/read: Read a resource
    """

    def __init__(self):
        self.tool_handler = get_tool_handler()
        self.resource_handler = get_resource_handler()
        self.server_info = {
            "name": "lexilingo-mcp",
            "version": "1.0.0",
            "capabilities": {
                "tools": True,
                "resources": True,
                "prompts": False,
            },
        }

    async def handle_request(self, request: MCPRequest) -> MCPResponse:
        """
        Handle incoming MCP request.

        Args:
            request: MCP request

        Returns:
            MCP response
        """
        try:
            method_handlers = {
                "initialize": self._handle_initialize,
                "tools/list": self._handle_tools_list,
                "tools/call": self._handle_tools_call,
                "resources/list": self._handle_resources_list,
                "resources/read": self._handle_resources_read,
                "ping": self._handle_ping,
            }

            handler = method_handlers.get(request.method)
            if not handler:
                return MCPResponse(
                    id=request.id,
                    error={
                        "code": ErrorCode.METHOD_NOT_FOUND,
                        "message": f"Method not found: {request.method}",
                    },
                )

            result = await handler(request.params or {})
            return MCPResponse(id=request.id, result=result)

        except Exception as e:
            logger.error(f"MCP request failed: {e}")
            return MCPResponse(
                id=request.id,
                error={
                    "code": ErrorCode.INTERNAL_ERROR,
                    "message": str(e),
                },
            )

    async def _handle_initialize(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle initialize request."""
        client_info = params.get("clientInfo", {})
        logger.info(f"MCP client connected: {client_info.get('name', 'unknown')}")

        return {
            "protocolVersion": "2024-11-05",
            "serverInfo": self.server_info,
            "capabilities": self.server_info["capabilities"],
        }

    async def _handle_tools_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle tools/list request."""
        return {"tools": TOOL_DEFINITIONS}

    async def _handle_tools_call(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle tools/call request."""
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        if not tool_name:
            raise ValueError("Tool name is required")

        # Check if tool exists
        tool_exists = any(t["name"] == tool_name for t in TOOL_DEFINITIONS)
        if not tool_exists:
            return {
                "isError": True,
                "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}],
            }

        result = await self.tool_handler.handle_tool(tool_name, arguments)

        if "error" in result:
            return {
                "isError": True,
                "content": [{"type": "text", "text": result["error"]}],
            }

        return {
            "content": [{"type": "text", "text": json.dumps(result, indent=2)}],
        }

    async def _handle_resources_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle resources/list request."""
        resources = await self.resource_handler.list_resources()
        return {"resources": resources}

    async def _handle_resources_read(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle resources/read request."""
        uri = params.get("uri")
        if not uri:
            raise ValueError("Resource URI is required")

        result = await self.resource_handler.read_resource(uri)

        if "error" in result:
            return {
                "isError": True,
                "content": [{"type": "text", "text": result["error"]}],
            }

        return {
            "contents": [{
                "uri": uri,
                "mimeType": "application/json",
                "text": json.dumps(result.get("contents", {}), indent=2),
            }],
        }

    async def _handle_ping(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle ping request."""
        return {"status": "ok"}


# ============================================================
# SINGLETON
# ============================================================

_server: Optional[MCPServer] = None


def get_mcp_server() -> MCPServer:
    """Get MCP server singleton."""
    global _server
    if _server is None:
        _server = MCPServer()
    return _server
