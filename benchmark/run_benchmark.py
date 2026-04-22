"""
NFR Benchmark — Old (stdio + WebSocket) vs New (gRPC)

Metrics collected per implementation:
  Latency    p50 / p95 / p99  (milliseconds)
  Throughput requests per second
  Memory     RSS of the server process (MB)
  CPU        CPU % of the server process during the run
"""

import asyncio
import json
import os
import statistics
import subprocess
import sys
import time

import psutil
import grpc
import websockets

# ── paths ──────────────────────────────────────────────────────────────────────
ROOT        = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PYTHON      = os.path.join(ROOT, "python_server", "venv", "bin", "python")
OLD_SERVER  = os.path.join(ROOT, "benchmark", "old_server.py")
GRPC_SERVER = os.path.join(ROOT, "python_server", "server.py")

# Add python_server to path so we can import generated stubs
sys.path.insert(0, os.path.join(ROOT, "python_server"))
from generated import demo_pb2, demo_pb2_grpc   # noqa: E402

# ── benchmark config ───────────────────────────────────────────────────────────
N_COMMAND   = 200   # unary command iterations
N_STREAM    = 50    # streaming iterations
CHUNKS      = 5     # chunks per stream call
WARMUP      = 10    # warm-up iterations (excluded from results)


# ── helpers ────────────────────────────────────────────────────────────────────

def percentile(data: list[float], p: int) -> float:
    data = sorted(data)
    k = (len(data) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(data) - 1)
    return data[lo] + (data[hi] - data[lo]) * (k - lo)


def sample_resource(proc: psutil.Process) -> tuple[float, float]:
    """Returns (cpu_pct, rss_mb) sampled over ~0.5 s."""
    proc.cpu_percent()          # first call primes the counter
    time.sleep(0.5)
    cpu = proc.cpu_percent()
    mem = proc.memory_info().rss / 1024 / 1024
    return cpu, mem


def print_table(old: dict, new: dict):
    W = 20
    print()
    print("=" * 68)
    print(f"{'METRIC':<28}{'Old (stdio + WebSocket)':>{W}}{'New (gRPC)':>{W}}")
    print("=" * 68)

    def row(label, old_val, new_val, unit="", better="lower"):
        try:
            if better == "lower":
                winner = "✓" if float(new_val) < float(old_val) else " "
            else:
                winner = "✓" if float(new_val) > float(old_val) else " "
        except Exception:
            winner = " "
        print(f"  {label:<26}{str(old_val) + unit:>{W}}{winner + str(new_val) + unit:>{W}}")

    print()
    print("  Command / Ack (unary)")
    row("  Latency p50 (ms)",  old["cmd_p50"],  new["cmd_p50"],  " ms")
    row("  Latency p95 (ms)",  old["cmd_p95"],  new["cmd_p95"],  " ms")
    row("  Latency p99 (ms)",  old["cmd_p99"],  new["cmd_p99"],  " ms")
    row("  Throughput (req/s)", old["cmd_rps"], new["cmd_rps"],  " rps", better="higher")
    print()
    print("  Streaming")
    row("  Latency p50 (ms)",  old["str_p50"],  new["str_p50"],  " ms")
    row("  Latency p95 (ms)",  old["str_p95"],  new["str_p95"],  " ms")
    row("  Latency p99 (ms)",  old["str_p99"],  new["str_p99"],  " ms")
    row("  Throughput (req/s)", old["str_rps"], new["str_rps"],  " rps", better="higher")
    print()
    print("  Server Resources")
    row("  CPU %",             old["cpu"],      new["cpu"],      "%")
    row("  Memory (MB)",       old["mem"],      new["mem"],      " MB")
    print()
    print("  ✓ = gRPC is better")
    print("=" * 68)
    print()


# ── Old implementation benchmark ───────────────────────────────────────────────

def _old_command(proc: subprocess.Popen) -> float:
    cmd = json.dumps({"command": "process", "payload": "hello world"}) + "\n"
    t0 = time.perf_counter()
    proc.stdin.write(cmd.encode())
    proc.stdin.flush()
    proc.stdout.readline()
    return (time.perf_counter() - t0) * 1000


async def _old_stream(chunks: int) -> float:
    t0 = time.perf_counter()
    async with websockets.connect("ws://localhost:8765") as ws:
        await ws.send(json.dumps({"session_id": "bench", "chunks": chunks}))
        while True:
            msg = json.loads(await ws.recv())
            if msg["final"]:
                break
    return (time.perf_counter() - t0) * 1000


