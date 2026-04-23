import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:grpc_client/src/generated/demo.pbgrpc.dart';

/// Standalone gRPC client for the benchmark.
/// Intentionally separate from DemoClient in grpc_client — owns its own
/// channel lifecycle so the benchmark controls exactly what it measures.
class GrpcBenchClient {
  ClientChannel? _channel;
  DemoServiceClient? _stub;
  Process? _serverProcess;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> connect({
    required String serverDirectory,
    String host = 'localhost',
    int port =
        50052, // dedicated bench port — avoids conflict with demo server on 50051
    int maxAttempts = 20,
    Duration retryDelay = const Duration(milliseconds: 400),
  }) async {
    final python = '$serverDirectory/venv/bin/python';
    // Use the dedicated bench server (same sleep times as old_server.py)
    // so both sides measure protocol overhead, not business logic simulation.
    final script = '$serverDirectory/../benchmark/grpc_bench_server.py';

    _serverProcess = await Process.start(
      python,
      [script],
      workingDirectory: serverDirectory,
    );

    _channel = ClientChannel(
      host,
      port: port,
      options: ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        // Keep the connection alive so each call doesn't pay
        // reconnection overhead during the benchmark loop.
        idleTimeout: const Duration(minutes: 5),
        connectionTimeout: const Duration(seconds: 5),
      ),
    );
    _stub = DemoServiceClient(_channel!);

    // Poll ping until server is ready
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await _stub!.ping(Empty());
        return;
      } catch (_) {
        await Future.delayed(retryDelay);
      }
    }
    await disconnect();
    throw TimeoutException('gRPC server did not become ready');
  }

  /// PID of the spawned Python process — used by [CpuSampler].
  int get pid => _serverProcess!.pid;

  Future<void> disconnect() async {
    await _channel?.shutdown();
    _channel = null;
    _stub = null;
    _serverProcess?.kill(ProcessSignal.sigterm);
    await _serverProcess?.exitCode;
    _serverProcess = null;
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  Future<CommandResponse> executeCommand(
    String command, {
    String payload = '',
  }) async {
    return _stub!.executeCommand(
      CommandRequest(command: command, payload: payload),
    );
  }

  Stream<OutputChunk> streamOutput(String sessionId, {int chunkCount = 5}) {
    return _stub!.streamOutput(
      StreamRequest(sessionId: sessionId, chunkCount: chunkCount),
    );
  }
}
