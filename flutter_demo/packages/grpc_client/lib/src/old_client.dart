import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Client that mimics the OLD communication architecture:
///   Commands  → JSON lines over Process stdin / stdout
///   Streaming → WebSocket on ws://localhost:8765
class OldClient {
  Process? _process;
  StreamSubscription<String>? _stdoutSub;

  // Each pending command registers a Completer here.
  // stdout lines resolve them in order (FIFO).
  final _pending = Queue<Completer<Map<String, dynamic>>>();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Spawns old_server.py via the venv python and waits for the ready signal.
  Future<void> connect({required String serverDirectory}) async {
    final python = '$serverDirectory/venv/bin/python';
    final script = '$serverDirectory/../benchmark/old_server.py';

    _process = await Process.start(
      python,
      [script],
      workingDirectory: serverDirectory,
    );

    // Wait for "[OldServer] ready" on stderr
    final ready = Completer<void>();
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (!ready.isCompleted && line.contains('ready')) {
        ready.complete();
      }
    });
    await ready.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Old server did not start'),
    );

    // Wire stdout → pending completers
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_pending.isNotEmpty) {
        final c = _pending.removeFirst();
        try {
          c.complete(jsonDecode(line) as Map<String, dynamic>);
        } catch (e) {
          c.completeError(e);
        }
      }
    });
  }

  /// PID of the spawned Python process — used by [CpuSampler].
  int get pid => _process!.pid;

  Future<void> disconnect() async {
    await _stdoutSub?.cancel();
    _process?.kill(ProcessSignal.sigterm);
    await _process?.exitCode;
    _process = null;
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  /// Send a JSON command over stdin, await JSON ack from stdout.
  /// Measures the full round-trip from this Dart call to receiving the ack.
  Future<Map<String, dynamic>> executeCommand(
    String command, {
    String payload = '',
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    _pending.add(completer);
    _process!.stdin.writeln(jsonEncode({'command': command, 'payload': payload}));
    return completer.future;
  }

  /// Open a WebSocket, send a stream request, yield chunks until final.
  Stream<Map<String, dynamic>> streamOutput(
    String sessionId, {
    int chunkCount = 5,
  }) async* {
    final channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8765'));
    channel.sink.add(
      jsonEncode({'session_id': sessionId, 'chunks': chunkCount}),
    );
    // Timeout = (chunks × 100ms) + 2s headroom — prevents an unclean
    // WebSocket close from freezing the benchmark loop indefinitely.
    final timeout = Duration(milliseconds: chunkCount * 100 + 2000);
    await for (final raw in channel.stream.timeout(timeout)) {
      final chunk = jsonDecode(raw as String) as Map<String, dynamic>;
      yield chunk;
      if (chunk['final'] == true) break;
    }
    await channel.sink.close().catchError((_) {});
  }
}
