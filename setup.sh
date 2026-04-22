#!/bin/bash
# setup.sh — one-shot setup for the gRPC demo.
# Supports macOS and Linux. Run once after cloning; re-run to regenerate proto files.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Locate Flutter / Dart ────────────────────────────────────────────────────
# Accept FLUTTER_HOME env override, otherwise fall back to PATH.
if [ -n "$FLUTTER_HOME" ]; then
  FLUTTER="$FLUTTER_HOME/bin/flutter"
  DART="$FLUTTER_HOME/bin/dart"
else
  FLUTTER="$(command -v flutter 2>/dev/null || true)"
  DART="$(command -v dart 2>/dev/null || true)"
fi

# ── Portable sed -i ──────────────────────────────────────────────────────────
# macOS BSD sed requires:  sed -i ''
# GNU sed (Linux) requires: sed -i
sedi() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

banner() { echo ""; echo "── $* ──"; }
ok()     { echo "  ✅ $*"; }
fail()   { echo "  ❌ $*"; exit 1; }

echo ""
echo "╔════════════════════════════════════╗"
echo "║       gRPC Demo  ·  Setup          ║"
echo "╚════════════════════════════════════╝"

# ── Dependency checks ────────────────────────────────────────────────────────
banner "Checking dependencies"

command -v python3 &>/dev/null && ok "python3" || fail "python3 not found. Install: sudo apt install python3 python3-venv  (or brew install python)"
command -v protoc  &>/dev/null && ok "protoc"  || fail "protoc not found. Install: sudo apt install protobuf-compiler  (or brew install protobuf)"
[ -n "$FLUTTER" ] && [ -f "$FLUTTER" ] && ok "flutter ($FLUTTER)" || fail "flutter not found. Add Flutter to PATH or set FLUTTER_HOME=/path/to/flutter"
[ -n "$DART"    ] && [ -f "$DART"    ] && ok "dart ($DART)"       || fail "dart not found alongside flutter"

# ── Python server ────────────────────────────────────────────────────────────
banner "Python server"
cd "$SCRIPT_DIR/python_server"

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

# grpc_tools generates an absolute import; fix it to a relative one.
sedi 's/^import demo_pb2 as demo__pb2/from . import demo_pb2 as demo__pb2/' \
  generated/demo_pb2_grpc.py 2>/dev/null || true

deactivate
ok "Proto generated → python_server/generated/"

# ── Dart / Flutter packages ───────────────────────────────────────────────────
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

banner "nfr_benchmark package"

NFR_DIR="$SCRIPT_DIR/flutter_demo/packages/nfr_benchmark"
cd "$NFR_DIR"
$FLUTTER pub get
ok "nfr_benchmark deps installed"

mkdir -p lib/src/generated
protoc \
  --dart_out=grpc:lib/src/generated \
  -I"$SCRIPT_DIR/proto" \
  "$SCRIPT_DIR/proto/demo.proto"
ok "Proto generated → nfr_benchmark/lib/src/generated/"

# ── Flutter app ───────────────────────────────────────────────────────────────
banner "Flutter app"
APP_DIR="$SCRIPT_DIR/flutter_demo/app"

# Detect which platforms to scaffold
PLATFORMS="android"
[[ "$OSTYPE" == "darwin"* ]] && PLATFORMS="$PLATFORMS,macos,ios"
[[ "$OSTYPE" == "linux"*  ]] && PLATFORMS="$PLATFORMS,linux"

if [ ! -d "$APP_DIR" ]; then
  echo "  Creating Flutter app scaffold..."
  cd "$SCRIPT_DIR/flutter_demo"
  $FLUTTER create \
    --org com.grpcdemo \
    --project-name grpc_demo_app \
    --platforms "$PLATFORMS" \
    app
  ok "Flutter app scaffolded (platforms: $PLATFORMS)"
fi

cp "$SCRIPT_DIR/flutter_demo/app_src/pubspec.yaml" "$APP_DIR/pubspec.yaml"
cp "$SCRIPT_DIR/flutter_demo/app_src/lib/main.dart" "$APP_DIR/lib/main.dart"
ok "pubspec.yaml + main.dart applied"

cd "$APP_DIR"
$FLUTTER pub get
ok "App deps installed"

# ── macOS-only: network entitlement ──────────────────────────────────────────
if [[ "$OSTYPE" == "darwin"* ]]; then
  banner "macOS entitlements"
  add_entitlement() {
    local FILE="$1"
    if [ -f "$FILE" ] && ! grep -q "network.client" "$FILE"; then
      sedi 's|</dict>|  <key>com.apple.security.network.client</key>\
  <true/>\
</dict>|' "$FILE"
      ok "Network entitlement added to $(basename "$FILE")"
    fi
  }
  add_entitlement "$APP_DIR/macos/Runner/DebugProfile.entitlements"
  add_entitlement "$APP_DIR/macos/Runner/Release.entitlements"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════╗"
echo "║          Setup complete!           ║"
echo "╚════════════════════════════════════╝"
echo ""
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "  Run the Flutter app (macOS):"
  echo "    cd flutter_demo/app && flutter run -d macos"
elif [[ "$OSTYPE" == "linux"* ]]; then
  echo "  Run the Flutter app (Linux desktop):"
  echo "    cd flutter_demo/app && flutter run -d linux"
fi
echo ""
