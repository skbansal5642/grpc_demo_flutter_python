"""
Old Implementation Server
Simulates the previous architecture:
  - Command / ack  → stdin (JSON lines in) / stdout (JSON lines out)
  - Streaming      → WebSocket on port 8765
"""

import sys
import json
import time
import threading
import asyncio
import websockets


# ── WebSocket server (replaces old WebSocket server) ──────────────────────────

async def _ws_handler(websocket):
    data = await websocket.recv()
    req = json.loads(data)
    count = max(1, min(req.get("chunks", 5), 20))
    session = req.get("session_id", "unknown")

    for i in range(count):
        time.sleep(0.03)  # simulate incremental work
        await websocket.send(json.dumps({
            "index": i,
            "data": f"Chunk {i + 1}/{count} — session '{session}'",
            "final": i == count - 1,
        }))


def _run_ws_server():
    async def _main():
        async with websockets.serve(_ws_handler, "localhost", 8765):
            await asyncio.Future()   # run until cancelled

    asyncio.run(_main())


# ── stdin/stdout command handler ───────────────────────────────────────────────

def _handle_commands():
    """
    Reads JSON-encoded commands from stdin, writes JSON acks to stdout.
    Mirrors the old flag-based protocol.
    """
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            cmd = json.loads(raw)
        except json.JSONDecodeError:
            continue

        command = cmd.get("command", "")
        payload = cmd.get("payload", "")
        time.sleep(0.01)  # simulate work

        if command == "process":
            ack = {"status": "ok", "result": payload.upper()}
        elif command == "error":
            ack = {"status": "error", "result": ""}
        else:
            ack = {"status": "ok", "result": ""}

        sys.stdout.write(json.dumps(ack) + "\n")
        sys.stdout.flush()


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Start WebSocket server in a background thread
    ws_thread = threading.Thread(target=_run_ws_server, daemon=True)
    ws_thread.start()

    # Signal ready (benchmark runner waits for this line)
    sys.stderr.write("[OldServer] ready\n")
    sys.stderr.flush()

    # Block on stdin commands
    _handle_commands()
