/// Results for one implementation (old or gRPC).
class ImplResult {
  final String name;

  // Command / ack (unary)
  final double cmdP50;
  final double cmdP95;
  final double cmdP99;
  final double cmdRps;
  final double cmdCpuAvg;   // average server CPU % during command benchmark
  final double cmdCpuPeak;  // peak server CPU % during command benchmark

  // Streaming
  final double strP50;
  final double strP95;
  final double strP99;
  final double strRps;
  final double strCpuAvg;   // average server CPU % during stream benchmark
  final double strCpuPeak;  // peak server CPU % during stream benchmark

  const ImplResult({
    required this.name,
    required this.cmdP50,
    required this.cmdP95,
    required this.cmdP99,
    required this.cmdRps,
    this.cmdCpuAvg = 0,
    this.cmdCpuPeak = 0,
    required this.strP50,
    required this.strP95,
    required this.strP99,
    required this.strRps,
    this.strCpuAvg = 0,
    this.strCpuPeak = 0,
  });
}

/// Side-by-side comparison returned by [BenchmarkRunner].
class BenchmarkComparison {
  final ImplResult old;
  final ImplResult grpc;

  /// True only on Linux where /proc/{pid}/stat is available.
  /// False on macOS / Windows — CPU columns should show "N/A".
  final bool cpuAvailable;

  const BenchmarkComparison({
    required this.old,
    required this.grpc,
    this.cpuAvailable = false,
  });
}
