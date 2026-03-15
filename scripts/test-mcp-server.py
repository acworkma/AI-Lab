#!/usr/bin/env python3
"""
test-mcp-server.py - Functional validation for the MCP server on ACA

Calls MCP tools via streamable HTTP transport and validates responses.
Uses stdlib only (no third-party dependencies) for portability.

Usage:
    python3 scripts/test-mcp-server.py --endpoint https://mcp-server.<aca-domain>
    python3 scripts/test-mcp-server.py --endpoint https://mcp-server.<aca-domain> --allow-public-dns

Prerequisites:
    - MCP server deployed to ACA (run scripts/deploy-mcp-server.sh first)
    - VPN connection established

Exit codes:
    0  All tests passed
    1  Unexpected error
    3  Runtime / Azure CLI error
    4  DNS resolution failed
    5  MCP server connection failed
    6  Tool invocation failed
"""

import argparse
import ipaddress
import json
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def log(level: str, message: str) -> None:
    print(f"[{level}] {message}")


def run_az(args: list[str]) -> str:
    process = subprocess.run(
        ["az", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        stderr = process.stderr.strip() or "Unknown Azure CLI error"
        raise RuntimeError(stderr)
    return process.stdout.strip()


def discover_app_fqdn(app_name: str, resource_group: str) -> str:
    """Auto-discover the container app FQDN from Azure."""
    fqdn = run_az([
        "containerapp", "show",
        "--name", app_name,
        "--resource-group", resource_group,
        "--query", "properties.configuration.ingress.fqdn",
        "-o", "tsv",
    ])
    if not fqdn:
        raise RuntimeError(f"No FQDN found for container app '{app_name}' in '{resource_group}'")
    return fqdn


def resolve_host(endpoint: str, require_private_dns: bool) -> tuple[str, str]:
    """Resolve the endpoint hostname and optionally verify it's a private IP."""
    host = urllib.parse.urlparse(endpoint).hostname
    if not host:
        raise RuntimeError(f"Invalid endpoint URL: {endpoint}")

    resolved_ip = socket.gethostbyname(host)
    ip = ipaddress.ip_address(resolved_ip)
    if require_private_dns and not ip.is_private:
        raise RuntimeError(f"Host '{host}' resolved to non-private IP {resolved_ip}")
    return host, resolved_ip


def mcp_initialize(endpoint: str, timeout: int) -> tuple[str, dict]:
    """
    Send an MCP initialize request and return the session ID and response.

    Uses the streamable HTTP transport: POST to /mcp with JSON-RPC.
    """
    url = f"{endpoint}/mcp"

    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {
                "name": "test-mcp-server",
                "version": "1.0.0",
            },
        },
    }

    request = urllib.request.Request(
        url=url,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        },
        data=json.dumps(payload).encode("utf-8"),
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            session_id = response.headers.get("Mcp-Session-Id", "")
            body = response.read().decode("utf-8")

            # Handle SSE response format
            if "text/event-stream" in response.headers.get("Content-Type", ""):
                return session_id, _parse_sse_response(body)

            return session_id, json.loads(body)
    except urllib.error.HTTPError as error:
        error_body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Initialize failed (HTTP {error.code}): {error_body}")


def mcp_initialized_notification(endpoint: str, session_id: str, timeout: int) -> None:
    """Send the initialized notification to complete the handshake."""
    url = f"{endpoint}/mcp"

    payload = {
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
    }

    request = urllib.request.Request(
        url=url,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Mcp-Session-Id": session_id,
        },
        data=json.dumps(payload).encode("utf-8"),
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response.read()
    except urllib.error.HTTPError as error:
        # 202 Accepted is fine for notifications
        if error.code not in (200, 202, 204):
            raise


def mcp_call_tool(endpoint: str, session_id: str, tool_name: str, arguments: dict, request_id: int, timeout: int) -> dict:
    """Call an MCP tool and return the result."""
    url = f"{endpoint}/mcp"

    payload = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": arguments,
        },
    }

    request = urllib.request.Request(
        url=url,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Mcp-Session-Id": session_id,
        },
        data=json.dumps(payload).encode("utf-8"),
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")

            if "text/event-stream" in response.headers.get("Content-Type", ""):
                return _parse_sse_response(body)

            return json.loads(body)
    except urllib.error.HTTPError as error:
        error_body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Tool call '{tool_name}' failed (HTTP {error.code}): {error_body}")


def _parse_sse_response(body: str) -> dict:
    """Parse a Server-Sent Events response to extract JSON-RPC message."""
    for line in body.strip().split("\n"):
        line = line.strip()
        if line.startswith("data:"):
            data = line[5:].strip()
            if data:
                return json.loads(data)
    raise RuntimeError(f"No data event found in SSE response: {body[:200]}")


def extract_tool_result_text(response: dict) -> str:
    """Extract text content from an MCP tool result response."""
    result = response.get("result", {})
    content = result.get("content", [])
    texts = []
    for item in content:
        if item.get("type") == "text":
            texts.append(item.get("text", ""))
    return "\n".join(texts)


