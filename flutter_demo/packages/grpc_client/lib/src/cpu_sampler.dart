import 'dart:async';
import 'dart:io';

/// Samples the CPU usage of a single process by reading /proc/{pid}/stat.
/// Linux-only — returns zeros silently on other platforms.
///
/// Usage:
///   final sampler = CpuSampler(pid: client.pid);
///   await sampler.start();
///   // ... run benchmark ...
///   final result = sampler.stop();
///   print('avg: ${result.avgPercent}%  peak: ${result.peakPercent}%');
class CpuSampler {
  final int pid;

  /// How often to read /proc/{pid}/stat.
  /// 500 ms is fine for benchmarks that run several seconds.
  final Duration interval;

  CpuSampler({required this.pid, this.interval = const Duration(milliseconds: 200)});

  // ── Internal state ──────────────────────────────────────────────────────────

  Timer? _timer;
  final _samples = <double>[];

  int _lastTicks = 0;
  DateTime _lastTime = DateTime.now();

  // Linux scheduler ticks per second — 100 on all modern kernels (Raspberry Pi included).
  static const int _hz = 100;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Begin periodic sampling. Call before the measurement loop.
  Future<void> start() async {
    _samples.clear();
    _lastTicks = await _readTicks();
    _lastTime = DateTime.now();

    _timer = Timer.periodic(interval, (_) async {
      final ticks = await _readTicks();
      final now = DateTime.now();
      final elapsedSec = now.difference(_lastTime).inMicroseconds / 1e6;

      if (elapsedSec > 0 && ticks >= _lastTicks) {
        // cpu% = ticks used in window / seconds in window / hz * 100
        final pct = (ticks - _lastTicks) / elapsedSec / _hz * 100;
        _samples.add(pct.clamp(0.0, 100.0 * Platform.numberOfProcessors));
      }

      _lastTicks = ticks;
      _lastTime = now;
    });
  }

  /// Stop sampling and return the aggregated result.
  CpuResult stop() {
    _timer?.cancel();
    _timer = null;

    if (_samples.isEmpty) return CpuResult.zero;

    final avg = _samples.reduce((a, b) => a + b) / _samples.length;
    final peak = _samples.reduce((a, b) => a > b ? a : b);

    return CpuResult(
      avgPercent: double.parse(avg.toStringAsFixed(1)),
      peakPercent: double.parse(peak.toStringAsFixed(1)),
    );
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  /// Returns utime + stime for the process (total CPU ticks consumed so far).
  /// Returns 0 on non-Linux platforms or if the process has already exited.
  Future<int> _readTicks() async {
    if (!Platform.isLinux) return 0;
    try {
      final content = await File('/proc/$pid/stat').readAsString();
      // Format: pid (name) state ... utime stime ...
      // The name field may contain spaces; find the last ')' to skip it safely.
      final afterName = content.substring(content.lastIndexOf(')') + 2);
      final fields = afterName.trim().split(' ');
      // Full field layout after the closing ')' (0-indexed):
      // [0]=state [1]=ppid [2]=pgrp [3]=session [4]=tty_nr [5]=tpgid
      // [6]=flags [7]=minflt [8]=cminflt [9]=majflt [10]=cmajflt
      // [11]=utime  [12]=stime  ← these are the CPU tick counters
      final utime = int.parse(fields[11]);
      final stime = int.parse(fields[12]);
      return utime + stime;
    } catch (_) {
      return 0; // process exited or platform not supported
    }
  }
}

/// Aggregated CPU result from one measurement window.
class CpuResult {
  final double avgPercent;
  final double peakPercent;

  const CpuResult({required this.avgPercent, required this.peakPercent});

  static const zero = CpuResult(avgPercent: 0, peakPercent: 0);
}
