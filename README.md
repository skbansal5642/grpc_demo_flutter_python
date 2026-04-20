# gRPC Demo

A working demo that replaces a dual-channel **stdio-flags + WebSocket** communication architecture with a single, typed **gRPC** channel between a Flutter app, a Flutter package, and a Python server.

---

## Why gRPC?

| Old pattern | gRPC replacement |
|---|---|
| Write flag string to `stdin`, poll `stdout` for ack | Unary RPC — typed request in, typed response out |
| Open WebSocket, send/receive raw frames, close | Server-streaming RPC — typed chunks until stream ends |
| Two channels to manage | Single `ClientChannel` |
| String-based contracts, easy to break | `.proto` schema — enforced on both sides |
| Manual error handling | gRPC status codes built-in |

---

## Architecture

```
Flutter App  (flutter_demo/app/)
  └─ grpc_client package  (flutter_demo/packages/grpc_client/)
       ├─ demo_client.dart          ← your wrapper: connect/disconnect/call
       └─ generated/                ← protoc output (gitignored, created by setup.sh)
            ├─ demo.pb.dart
            └─ demo.pbgrpc.dart
                    ↕  HTTP/2  (gRPC)
            Python gRPC Server  (python_server/)
                 └─ server.py
```

### Communication patterns

| Button in app | Pattern | gRPC call |
|---|---|---|
| **Ping** | Health check | Unary `Ping` |
| **Execute Command** | Send command → get result | Unary `ExecuteCommand` |
| **Trigger Error** | Error path demo | Unary `ExecuteCommand(error)` |
| **Stream Output** | Receive data chunks | Server-streaming `StreamOutput` |

The app launches the Python server automatically on connect and kills it on disconnect — no manual terminal steps for the end user.

---

## Prerequisites

Install these before running setup:

| Tool | Install |
|---|---|
| Python 3.9+ | <https://python.org> or `brew install python` |
| Flutter 3.10+ | <https://flutter.dev/docs/get-started/install> |
| protoc | `brew install protobuf` |

> `protoc` is needed by `setup.sh` to generate client code. After setup it is only needed again when `demo.proto` changes.

---

## Setup

> **Note:** Generated files are gitignored and not included in the repo. `setup.sh` creates everything from scratch. Run it once after cloning.

### 1. Clone

```bash
git clone https://github.com/skbansal5642/grpc_demo_flutter_python
cd grpc_demo
```

### 2. Run setup

```bash
chmod +x setup.sh
./setup.sh
```

`setup.sh` does the following in order:

| Step | What happens |
|---|---|
| Creates `python_server/venv/` | Isolated Python environment |
| Installs Python deps into venv | `grpcio`, `grpcio-tools` |
| Generates `python_server/generated/` | `demo_pb2.py`, `demo_pb2_grpc.py` from `demo.proto` |
| Activates `protoc-gen-dart` plugin | Via `dart pub global activate` |
| Generates `grpc_client/lib/src/generated/` | `demo.pb.dart`, `demo.pbgrpc.dart` from `demo.proto` |
| Scaffolds `flutter_demo/app/` | Runs `flutter create` if app doesn't exist |
| Installs Flutter deps | `flutter pub get` in both package and app |
| Adds macOS network entitlement | Required for outbound gRPC (HTTP/2) connections |

### 3. Run the app

```bash
cd flutter_demo/app
flutter run -d macos
```

Press **Start & Connect** in the app — it will automatically start the Python gRPC server and connect to it.

---

## Project Structure

```
grpc_demo/
├── setup.sh                              # Run once after cloning
├── .gitignore
├── proto/
│   └── demo.proto                        # Source of truth for both sides
│
├── python_server/
│   ├── server.py                         # gRPC server implementation
│   ├── start_server.sh                   # Convenience launcher (activates venv)
│   ├── requirements.txt
│   ├── venv/                             # ← gitignored, created by setup.sh
│   └── generated/                        # ← gitignored, created by setup.sh
│       ├── demo_pb2.py
│       └── demo_pb2_grpc.py
│
└── flutter_demo/
    ├── packages/
    │   └── grpc_client/                  # Flutter package (gRPC layer)
    │       ├── pubspec.yaml
    │       └── lib/
    │           ├── grpc_client.dart      # Public API export
    │           └── src/
    │               ├── demo_client.dart  # Hand-written wrapper — edit this
    │               └── generated/        # ← gitignored, created by setup.sh
    │                   ├── demo.pb.dart
    │                   ├── demo.pbgrpc.dart
    │                   ├── demo.pbenum.dart
    │                   └── demo.pbjson.dart
    └── app/
        ├── pubspec.yaml
        ├── lib/
        │   └── main.dart                 # Flutter UI
        └── test/
            └── widget_test.dart
```

---

## Regenerating Proto Files

When `demo.proto` changes, regenerate both sides and commit the results:

**Python:**
```bash
cd python_server
source venv/bin/activate
python -m grpc_tools.protoc \
  -I../proto \
  --python_out=generated \
  --grpc_python_out=generated \
  ../proto/demo.proto
```

**Dart:**
```bash
cd flutter_demo/packages/grpc_client
protoc \
  --dart_out=grpc:lib/src/generated \
  -I../../proto \
  ../../proto/demo.proto
```

Then update `demo_client.dart` if any method signatures changed.

---

## Team Ownership

| Artifact | Owner |
|---|---|
| `proto/demo.proto` | Shared — changes require agreement from both teams |
| `python_server/` | Python team |
| `packages/grpc_client/lib/src/generated/` | Generated — re-run protoc when proto changes |
| `packages/grpc_client/lib/src/demo_client.dart` | Flutter team |
| `flutter_demo/app/` | Flutter team |

> **Recommended:** As the project matures, move `demo.proto` to a dedicated shared repo and reference it as a git submodule in both repos. CI/CD can then auto-publish a new `grpc_client` package version whenever the proto changes.

---

## Dependencies

**Python**
- `grpcio` — gRPC runtime
- `grpcio-tools` — proto compiler plugin for Python

**Dart / Flutter**
- [`grpc`](https://pub.dev/packages/grpc) `^5.1.0`
- [`protobuf`](https://pub.dev/packages/protobuf) `^6.0.0`
