"""
gRPC server for NFR benchmarking only.
Uses grpc.aio (asyncio) to eliminate thread-dispatch overhead that
ThreadPoolExecutor adds (~2.58 ms per call). asyncio handles requests
on a single event loop without the latency cost of handing work to a
thread pool — same model as the stdio server's single-threaded readline loop.
"""

import asyncio
import grpc
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python_server'))
from generated import demo_pb2, demo_pb2_grpc


class BenchServicer(demo_pb2_grpc.DemoServiceServicer):

    async def Ping(self, request, context):
        return demo_pb2.PingResponse(server_version="bench-1.0", message="pong")

    async def ExecuteCommand(self, request, context):
        await asyncio.sleep(0.01)   # same as old_server.py
        return demo_pb2.CommandResponse(
            success=True,
            message="ok",
            result=request.payload.upper(),
        )

    async def StreamOutput(self, request, context):
        count = max(1, min(request.chunk_count, 20))
        for i in range(count):
            await asyncio.sleep(0.03)   # same as old_server.py
            yield demo_pb2.OutputChunk(
                index=i,
                data=f"chunk_{i}",
                is_final=(i == count - 1),
            )


async def serve():
    server = grpc.aio.server()
    demo_pb2_grpc.add_DemoServiceServicer_to_server(BenchServicer(), server)
    server.add_insecure_port("[::]:50052")
    await server.start()
    sys.stderr.write("[BenchServer] listening on 50052\n")
    sys.stderr.flush()
    await server.wait_for_termination()


if __name__ == "__main__":
    asyncio.run(serve())
