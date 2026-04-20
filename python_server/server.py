"""
gRPC Demo Server
Replaces: .sh script that ran python and communicated via stdio flags + WebSocket server
Now: a single gRPC server that handles both command/ack and streaming patterns.
"""

import grpc
import time
from concurrent import futures
from generated import demo_pb2, demo_pb2_grpc


class DemoServiceServicer(demo_pb2_grpc.DemoServiceServicer):

    def Ping(self, request, context):
        print("[Server] Ping received")
        return demo_pb2.PingResponse(
            server_version="1.0.0",
            message="pong from Python gRPC server",
        )

    def ExecuteCommand(self, request, context):
        """
        Replaces: reading a flag from stdin, processing, writing ack to stdout.
        Now: typed request in, typed response out.
        """
        print(f"[Server] ExecuteCommand: command={request.command!r}  payload={request.payload!r}")
        time.sleep(0.4)  # simulate work

        if request.command == "process":
            return demo_pb2.CommandResponse(
                success=True,
                message="Command processed successfully",
                result=f"Processed → {request.payload.upper()}",
            )
        elif request.command == "error":
            return demo_pb2.CommandResponse(
                success=False,
                message="Command failed intentionally (demo error path)",
                result="",
            )
        else:
            return demo_pb2.CommandResponse(
                success=True,
                message=f"Unknown command '{request.command}' acknowledged",
                result="",
            )

    def StreamOutput(self, request, context):
        """
        Replaces: WebSocket server streaming frames to the client.
        Now: gRPC server-streaming — same semantics, typed and schema-enforced.
        """
        count = max(1, min(request.chunk_count, 20))
        print(f"[Server] StreamOutput: session={request.session_id!r}  chunks={count}")

        for i in range(count):
            time.sleep(0.3)  # simulate incremental work (file processing, ML inference, etc.)
            is_final = i == count - 1
            yield demo_pb2.OutputChunk(
                index=i,
                data=f"Chunk {i + 1}/{count} — processing session '{request.session_id}'...",
                is_final=is_final,
            )


def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    demo_pb2_grpc.add_DemoServiceServicer_to_server(DemoServiceServicer(), server)
    address = "[::]:50051"
    server.add_insecure_port(address)
    server.start()
    print(f"[Server] gRPC server listening on {address}")
    print("[Server] Waiting for connections — press Ctrl+C to stop\n")
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        print("\n[Server] Shutting down...")
        server.stop(grace=2)


if __name__ == "__main__":
    serve()
