#!/bin/bash
# setup.sh — one-shot setup for the gRPC demo.
# Run once; re-run any time to regenerate proto files.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER="/Users/spurge/SDKs/flutter/bin/flutter"
DART="/Users/spurge/SDKs/flutter/bin/dart"

banner() { echo ""; echo "── $* ──"; }
ok()     { echo "  ✅ $*"; }
fail()   { echo "  ❌ $*"; exit 1; }

echo ""
echo "╔════════════════════════════════════╗"
echo "║       gRPC Demo  ·  Setup          ║"
echo "╚════════════════════════════════════╝"

# ── Dependency checks ────────────────────────────────────────────────────────
banner "Checking dependencies"

command -v python3 &>/dev/null && ok "python3" || fail "python3 not found. Install from https://python.org"
command -v protoc  &>/dev/null && ok "protoc"  || fail "protoc not found. Run: brew install protobuf"
[ -f "$FLUTTER" ]              && ok "flutter ($FLUTTER)" || fail "flutter not found at $FLUTTER"

# ── Python server ────────────────────────────────────────────────────────────
banner "Python server"
cd "$SCRIPT_DIR/python_server"

# Use a venv to avoid the PEP 668 "externally managed environment" restriction.
if [ ! -d "venv" ]; then
  python3 -m venv venv
  ok "venv created"
fi
source venv/bin/activate
pip install -r requirements.txt
ok "Python deps installed in venv"

mkdir -p generated
touch generated/__init__.py
python -m grpc_tools.protoc \
  -I"$SCRIPT_DIR/proto" \
  --python_out=generated \
  --grpc_python_out=generated \
  "$SCRIPT_DIR/proto/demo.proto"

# grpc_tools generates an absolute import; fix it to a relative one so the
# generated package resolves correctly when run from any directory.
sed -i '' 's/^import demo_pb2 as demo__pb2/from . import demo_pb2 as demo__pb2/' \
  generated/demo_pb2_grpc.py 2>/dev/null \
|| sed -i   's/^import demo_pb2 as demo__pb2/from . import demo_pb2 as demo__pb2/' \
  generated/demo_pb2_grpc.py 2>/dev/null \
|| true

deactivate
ok "Proto generated → python_server/generated/"

# ── Dart / Flutter package ───────────────────────────────────────────────────
banner "Flutter grpc_client package"

$DART pub global activate protoc_plugin
export PATH="$PATH:$HOME/.pub-cache/bin"

PKG_DIR="$SCRIPT_DIR/flutter_demo/packages/grpc_client"
cd "$PKG_DIR"
$FLUTTER pub get
ok "grpc_client deps installed"

mkdir -p lib/src/generated
protoc \
  --dart_out=grpc:lib/src/generated \
  -I"$SCRIPT_DIR/proto" \
  "$SCRIPT_DIR/proto/demo.proto"
ok "Proto generated → grpc_client/lib/src/generated/"

# ── Flutter app (scaffold if needed) ────────────────────────────────────────
banner "Flutter app"
APP_DIR="$SCRIPT_DIR/flutter_demo/app"

if [ ! -d "$APP_DIR" ]; then
  echo "  Creating Flutter app scaffold..."
  cd "$SCRIPT_DIR/flutter_demo"
  $FLUTTER create \
    --org com.grpcdemo \
    --project-name grpc_demo_app \
    --platforms macos,ios,android \
    app
  ok "Flutter app scaffolded"
fi

# Copy our pubspec + main.dart over the scaffold defaults
cp "$SCRIPT_DIR/flutter_demo/app_src/pubspec.yaml" "$APP_DIR/pubspec.yaml"
cp "$SCRIPT_DIR/flutter_demo/app_src/lib/main.dart" "$APP_DIR/lib/main.dart"
ok "pubspec.yaml + main.dart applied"

cd "$APP_DIR"
$FLUTTER pub get
ok "App deps installed"

# macOS needs an explicit network-client entitlement for outbound TCP (gRPC uses HTTP/2)
add_entitlement() {
  local FILE="$1"
  if [ -f "$FILE" ] && ! grep -q "network.client" "$FILE"; then
    sed -i '' 's|</dict>|  <key>com.apple.security.network.client</key>\
  <true/>\
</dict>|' "$FILE"
    ok "Network entitlement added to $(basename "$FILE")"
  fi
}
add_entitlement "$APP_DIR/macos/Runner/DebugProfile.entitlements"
add_entitlement "$APP_DIR/macos/Runner/Release.entitlements"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════╗"
echo "║          Setup complete!           ║"
echo "╚════════════════════════════════════╝"
echo ""
echo "  Run the Flutter app:"
echo "    cd grpc_demo/flutter_demo/app && $FLUTTER run -d macos"
echo ""
