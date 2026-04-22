/// grpc_client — public API of the Flutter package.
///
/// Drop-in replacement for the package that previously:
///   • spawned a Process and sent flags over stdin/stdout
///   • opened a WebSocket client for streaming
///
/// Now exposes a single [DemoClient] backed by one gRPC channel.
library grpc_client;

export 'src/benchmark_runner.dart';
export 'src/demo_client.dart';
export 'src/models.dart';