async def run_old_benchmark() -> dict:
    print("\n── Starting OLD server (stdio + WebSocket) ──")
    proc = subprocess.Popen(
        [PYTHON, OLD_SERVER],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Wait for ready signal on stderr
    for _ in range(30):
        line = proc.stderr.readline().decode()
        if "ready" in line:
            break
        time.sleep(0.1)
    else:
        proc.kill()
        raise RuntimeError("Old server did not start in time")

    ps = psutil.Process(proc.pid)
    time.sleep(0.3)

    # Warm up
    for _ in range(WARMUP):
        _old_command(proc)

    # ── Command latency ──
    print(f"  Running {N_COMMAND} command iterations...")
    cmd_latencies = []
    t_start = time.perf_counter()
    for _ in range(N_COMMAND):
        cmd_latencies.append(_old_command(proc))
    cmd_elapsed = time.perf_counter() - t_start

    # ── Streaming latency ──
    print(f"  Running {N_STREAM} stream iterations...")
    str_latencies = []
    t_start = time.perf_counter()
    for _ in range(N_STREAM):
        str_latencies.append(await _old_stream(CHUNKS))
    str_elapsed = time.perf_counter() - t_start

    cpu, mem = sample_resource(ps)
    proc.terminate()
    proc.wait()

    return {
        "cmd_p50": round(percentile(cmd_latencies, 50), 2),
        "cmd_p95": round(percentile(cmd_latencies, 95), 2),
        "cmd_p99": round(percentile(cmd_latencies, 99), 2),
        "cmd_rps": round(N_COMMAND / cmd_elapsed, 1),
        "str_p50": round(percentile(str_latencies, 50), 2),
        "str_p95": round(percentile(str_latencies, 95), 2),
        "str_p99": round(percentile(str_latencies, 99), 2),
        "str_rps": round(N_STREAM / str_elapsed, 1),
        "cpu":     round(cpu, 1),
        "mem":     round(mem, 1),
    }


# ── gRPC benchmark ─────────────────────────────────────────────────────────────

def _grpc_command(stub) -> float:
    t0 = time.perf_counter()
    stub.ExecuteCommand(
        demo_pb2.CommandRequest(command="process", payload="hello world")
    )
    return (time.perf_counter() - t0) * 1000


def _grpc_stream(stub, chunks: int) -> float:
    t0 = time.perf_counter()
    for _ in stub.StreamOutput(
        demo_pb2.StreamRequest(session_id="bench", chunk_count=chunks)
    ):
        pass
    return (time.perf_counter() - t0) * 1000


async def run_grpc_benchmark() -> dict:
    print("\n── Starting NEW server (gRPC) ──")
    proc = subprocess.Popen(
        [PYTHON, GRPC_SERVER],
        stderr=subprocess.PIPE,
    )

    # Wait for server to accept connections
    for _ in range(30):
        line = proc.stderr.readline().decode()
        if "listening" in line.lower() or "started" in line.lower():
            break
        time.sleep(0.1)
    time.sleep(0.3)  # let the server fully initialise

    ps = psutil.Process(proc.pid)

    channel = grpc.insecure_channel("localhost:50051")
    stub = demo_pb2_grpc.DemoServiceStub(channel)

    # Warm up
    for _ in range(WARMUP):
        stub.Ping(demo_pb2.Empty())
        stub.ExecuteCommand(demo_pb2.CommandRequest(command="process", payload="warmup"))

    # ── Command latency ──
    print(f"  Running {N_COMMAND} command iterations...")
    cmd_latencies = []
    t_start = time.perf_counter()
    for _ in range(N_COMMAND):
        cmd_latencies.append(_grpc_command(stub))
    cmd_elapsed = time.perf_counter() - t_start

    # ── Streaming latency ──
    print(f"  Running {N_STREAM} stream iterations...")
    str_latencies = []
    t_start = time.perf_counter()
    for _ in range(N_STREAM):
        str_latencies.append(_grpc_stream(stub, CHUNKS))
    str_elapsed = time.perf_counter() - t_start

    cpu, mem = sample_resource(ps)
    channel.close()
    proc.terminate()
    proc.wait()

    return {
        "cmd_p50": round(percentile(cmd_latencies, 50), 2),
        "cmd_p95": round(percentile(cmd_latencies, 95), 2),
        "cmd_p99": round(percentile(cmd_latencies, 99), 2),
        "cmd_rps": round(N_COMMAND / cmd_elapsed, 1),
        "str_p50": round(percentile(str_latencies, 50), 2),
        "str_p95": round(percentile(str_latencies, 95), 2),
        "str_p99": round(percentile(str_latencies, 99), 2),
        "str_rps": round(N_STREAM / str_elapsed, 1),
        "cpu":     round(cpu, 1),
        "mem":     round(mem, 1),
    }


# ── Main ───────────────────────────────────────────────────────────────────────

async def main():
    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║              gRPC vs Old Implementation — NFR Benchmark         ║")
    print("╚══════════════════════════════════════════════════════════════════╝")
    print(f"\n  Config: {N_COMMAND} command calls · {N_STREAM} stream calls · {CHUNKS} chunks/stream")

    old_results  = await run_old_benchmark()
    grpc_results = await run_grpc_benchmark()

    print_table(old_results, grpc_results)


if __name__ == "__main__":
    asyncio.run(main())
