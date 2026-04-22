import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grpc_client/grpc_client.dart';
import 'package:grpc_demo_app/benchmark_page.dart';

// Path to the Python server script. In a real app this would be a bundled asset path.
const _defaultServerPath =
    '/Users/spurge/Documents/claude_workspace/grpc_demo/python_server';

void main() => runApp(const GrpcDemoApp());

class GrpcDemoApp extends StatelessWidget {
  const GrpcDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gRPC Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _RootTabs(),
    );
  }
}

// ── Connection state machine ───────────────────────────────────────────────

enum ConnState { idle, starting, connected, disconnecting }

extension on ConnState {
  bool get isBusy =>
      this == ConnState.starting || this == ConnState.disconnecting;
  String get label => switch (this) {
        ConnState.idle => 'Not connected',
        ConnState.starting => 'Starting Python server…',
        ConnState.connected => 'Connected  ·  localhost:50051',
        ConnState.disconnecting => 'Disconnecting…',
      };
  Color get color => switch (this) {
        ConnState.idle => Colors.red.shade50,
        ConnState.starting => Colors.orange.shade50,
        ConnState.connected => Colors.green.shade100,
        ConnState.disconnecting => Colors.orange.shade50,
      };
  Color get iconColor => switch (this) {
        ConnState.idle => Colors.red.shade400,
        ConnState.starting => Colors.orange.shade700,
        ConnState.connected => Colors.green.shade700,
        ConnState.disconnecting => Colors.orange.shade700,
      };
  IconData get icon => switch (this) {
        ConnState.idle => Icons.wifi_off,
        ConnState.starting => Icons.hourglass_top,
        ConnState.connected => Icons.wifi,
        ConnState.disconnecting => Icons.hourglass_bottom,
      };
}

