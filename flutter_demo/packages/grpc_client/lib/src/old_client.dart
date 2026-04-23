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
    // Flush immediately — without this the IOSink buffer may not be sent
    // to the Python process until it fills, causing readline() to block
    // indefinitely on slower hardware like CM4.
    await _process!.stdin.flush();
    return completer.future;
  }

  /// Open a WebSocket, send a stream request, yield chunks until final.
  Stream<Map<String, dynamic>> streamOutput(
    String sessionId, {
    int chunkCount = 5,
  }) async* {
    // Use 127.0.0.1 explicitly — avoids the ambiguity where "localhost"
    // resolves to ::1 (IPv6) on the server but 127.0.0.1 (IPv4) on the
    // client (common on Raspberry Pi / Debian), causing the server to
    // never receive the request message.
    final channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8765'));

    // Wait for the TCP + WebSocket handshake to complete before sending.
    // Without this, sink.add() fires before the connection is ready and
    // the message is silently dropped.
    await channel.ready;

    channel.sink.add(
      jsonEncode({'session_id': sessionId, 'chunks': chunkCount}),
    );

    // Timeout per chunk × 3 + 3s headroom.
    // Each chunk has a 30ms sleep, so 5 chunks = 150ms; 3s is generous.
    final timeout = Duration(milliseconds: chunkCount * 3 * 30 + 3000);
    await for (final raw in channel.stream.timeout(timeout)) {
      final chunk = jsonDecode(raw as String) as Map<String, dynamic>;
      yield chunk;
      if (chunk['final'] == true) break;
    }
    await channel.sink.close().catchError((_) {});
  }
}
