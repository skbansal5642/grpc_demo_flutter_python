// This is a generated file - do not edit.
//
// Generated from demo.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'demo.pb.dart' as $0;

export 'demo.pb.dart';

/// Single service replaces both:
///   - stdio flags + ack pattern  → ExecuteCommand (unary RPC)
///   - WebSocket streaming        → StreamOutput (server-streaming RPC)
@$pb.GrpcServiceName('demo.DemoService')
class DemoServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  DemoServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.PingResponse> ping(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$ping, request, options: options);
  }

  $grpc.ResponseFuture<$0.CommandResponse> executeCommand(
    $0.CommandRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$executeCommand, request, options: options);
  }

  $grpc.ResponseStream<$0.OutputChunk> streamOutput(
    $0.StreamRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$streamOutput, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$ping = $grpc.ClientMethod<$0.Empty, $0.PingResponse>(
      '/demo.DemoService/Ping',
      ($0.Empty value) => value.writeToBuffer(),
      $0.PingResponse.fromBuffer);
  static final _$executeCommand =
      $grpc.ClientMethod<$0.CommandRequest, $0.CommandResponse>(
          '/demo.DemoService/ExecuteCommand',
          ($0.CommandRequest value) => value.writeToBuffer(),
          $0.CommandResponse.fromBuffer);
  static final _$streamOutput =
      $grpc.ClientMethod<$0.StreamRequest, $0.OutputChunk>(
          '/demo.DemoService/StreamOutput',
          ($0.StreamRequest value) => value.writeToBuffer(),
          $0.OutputChunk.fromBuffer);
}

@$pb.GrpcServiceName('demo.DemoService')
abstract class DemoServiceBase extends $grpc.Service {
  $core.String get $name => 'demo.DemoService';

  DemoServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.PingResponse>(
        'Ping',
        ping_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.PingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CommandRequest, $0.CommandResponse>(
        'ExecuteCommand',
        executeCommand_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CommandRequest.fromBuffer(value),
        ($0.CommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StreamRequest, $0.OutputChunk>(
        'StreamOutput',
        streamOutput_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.StreamRequest.fromBuffer(value),
        ($0.OutputChunk value) => value.writeToBuffer()));
  }

  $async.Future<$0.PingResponse> ping_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return ping($call, await $request);
  }

  $async.Future<$0.PingResponse> ping($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.CommandResponse> executeCommand_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CommandRequest> $request) async {
    return executeCommand($call, await $request);
  }

  $async.Future<$0.CommandResponse> executeCommand(
      $grpc.ServiceCall call, $0.CommandRequest request);

  $async.Stream<$0.OutputChunk> streamOutput_Pre($grpc.ServiceCall $call,
      $async.Future<$0.StreamRequest> $request) async* {
    yield* streamOutput($call, await $request);
  }

  $async.Stream<$0.OutputChunk> streamOutput(
      $grpc.ServiceCall call, $0.StreamRequest request);
}
