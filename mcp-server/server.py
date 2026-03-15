from mcp.server.fastmcp import FastMCP
from datetime import datetime, timezone
import socket

mcp = FastMCP("Demo MCP Server", host="0.0.0.0", port=3333)


@mcp.tool()
def get_current_time(timezone_name: str = "UTC") -> str:
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(timezone.utc).isoformat()


@mcp.tool()
def get_runtime_info() -> dict:
    """Return container runtime information."""
    return {
        "hostname": socket.gethostname(),
        "version": "1.0.0",
    }


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
