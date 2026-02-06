"""
MCP Routes

FastAPI routes for MCP protocol over HTTP.
"""

import logging
from typing import Any, Dict

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from api.mcp.server import get_mcp_server, MCPRequest, MCPResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/mcp", tags=["MCP"])


# ============================================================
# HTTP ENDPOINTS
# ============================================================


class MCPHttpRequest(BaseModel):
    """HTTP wrapper for MCP request."""
    jsonrpc: str = "2.0"
    id: str = "1"
    method: str
    params: Dict[str, Any] = {}


@router.post(
    "/",
    summary="MCP Protocol Endpoint",
    description="""
    Model Context Protocol endpoint for AI assistants.
    
    **Supported methods:**
    - `initialize` - Initialize connection
    - `tools/list` - List available tools
    - `tools/call` - Call a tool
    - `resources/list` - List available resources
    - `resources/read` - Read a resource
    - `ping` - Health check
    """,
)
async def mcp_endpoint(request: MCPHttpRequest):
    """Handle MCP requests over HTTP."""
    try:
        server = get_mcp_server()
        mcp_request = MCPRequest(
            jsonrpc=request.jsonrpc,
            id=request.id,
            method=request.method,
            params=request.params,
        )
        
        response = await server.handle_request(mcp_request)
        return response.model_dump(exclude_none=True)
        
    except Exception as e:
        logger.error(f"MCP endpoint error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/tools", summary="List MCP Tools")
async def list_tools():
    """List all available MCP tools."""
    server = get_mcp_server()
    mcp_request = MCPRequest(method="tools/list")
    response = await server.handle_request(mcp_request)
    return response.result


@router.get("/resources", summary="List MCP Resources")
async def list_resources():
    """List all available MCP resources."""
    server = get_mcp_server()
    mcp_request = MCPRequest(method="resources/list")
    response = await server.handle_request(mcp_request)
    return response.result


@router.post("/tools/{tool_name}", summary="Call MCP Tool")
async def call_tool(tool_name: str, arguments: Dict[str, Any] = {}):
    """Call a specific MCP tool."""
    server = get_mcp_server()
    mcp_request = MCPRequest(
        method="tools/call",
        params={"name": tool_name, "arguments": arguments},
    )
    response = await server.handle_request(mcp_request)
    
    if response.error:
        raise HTTPException(status_code=400, detail=response.error)
    
    return response.result


@router.get("/resources/{resource_uri:path}", summary="Read MCP Resource")
async def read_resource(resource_uri: str):
    """Read a specific MCP resource."""
    server = get_mcp_server()
    mcp_request = MCPRequest(
        method="resources/read",
        params={"uri": resource_uri},
    )
    response = await server.handle_request(mcp_request)
    
    if response.error:
        raise HTTPException(status_code=404, detail=response.error)
    
    return response.result


# ============================================================
# WEBSOCKET ENDPOINT (for persistent connections)
# ============================================================


@router.websocket("/ws")
async def mcp_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for MCP protocol.
    
    Allows persistent bidirectional communication.
    """
    await websocket.accept()
    server = get_mcp_server()
    
    logger.info("MCP WebSocket client connected")
    
    try:
        while True:
            data = await websocket.receive_json()
            
            try:
                mcp_request = MCPRequest(**data)
                response = await server.handle_request(mcp_request)
                await websocket.send_json(response.model_dump(exclude_none=True))
                
            except Exception as e:
                error_response = MCPResponse(
                    id=data.get("id"),
                    error={"code": -32603, "message": str(e)},
                )
                await websocket.send_json(error_response.model_dump(exclude_none=True))
                
    except WebSocketDisconnect:
        logger.info("MCP WebSocket client disconnected")
    except Exception as e:
        logger.error(f"MCP WebSocket error: {e}")


# ============================================================
# HEALTH CHECK
# ============================================================


@router.get("/health", summary="MCP Health Check")
async def mcp_health():
    """Check MCP server health."""
    server = get_mcp_server()
    return {
        "status": "healthy",
        "server_info": server.server_info,
        "tools_count": 5,
        "resources_count": 4,
    }
