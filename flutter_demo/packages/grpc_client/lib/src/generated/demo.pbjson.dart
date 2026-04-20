// This is a generated file - do not edit.
//
// Generated from demo.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use emptyDescriptor instead')
const Empty$json = {
  '1': 'Empty',
};

/// Descriptor for `Empty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyDescriptor =
    $convert.base64Decode('CgVFbXB0eQ==');

@$core.Deprecated('Use pingResponseDescriptor instead')
const PingResponse$json = {
  '1': 'PingResponse',
  '2': [
    {'1': 'server_version', '3': 1, '4': 1, '5': 9, '10': 'serverVersion'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `PingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingResponseDescriptor = $convert.base64Decode(
    'CgxQaW5nUmVzcG9uc2USJQoOc2VydmVyX3ZlcnNpb24YASABKAlSDXNlcnZlclZlcnNpb24SGA'
    'oHbWVzc2FnZRgCIAEoCVIHbWVzc2FnZQ==');

@$core.Deprecated('Use commandRequestDescriptor instead')
const CommandRequest$json = {
  '1': 'CommandRequest',
  '2': [
    {'1': 'command', '3': 1, '4': 1, '5': 9, '10': 'command'},
    {'1': 'payload', '3': 2, '4': 1, '5': 9, '10': 'payload'},
  ],
};

/// Descriptor for `CommandRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandRequestDescriptor = $convert.base64Decode(
    'Cg5Db21tYW5kUmVxdWVzdBIYCgdjb21tYW5kGAEgASgJUgdjb21tYW5kEhgKB3BheWxvYWQYAi'
    'ABKAlSB3BheWxvYWQ=');

@$core.Deprecated('Use commandResponseDescriptor instead')
const CommandResponse$json = {
  '1': 'CommandResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'result', '3': 3, '4': 1, '5': 9, '10': 'result'},
  ],
};

/// Descriptor for `CommandResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandResponseDescriptor = $convert.base64Decode(
    'Cg9Db21tYW5kUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxIYCgdtZXNzYWdlGA'
    'IgASgJUgdtZXNzYWdlEhYKBnJlc3VsdBgDIAEoCVIGcmVzdWx0');

@$core.Deprecated('Use streamRequestDescriptor instead')
const StreamRequest$json = {
  '1': 'StreamRequest',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'chunk_count', '3': 2, '4': 1, '5': 5, '10': 'chunkCount'},
  ],
};

/// Descriptor for `StreamRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamRequestDescriptor = $convert.base64Decode(
    'Cg1TdHJlYW1SZXF1ZXN0Eh0KCnNlc3Npb25faWQYASABKAlSCXNlc3Npb25JZBIfCgtjaHVua1'
    '9jb3VudBgCIAEoBVIKY2h1bmtDb3VudA==');

@$core.Deprecated('Use outputChunkDescriptor instead')
const OutputChunk$json = {
  '1': 'OutputChunk',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 5, '10': 'index'},
    {'1': 'data', '3': 2, '4': 1, '5': 9, '10': 'data'},
    {'1': 'is_final', '3': 3, '4': 1, '5': 8, '10': 'isFinal'},
  ],
};

/// Descriptor for `OutputChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List outputChunkDescriptor = $convert.base64Decode(
    'CgtPdXRwdXRDaHVuaxIUCgVpbmRleBgBIAEoBVIFaW5kZXgSEgoEZGF0YRgCIAEoCVIEZGF0YR'
    'IZCghpc19maW5hbBgDIAEoCFIHaXNGaW5hbA==');
