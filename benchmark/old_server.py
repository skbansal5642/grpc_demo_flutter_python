"""
Old Implementation Server — single asyncio event loop, no threads.
Simulates the previous architecture:
  - Command / ack  → stdin (JSON lines in) / stdout (JSON lines out)
  - Streaming      → WebSocket on port 8765

Previously used threading.Thread for the WebSocket server, which caused GIL
contention on slower hardware (CM4). Everything now runs in one event loop so
the WS handler and stdin reader cooperate via coroutines with no locking.
"""

import asyncio
import sys
import json
import websockets


# ── WebSocket handler ─────────────────────────────────────────────────────────

async def _ws_handler(websocket):
    data = await websocket.recv()
    req = json.loads(data)
    count = max(1, min(req.get("chunks", 5), 20))
    session = req.get("session_id", "unknown")

    for i in range(count):
        await asyncio.sleep(0.03)   # same latency as before, but non-blocking
        await websocket.send(json.dumps({
            "index": i,
            "data": f"Chunk {i + 1}/{count} — session '{session}'",
            "final": i == count - 1,
        }))
    await websocket.close()


# ── Async stdin reader ────────────────────────────────────────────────────────

async def _handle_stdin():
    """
    Reads JSON commands from stdin without blocking the event loop.
    Uses connect_read_pipe so asyncio can multiplex stdin with WebSocket I/O.
    """
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    async for raw in reader:
        line = raw.decode().strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            continue

        command = cmd.get("command", "")
        payload = cmd.get("payload", "")
        await asyncio.sleep(0.01)   # simulate work

        if command == "process":
            ack = {"status": "ok", "result": payload.upper()}
        elif command == "error":
            ack = {"status": "error", "result": ""}
        else:
            ack = {"status": "ok", "result": ""}

        sys.stdout.write(json.dumps(ack) + "\n")
        sys.stdout.flush()


# ── Entry point ───────────────────────────────────────────────────────────────

async def main():
    # Bind to 0.0.0.0 so both IPv4 (127.0.0.1) and IPv6 (::1) clients
    # connect regardless of how the OS resolves "localhost".
    async with websockets.serve(_ws_handler, "0.0.0.0", 8765):
        sys.stderr.write("[OldServer] ready\n")
        sys.stderr.flush()
        await _handle_stdin()


if __name__ == "__main__":
    asyncio.run(main())
