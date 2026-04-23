import 'dart:io';

import 'package:grpc_client/src/grpc_bench_client.dart';

import 'cpu_sampler.dart';
import 'models.dart';
import 'old_client.dart';

/// Runs both implementations back-to-back and returns a [BenchmarkComparison].
/// All timings are measured Flutter-side using [Stopwatch] — true round-trip
/// from Dart sending the request to Dart receiving the response.
/// CPU usage is sampled from /proc/{pid}/stat on Linux (zero on other platforms).
class BenchmarkRunner {
  final int nCommand; // number of command/ack iterations
  final int nStream; // number of streaming iterations
  final int chunks; // chunks per stream call
  final int warmup; // warm-up iterations (excluded from results)

  /// [onProgress] is called with status messages so the UI can show progress.
  final void Function(String message)? onProgress;

  BenchmarkRunner({
    this.nCommand = 100,
    this.nStream = 30,
    this.chunks = 5,
    this.warmup = 10,
    this.onProgress,
  });

  // ── Public API ─────────────────────────────────────────────────────────────

  /// [serverDirectory] = absolute path to python_server/
  Future<BenchmarkComparison> run({required String serverDirectory}) async {
    if (!Platform.isLinux) {
      _log('ℹ️  CPU sampling is Linux-only — will show N/A on this platform.');
    }
    final oldResult = await _runOld(serverDirectory);
    final grpcResult = await _runGrpc(serverDirectory);
    return BenchmarkComparison(
      old: oldResult,
      grpc: grpcResult,
      cpuAvailable: Platform.isLinux,
    );
  }

  // ── Old implementation ─────────────────────────────────────────────────────

  Future<ImplResult> _runOld(String serverDirectory) async {
    _log('Starting Old server (stdio + WebSocket)…');
    final client = OldClient();
    await client.connect(serverDirectory: serverDirectory);

    // Warm up
    _log('Warming up Old server…');
    for (var i = 0; i < warmup; i++) {
      await client.executeCommand('process', payload: 'warmup');
    }

    // Command round-trips
    _log('Old — measuring $nCommand command round-trips…');
    final cmdSampler = CpuSampler(pid: client.pid);
    await cmdSampler.start();
    final cmdMs = <double>[];
    final cmdStart = Stopwatch()..start();
    for (var i = 0; i < nCommand; i++) {
      final t = Stopwatch()..start();
      await client.executeCommand('process', payload: 'hello world');
      cmdMs.add(t.elapsedMicroseconds / 1000.0);
    }
    final cmdElapsed = cmdStart.elapsedMicroseconds / 1e6;
    final cmdCpu = cmdSampler.stop();

    // Stream round-trips
    _log('Old — measuring $nStream stream round-trips ($chunks chunks each)…');
    final strSampler = CpuSampler(pid: client.pid);
    await strSampler.start();
    final strMs = <double>[];
    final strStart = Stopwatch()..start();
    for (var i = 0; i < nStream; i++) {
      final t = Stopwatch()..start();
      await for (final _ in client.streamOutput('bench-$i', chunkCount: chunks)) {}
      strMs.add(t.elapsedMicroseconds / 1000.0);
    }
    final strElapsed = strStart.elapsedMicroseconds / 1e6;
    final strCpu = strSampler.stop();

    await client.disconnect();
    _log('Old server stopped.');

    return _compute(
      name: 'Old (stdio + WebSocket)',
      cmdMs: cmdMs,
      cmdElapsed: cmdElapsed,
      cmdCpuAvg: cmdCpu.avgPercent,
      cmdCpuPeak: cmdCpu.peakPercent,
      strMs: strMs,
      strElapsed: strElapsed,
      strCpuAvg: strCpu.avgPercent,
      strCpuPeak: strCpu.peakPercent,
    );
  }

  // ── gRPC implementation ────────────────────────────────────────────────────

  Future<ImplResult> _runGrpc(String serverDirectory) async {
    _log('Starting gRPC server…');
    final client = GrpcBenchClient();
    await client.connect(serverDirectory: serverDirectory);

    // Warm up
    _log('Warming up gRPC server…');
    for (var i = 0; i < warmup; i++) {
      await client.executeCommand('process', payload: 'warmup');
    }

    // Command round-trips
    _log('gRPC — measuring $nCommand command round-trips…');
    final cmdSampler = CpuSampler(pid: client.pid);
    await cmdSampler.start();
    final cmdMs = <double>[];
    final cmdStart = Stopwatch()..start();
    for (var i = 0; i < nCommand; i++) {
      final t = Stopwatch()..start();
      await client.executeCommand('process', payload: 'hello world');
      cmdMs.add(t.elapsedMicroseconds / 1000.0);
    }
    final cmdElapsed = cmdStart.elapsedMicroseconds / 1e6;
    final cmdCpu = cmdSampler.stop();

    // Stream round-trips
    _log('gRPC — measuring $nStream stream round-trips ($chunks chunks each)…');
    final strSampler = CpuSampler(pid: client.pid);
    await strSampler.start();
    final strMs = <double>[];
    final strStart = Stopwatch()..start();
    for (var i = 0; i < nStream; i++) {
      final t = Stopwatch()..start();
      await for (final _ in client.streamOutput('bench-$i', chunkCount: chunks)) {}
      strMs.add(t.elapsedMicroseconds / 1000.0);
    }
    final strElapsed = strStart.elapsedMicroseconds / 1e6;
    final strCpu = strSampler.stop();

    await client.disconnect();
    _log('gRPC server stopped.');

    return _compute(
      name: 'New (gRPC)',
      cmdMs: cmdMs,
      cmdElapsed: cmdElapsed,
      cmdCpuAvg: cmdCpu.avgPercent,
      cmdCpuPeak: cmdCpu.peakPercent,
      strMs: strMs,
      strElapsed: strElapsed,
      strCpuAvg: strCpu.avgPercent,
      strCpuPeak: strCpu.peakPercent,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  ImplResult _compute({
    required String name,
    required List<double> cmdMs,
    required double cmdElapsed,
    required double cmdCpuAvg,
    required double cmdCpuPeak,
    required List<double> strMs,
    required double strElapsed,
    required double strCpuAvg,
    required double strCpuPeak,
  }) {
    cmdMs.sort();
    strMs.sort();
    return ImplResult(
      name: name,
      cmdP50: _p(cmdMs, 50),
      cmdP95: _p(cmdMs, 95),
      cmdP99: _p(cmdMs, 99),
      cmdRps: nCommand / cmdElapsed,
      cmdCpuAvg: cmdCpuAvg,
      cmdCpuPeak: cmdCpuPeak,
      strP50: _p(strMs, 50),
      strP95: _p(strMs, 95),
      strP99: _p(strMs, 99),
      strRps: nStream / strElapsed,
      strCpuAvg: strCpuAvg,
      strCpuPeak: strCpuPeak,
    );
  }

  static double _p(List<double> sorted, int percentile) {
    if (sorted.isEmpty) return 0;
    final k = (sorted.length - 1) * percentile / 100;
    final lo = k.floor();
    final hi = (lo + 1).clamp(0, sorted.length - 1);
    return double.parse(
      (sorted[lo] + (sorted[hi] - sorted[lo]) * (k - lo)).toStringAsFixed(2),
    );
  }

  void _log(String msg) => onProgress?.call(msg);
}
