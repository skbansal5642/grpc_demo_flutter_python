/// Results for one implementation (old or gRPC).
class ImplResult {
  final String name;

  // Command / ack (unary)
  final double cmdP50;
  final double cmdP95;
  final double cmdP99;
  final double cmdRps;

  // Streaming
  final double strP50;
  final double strP95;
  final double strP99;
  final double strRps;

  const ImplResult({
    required this.name,
    required this.cmdP50,
    required this.cmdP95,
    required this.cmdP99,
    required this.cmdRps,
    required this.strP50,
    required this.strP95,
    required this.strP99,
    required this.strRps,
  });
}

/// Side-by-side comparison returned by [BenchmarkRunner].
class BenchmarkComparison {
  final ImplResult old;
  final ImplResult grpc;
  const BenchmarkComparison({required this.old, required this.grpc});
}