// ── Page ───────────────────────────────────────────────────────────────────

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _client = DemoClient();
  final _logs = <_LogEntry>[];
  final _pathController = TextEditingController(text: _defaultServerPath);
  var _connState = ConnState.idle;
  StreamSubscription<String>? _serverLogSub;

  @override
  void initState() {
    super.initState();
    // Pipe Python process stdout/stderr into the log view
    _serverLogSub = _client.serverLogs.listen(
      (line) => _log('[python] ${line.trim()}', level: LogLevel.server),
    );
  }

  @override
  void dispose() {
    _serverLogSub?.cancel();
    _pathController.dispose();
    _client.dispose();
    super.dispose();
  }

  void _log(String text, {LogLevel level = LogLevel.info}) {
    final now = DateTime.now();
    setState(() {
      _logs.insert(
        0,
        _LogEntry(
          time: '${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')}:'
              '${now.second.toString().padLeft(2, '0')}',
          text: text,
          level: level,
        ),
      );
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> _toggleConnect() async {
    if (_connState == ConnState.connected) {
      setState(() => _connState = ConnState.disconnecting);
      _log('Stopping Python server and closing channel…');
      try {
        await _client.disconnect();
        _log('Disconnected', level: LogLevel.success);
      } catch (e) {
        _log('Disconnect error: $e', level: LogLevel.error);
      } finally {
        setState(() => _connState = ConnState.idle);
      }
    } else {
      setState(() => _connState = ConnState.starting);
      _log('Launching Python gRPC server at:\n  ${_pathController.text}');
      try {
        await _client.connect(serverDirectory: _pathController.text);
        _log('Server ready — gRPC channel open', level: LogLevel.success);
        setState(() => _connState = ConnState.connected);
      } on TimeoutException catch (e) {
        _log('Timeout: $e', level: LogLevel.error);
        setState(() => _connState = ConnState.idle);
      } catch (e) {
        _log('Start error: $e', level: LogLevel.error);
        setState(() => _connState = ConnState.idle);
      }
    }
  }

  // ── gRPC calls ─────────────────────────────────────────────────────────────

  Future<void> _ping() async {
    try {
      final r = await _client.ping();
      _log('Ping → v${r.version}: ${r.message}', level: LogLevel.success);
    } catch (e) {
      _log('Ping error: $e', level: LogLevel.error);
    }
  }

  Future<void> _executeCommand() async {
    _log('→ ExecuteCommand(process, "hello world")');
    try {
      final r = await _client.executeCommand('process', payload: 'hello world');
      _log('${r.success ? "✓" : "✗"} ${r.message}  |  ${r.result}',
          level: r.success ? LogLevel.success : LogLevel.error);
    } catch (e) {
      _log('Command error: $e', level: LogLevel.error);
    }
  }

  Future<void> _executeErrorCommand() async {
    _log('→ ExecuteCommand(error)');
    try {
      final r = await _client.executeCommand('error');
      _log('✗ ${r.message}', level: LogLevel.error);
    } catch (e) {
      _log('Command error: $e', level: LogLevel.error);
    }
  }

  Future<void> _streamOutput() async {
    final sessionId = 'sess-${DateTime.now().millisecondsSinceEpoch}';
    _log('→ StreamOutput(session=$sessionId, chunks=5)');
    try {
      await for (final chunk
          in _client.streamOutput(sessionId, chunkCount: 5)) {
        _log(
          '[${chunk.index}] ${chunk.data}${chunk.isFinal ? "  ← FINAL" : ""}',
          level: chunk.isFinal ? LogLevel.success : LogLevel.info,
        );
      }
      _log('Stream complete', level: LogLevel.success);
    } catch (e) {
      _log('Stream error: $e', level: LogLevel.error);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isConnected = _connState == ConnState.connected;
    final isBusy = _connState.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('gRPC Demo'),
        centerTitle: true,
        backgroundColor: cs.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: _connState.color,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                isBusy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _connState.iconColor,
                        ),
                      )
                    : Icon(_connState.icon,
                        color: _connState.iconColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  _connState.label,
                  style: TextStyle(
                    color: _connState.iconColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Server path field (shown only when idle)
          if (_connState == ConnState.idle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _pathController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Python server directory (python_server/)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isBusy ? null : _toggleConnect,
                  icon:
                      Icon(isConnected ? Icons.stop_circle : Icons.play_circle),
                  label: Text(
                    switch (_connState) {
                      ConnState.idle => 'Start & Connect',
                      ConnState.starting => 'Starting…',
                      ConnState.connected => 'Stop & Disconnect',
                      ConnState.disconnecting => 'Stopping…',
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: (isConnected) ? _ping : null,
                  icon: const Icon(Icons.wifi_tethering, size: 16),
                  label: const Text('Ping'),
                ),
                OutlinedButton.icon(
                  onPressed: (isConnected) ? _executeCommand : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Execute Command'),
                ),
                OutlinedButton.icon(
                  onPressed: (isConnected) ? _executeErrorCommand : null,
                  icon: const Icon(Icons.error_outline, size: 16),
                  label: const Text('Trigger Error'),
                ),
                FilledButton.tonalIcon(
                  onPressed: (isConnected) ? _streamOutput : null,
                  icon: const Icon(Icons.stream, size: 16),
                  label: const Text('Stream Output'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Log view
          Expanded(child: _LogView(logs: _logs)),
        ],
      ),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────

class _LogView extends StatelessWidget {
  const _LogView({required this.logs});
  final List<_LogEntry> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text('Press "Start & Connect" to launch the server',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return Container(
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: logs.length,
        itemBuilder: (_, i) {
          final e = logs[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              '${e.time}  ${e.text}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: e.level.color,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Data ───────────────────────────────────────────────────────────────────

enum LogLevel {
  info(Color(0xFFAAAAAA)),
  success(Color(0xFF89D185)),
  error(Color(0xFFF48771)),
  server(Color(0xFF569CD6)); // blue — Python process output

  const LogLevel(this.color);
  final Color color;
}

class _LogEntry {
  final String time;
  final String text;
  final LogLevel level;
  const _LogEntry(
      {required this.time, required this.text, required this.level});
}

// ══════════════════════════════════════════════════════════════════════════════
// Root tab scaffold
// ══════════════════════════════════════════════════════════════════════════════

class _RootTabs extends StatefulWidget {
  const _RootTabs();

  @override
  State<_RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<_RootTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [DemoPage(), BenchmarkPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wifi), label: 'gRPC Demo'),
          NavigationDestination(
              icon: Icon(Icons.speed), label: 'NFR Benchmark'),
        ],
      ),
    );
  }
}
