import 'dart:async';
import 'dart:io';
import 'package:grpc/grpc.dart';
import 'generated/demo.pbgrpc.dart';

/// Manages the full lifecycle: spawns the Python process, waits for it to be
/// ready, opens the gRPC channel, and tears everything down on disconnect.
///
/// This mirrors the old package pattern:
///   connect()  → start .sh process  +  open WebSocket
///   dispose()  → kill process       +  close WebSocket
///
/// Now it's:
///   connect()  → start Python via Process  +  open gRPC channel (one thing)
///   dispose()  → close gRPC channel        +  SIGTERM the process
class DemoClient {
  ClientChannel? _channel;
  DemoServiceClient? _stub;
  Process? _serverProcess;

  // Broadcasts stdout/stderr from the Python process so the UI can show it.
  final _serverLogs = StreamController<String>.broadcast();
  Stream<String> get serverLogs => _serverLogs.stream;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Starts the Python gRPC server, waits until it responds to Ping, then
  /// opens the gRPC channel. Throws [TimeoutException] if the server doesn't
  /// come up within [maxReadyAttempts] × [retryDelay].
  ///
  /// [serverDirectory] is the path to the `python_server/` folder.
  /// The venv python and server.py are resolved from it automatically.
  Future<void> connect({
    required String serverDirectory,
    String host = 'localhost',
    int port = 50051,
    int maxReadyAttempts = 20,
    Duration retryDelay = const Duration(milliseconds: 400),
  }) async {
    await _startServer(serverDirectory);

    _channel = ClientChannel(
      host,
      port: port,
      options: ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        // Keep the connection alive to avoid reconnect overhead on every call.
        idleTimeout: const Duration(minutes: 5),
        connectionTimeout: const Duration(seconds: 5),
      ),
    );
    _stub = DemoServiceClient(_channel!);

    await _waitForReady(maxReadyAttempts, retryDelay);
  }

  /// Closes the gRPC channel and terminates the Python process.
  Future<void> disconnect() async {
    await _channel?.shutdown();
    _channel = null;
    _stub = null;

    _serverProcess?.kill(ProcessSignal.sigterm);
    await _serverProcess?.exitCode;
    _serverProcess = null;
  }

  /// Call once when the owning widget is disposed.
  void dispose() {
    _serverLogs.close();
    disconnect();
  }

  bool get isConnected => _channel != null;

  // ── Operations ─────────────────────────────────────────────────────────────

  Future<PingResult> ping() async {
    _assertConnected();
    final res = await _stub!.ping(Empty());
    return PingResult(version: res.serverVersion, message: res.message);
  }

  /// Replaces: writing a flag to stdin and waiting for the ack line on stdout.
  Future<CommandResult> executeCommand(String command, {String payload = ''}) async {
    _assertConnected();
    final res = await _stub!.executeCommand(
      CommandRequest(command: command, payload: payload),
    );
    return CommandResult(success: res.success, message: res.message, result: res.result);
  }

  /// Replaces: opening a WebSocket session and reading frames until server closes.
  Stream<StreamChunk> streamOutput(String sessionId, {int chunkCount = 5}) {
    _assertConnected();
    return _stub!
        .streamOutput(StreamRequest(sessionId: sessionId, chunkCount: chunkCount))
        .map((c) => StreamChunk(index: c.index, data: c.data, isFinal: c.isFinal));
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<void> _startServer(String serverDirectory) async {
    // Call the venv python directly — avoids bash execution restrictions on macOS.
    final python = '$serverDirectory/venv/bin/python';
    final script = '$serverDirectory/server.py';
    _serverProcess = await Process.start(python, [script],
        workingDirectory: serverDirectory);

    final dec = const SystemEncoding().decoder;
    _serverProcess!.stdout.transform(dec).listen(_serverLogs.add);
    _serverProcess!.stderr.transform(dec).listen(_serverLogs.add);
  }

  Future<void> _waitForReady(int maxAttempts, Duration delay) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await _stub!.ping(Empty());
        return; // server is up
      } catch (_) {
        await Future.delayed(delay);
      }
    }
    // Timed out — clean up before throwing
    await disconnect();
    throw TimeoutException(
      'Python gRPC server did not become ready after '
      '${maxAttempts * delay.inMilliseconds}ms. '
      'Check that python3 is in PATH and the script path is correct.',
    );
  }

  void _assertConnected() {
    if (_stub == null) throw StateError('Not connected. Call connect() first.');
  }
}

// ── Value objects ──────────────────────────────────────────────────────────

class PingResult {
  final String version;
  final String message;
  PingResult({required this.version, required this.message});
}

class CommandResult {
  final bool success;
  final String message;
  final String result;
  CommandResult({required this.success, required this.message, required this.result});
}

class StreamChunk {
  final int index;
  final String data;
  final bool isFinal;
  StreamChunk({required this.index, required this.data, required this.isFinal});
}
