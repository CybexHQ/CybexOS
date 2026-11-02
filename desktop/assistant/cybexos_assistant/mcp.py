"""`cybexos-assistant mcp`: the Cybex OS desktop tools as an MCP server.

Claude Code and Codex start this over stdio for the assistant's own agent
processes (claude.py, codex.py). It lists the tools in desktop.py and passes
every call to the assistant service as `desktop.call`, naming the lane its
agent belongs to (CYBEXOS_ASSISTANT_LANE). The service decides what may run,
asks the person when it should, records what changed, and carries the call
out itself or through the shell. Nothing is decided here.

Newline-delimited JSON-RPC 2.0, as MCP's stdio transport specifies.
"""

from __future__ import annotations

import asyncio
import os
import sys

from . import desktop
from .protocol import MAX_LINE, default_socket, encode, iter_lines, parse_json


PROTOCOL_VERSIONS = ("2025-06-18", "2025-03-26", "2024-11-05")
# Long enough for an app to install; the agents are told the same.
CALL_TIMEOUT = 900.0


async def call_service(socket_path, tool, arguments, lane):
    reader, writer = await asyncio.open_unix_connection(str(socket_path))
    try:
        writer.write(encode({"jsonrpc": "2.0", "id": 1, "method": "desktop.call",
                             "params": {"tool": tool, "arguments": arguments, "lane": lane}}))
        await writer.drain()
        async for line in iter_lines(reader, MAX_LINE):
            message = parse_json(line)
            if message is None or message.get("id") != 1:
                continue
            if "error" in message:
                return {"isError": True, "text": str((message["error"] or {}).get("message") or "The call failed.")}
            result = message.get("result") or {}
            return {"isError": bool(result.get("isError")), "text": str(result.get("text") or "")}
        return {"isError": True, "text": "The assistant service closed the connection."}
    finally:
        writer.close()


async def handle(message, socket_path, lane):
    """The answer to one request, or None for a notification."""
    method = message.get("method")
    identifier = message.get("id")
    params = message.get("params") if isinstance(message.get("params"), dict) else {}
    if identifier is None:
        return None
    if method == "initialize":
        requested = params.get("protocolVersion")
        version = requested if requested in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0]
        result = {"protocolVersion": version, "capabilities": {"tools": {"listChanged": False}},
                  "serverInfo": {"name": desktop.SERVER, "title": "Cybex OS desktop", "version": "1"},
                  "instructions": "Cybex OS's own desktop tools. Every change they make can be undone."}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": desktop.listing()}
    elif method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") if isinstance(params.get("arguments"), dict) else {}
        if desktop.tool_name(name) == "":
            outcome = {"isError": True, "text": f"Unknown tool {name}."}
        else:
            try:
                outcome = await asyncio.wait_for(call_service(socket_path, name, arguments, lane), CALL_TIMEOUT)
            except (OSError, ConnectionError):
                outcome = {"isError": True, "text": "The Cybex OS Assistant service is not running."}
            except asyncio.TimeoutError:
                outcome = {"isError": True, "text": "The desktop did not answer in time."}
        result = {"content": [{"type": "text", "text": outcome["text"]}], "isError": outcome["isError"]}
    else:
        return {"jsonrpc": "2.0", "id": identifier, "error": {"code": -32601, "message": f"Unknown method {method}"}}
    return {"jsonrpc": "2.0", "id": identifier, "result": result}


async def serve(stdin=None, stdout=None, socket_path=None, lane=None):
    loop = asyncio.get_running_loop()
    if stdin is None:
        stdin = asyncio.StreamReader(limit=MAX_LINE)
        await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(stdin), sys.stdin)
    write = stdout or (lambda data: (sys.stdout.buffer.write(data), sys.stdout.buffer.flush()))
    socket_path = socket_path or os.environ.get("CYBEXOS_ASSISTANT_SOCKET") or default_socket()
    lane = lane or os.environ.get("CYBEXOS_ASSISTANT_LANE") or "main"
    tasks = set()

    async def answer(message):
        reply = await handle(message, socket_path, lane)
        if reply is not None:
            write(encode(reply))

    async for line in iter_lines(stdin, MAX_LINE):
        message = parse_json(line)
        if message is None:
            write(encode({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}))
            continue
        task = asyncio.create_task(answer(message))
        tasks.add(task)
        task.add_done_callback(tasks.discard)
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)


def command(socket_path, lane):
    """How an agent starts this server: (argv, env)."""
    package = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    env = {"CYBEXOS_ASSISTANT_SOCKET": str(socket_path), "CYBEXOS_ASSISTANT_LANE": lane, "PYTHONPATH": package}
    return [sys.executable, "-m", "cybexos_assistant", "mcp"], env


def main():
    try:
        asyncio.run(serve())
    except KeyboardInterrupt:
        pass
    return 0