def test_get_current_time(endpoint: str, session_id: str, timeout: int) -> bool:
    """Test the get_current_time tool."""
    log("TEST", "Calling get_current_time...")

    try:
        response = mcp_call_tool(endpoint, session_id, "get_current_time", {}, 2, timeout)

        if "error" in response:
            log("FAIL", f"get_current_time returned error: {response['error']}")
            return False

        text = extract_tool_result_text(response)
        if not text:
            log("FAIL", "get_current_time returned empty result")
            return False

        # Validate ISO 8601 format (should contain T and digits)
        if "T" in text and any(c.isdigit() for c in text):
            log("PASS", f"get_current_time returned: {text}")
            return True
        else:
            log("FAIL", f"get_current_time returned non-ISO value: {text}")
            return False

    except Exception as e:
        log("FAIL", f"get_current_time failed: {e}")
        return False


def test_get_runtime_info(endpoint: str, session_id: str, timeout: int) -> bool:
    """Test the get_runtime_info tool."""
    log("TEST", "Calling get_runtime_info...")

    try:
        response = mcp_call_tool(endpoint, session_id, "get_runtime_info", {}, 3, timeout)

        if "error" in response:
            log("FAIL", f"get_runtime_info returned error: {response['error']}")
            return False

        text = extract_tool_result_text(response)
        if not text:
            log("FAIL", "get_runtime_info returned empty result")
            return False

        # Parse the result as JSON
        info = json.loads(text)

        has_hostname = "hostname" in info and isinstance(info["hostname"], str) and len(info["hostname"]) > 0
        has_version = "version" in info and info["version"] == "1.0.0"

        if has_hostname and has_version:
            log("PASS", f"get_runtime_info returned: hostname={info['hostname']}, version={info['version']}")
            return True
        else:
            log("FAIL", f"get_runtime_info missing expected fields: {text}")
            return False

    except json.JSONDecodeError:
        log("FAIL", f"get_runtime_info result is not valid JSON: {text}")
        return False
    except Exception as e:
        log("FAIL", f"get_runtime_info failed: {e}")
        return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Test MCP server tools deployed on Azure Container Apps."
    )
    parser.add_argument(
        "--endpoint", "-e",
        default=None,
        help="MCP server endpoint URL (e.g., https://mcp-server.<domain>). Auto-discovered if not provided.",
    )
    parser.add_argument(
        "--app-name", "-n",
        default="mcp-server",
        help="Container app name for auto-discovery (default: mcp-server)",
    )
    parser.add_argument(
        "--resource-group", "-g",
        default="rg-ai-aca",
        help="Resource group for auto-discovery (default: rg-ai-aca)",
    )
    parser.add_argument(
        "--timeout", "-t",
        type=int,
        default=30,
        help="HTTP timeout in seconds (default: 30)",
    )
    parser.add_argument(
        "--allow-public-dns",
        action="store_true",
        help="Allow endpoint DNS to resolve to non-private IP",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        # Discover or use provided endpoint
        if args.endpoint:
            endpoint = args.endpoint.rstrip("/")
        else:
            log("INFO", f"Auto-discovering endpoint for '{args.app_name}' in '{args.resource_group}'...")
            fqdn = discover_app_fqdn(args.app_name, args.resource_group)
            endpoint = f"https://{fqdn}"

        log("INFO", f"Endpoint: {endpoint}")

        # DNS resolution check
        host, ip_addr = resolve_host(endpoint, require_private_dns=not args.allow_public_dns)
        log("INFO", f"Host: {host}")
        log("INFO", f"Resolved IP: {ip_addr}")

        # MCP handshake
        log("INFO", "Initializing MCP session...")
        session_id, init_response = mcp_initialize(endpoint, args.timeout)
        log("INFO", f"Session ID: {session_id or '(none)'}")

        server_info = init_response.get("result", {}).get("serverInfo", {})
        log("INFO", f"Server: {server_info.get('name', 'unknown')} v{server_info.get('version', '?')}")

        # Send initialized notification
        mcp_initialized_notification(endpoint, session_id, args.timeout)
        log("INFO", "MCP handshake complete")

        # Run tool tests
        print("")
        results = []
        results.append(("get_current_time", test_get_current_time(endpoint, session_id, args.timeout)))
        results.append(("get_runtime_info", test_get_runtime_info(endpoint, session_id, args.timeout)))

        # Summary
        print("")
        passed = sum(1 for _, ok in results if ok)
        failed = sum(1 for _, ok in results if not ok)

        log("INFO", f"Results: {passed} passed, {failed} failed")

        if failed > 0:
            log("ERROR", "Some tests failed")
            return 6

        log("SUCCESS", "All MCP tool tests passed")
        return 0

    except socket.gaierror as error:
        log("ERROR", f"DNS resolution failed: {error}")
        log("ERROR", "Ensure VPN is connected and DNS is configured")
        return 4
    except (ConnectionError, urllib.error.URLError) as error:
        log("ERROR", f"Connection failed: {error}")
        log("ERROR", "Ensure VPN is connected and the MCP server is running")
        return 5
    except RuntimeError as error:
        log("ERROR", str(error))
        return 3
    except Exception as error:
        log("ERROR", f"Unexpected failure: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
