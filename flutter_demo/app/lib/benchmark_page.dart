// ══════════════════════════════════════════════════════════════════════════════
// Benchmark Page
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:grpc_client/grpc_client.dart';

const _defaultServerPath =
    '/Users/spurge/Documents/claude_workspace/grpc_demo/python_server';

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  final _pathController = TextEditingController(text: _defaultServerPath);
  final _logs = <String>[];
  bool _running = false;
  BenchmarkComparison? _results;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
      _logs.clear();
    });

    try {
      final runner = BenchmarkRunner(
        nCommand: 100,
        nStream: 30,
        chunks: 5,
        warmup: 10,
        onProgress: (msg) => setState(() => _logs.add(msg)),
      );
      final results = await runner.run(serverDirectory: _pathController.text);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _logs.add('Error: $e'));
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFR Benchmark'),
        centerTitle: true,
        backgroundColor: cs.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running benchmark…' : 'Run Benchmark'),
            ),
          ),
          const Divider(height: 1),

          if (_results != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 600),
              child: SingleChildScrollView(
                child: _ResultsTable(comparison: _results!),
              ),
            ),
            const Divider(height: 1),
          ],

          // Progress log
          Expanded(
            child: Container(
              color: const Color(0xFF1E1E1E),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Press Run Benchmark to start.\nBoth servers start and stop automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          _logs[i],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Results table ─────────────────────────────────────────────────────────────

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.comparison});
  final BenchmarkComparison comparison;

  @override
  Widget build(BuildContext context) {
    final old = comparison.old;
    final grpc = comparison.grpc;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(6)),
          children: [
            _headerRow(),
            _sectionRow('Command / Ack (unary)'),
            _metricRow('Latency p50', old.cmdP50, grpc.cmdP50, 'ms'),
            _metricRow('Latency p95', old.cmdP95, grpc.cmdP95, 'ms'),
            _metricRow('Latency p99', old.cmdP99, grpc.cmdP99, 'ms'),
            _metricRow('Throughput', old.cmdRps, grpc.cmdRps, 'rps',
                higherIsBetter: true),
            _sectionRow('Streaming'),
            _metricRow('Latency p50', old.strP50, grpc.strP50, 'ms'),
            _metricRow('Latency p95', old.strP95, grpc.strP95, 'ms'),
            _metricRow('Latency p99', old.strP99, grpc.strP99, 'ms'),
            _metricRow('Throughput', old.strRps, grpc.strRps, 'rps',
                higherIsBetter: true),
          ],
        ),
      ),
    );
  }

  TableRow _headerRow() => TableRow(
        decoration: BoxDecoration(color: Colors.indigo.shade50),
        children: ['Metric', 'Old (stdio + WS)', 'New (gRPC)', 'Winner']
            .map((t) => _cell(t, bold: true))
            .toList(),
      );

  TableRow _sectionRow(String label) => TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade100),
        children: [
          _cell(label, bold: true, colspan: true),
          _cell(''),
          _cell(''),
          _cell(''),
        ],
      );

  TableRow _metricRow(String label, double oldVal, double grpcVal, String unit,
      {bool higherIsBetter = false}) {
    final grpcWins = higherIsBetter ? grpcVal > oldVal : grpcVal < oldVal;
    return TableRow(children: [
      _cell(label),
      _cell('${oldVal.toStringAsFixed(2)} $unit'),
      _cell('${grpcVal.toStringAsFixed(2)} $unit',
          color: grpcWins ? Colors.green.shade700 : null),
      _cell(grpcWins ? '✓ gRPC' : '— tie',
          color: grpcWins ? Colors.green.shade700 : Colors.grey),
    ]);
  }

  Widget _cell(String text,
          {bool bold = false, Color? color, bool colspan = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
            fontSize: 13,
          ),
        ),
      );
}
