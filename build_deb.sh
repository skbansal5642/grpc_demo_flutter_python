#!/bin/bash
# build_deb.sh — builds a distributable .deb for the gRPC Demo Flutter app.
#
# Prerequisites (run once before this script):
#   1. ./setup.sh          — generates proto files and installs deps
#   2. Linux host machine  — Flutter Linux desktop toolchain must be present
#
# Usage:
#   ./build_deb.sh
#   FLUTTER_HOME=/path/to/flutter ./build_deb.sh   # if flutter not in PATH
#   VERSION=2.0.0 ./build_deb.sh                   # override version
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${VERSION:-1.0.0}"
PKG_NAME="grpc-demo-app"

# Detect CPU architecture and map to deb + Flutter bundle path names
_MACHINE="$(uname -m)"
case "$_MACHINE" in
  x86_64)           ARCH="amd64";  FLUTTER_ARCH="x64"  ;;
  aarch64|arm64)    ARCH="arm64";  FLUTTER_ARCH="arm64" ;;
  armv7l)           ARCH="armhf";  FLUTTER_ARCH="arm"   ;;
  *)                ARCH="$_MACHINE"; FLUTTER_ARCH="$_MACHINE" ;;
esac

DEB_STEM="${PKG_NAME}_${VERSION}_${ARCH}"
OUT_DIR="$SCRIPT_DIR/dist"
STAGING="$OUT_DIR/$DEB_STEM"

# ── Locate Flutter ─────────────────────────────────────────────────────────────
if [ -n "$FLUTTER_HOME" ]; then
  FLUTTER="$FLUTTER_HOME/bin/flutter"
else
  FLUTTER="$(command -v flutter 2>/dev/null || true)"
fi
[ -f "$FLUTTER" ] || { echo "❌ flutter not found. Add to PATH or set FLUTTER_HOME=/path/to/flutter"; exit 1; }

banner() { echo ""; echo "── $* ──"; }
ok()     { echo "  ✅ $*"; }
fail()   { echo "  ❌ $*"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   gRPC Demo  ·  Build .deb  v${VERSION}      ║"
echo "╚══════════════════════════════════════════╝"
echo "  Host arch : $_MACHINE  →  deb=$ARCH  flutter=$FLUTTER_ARCH"

# ── Pre-flight checks ──────────────────────────────────────────────────────────
banner "Pre-flight checks"

[ -f "$SCRIPT_DIR/python_server/generated/demo_pb2.py" ] \
  && ok "Python proto files present" \
  || fail "Python proto files missing — run ./setup.sh first"

[ -f "$SCRIPT_DIR/flutter_demo/packages/grpc_client/lib/src/generated/demo.pb.dart" ] \
  && ok "Dart proto files present" \
  || fail "Dart proto files missing — run ./setup.sh first"

command -v dpkg-deb &>/dev/null \
  && ok "dpkg-deb" \
  || fail "dpkg-deb not found — install: sudo apt install dpkg"

# ── Build Flutter release ──────────────────────────────────────────────────────
banner "Building Flutter release (linux)"
cd "$SCRIPT_DIR/flutter_demo/app"
$FLUTTER build linux --release
BUNDLE="$SCRIPT_DIR/flutter_demo/app/build/linux/$FLUTTER_ARCH/release/bundle"
[ -f "$BUNDLE/grpc_demo_app" ] && ok "Flutter bundle ready" || fail "Flutter build failed"

# ── Stage package tree ─────────────────────────────────────────────────────────
banner "Staging package"
rm -rf "$STAGING"
mkdir -p \
  "$STAGING/DEBIAN" \
  "$STAGING/opt/grpc_demo/app" \
  "$STAGING/opt/grpc_demo/python_server" \
  "$STAGING/opt/grpc_demo/benchmark" \
  "$STAGING/usr/local/bin" \
  "$STAGING/usr/share/applications"

# Flutter bundle
cp -r "$BUNDLE/." "$STAGING/opt/grpc_demo/app/"
ok "Flutter bundle copied"

# Python demo server (no venv — postinst builds it on the target)
cp "$SCRIPT_DIR/python_server/server.py"         "$STAGING/opt/grpc_demo/python_server/"
cp "$SCRIPT_DIR/python_server/requirements.txt"  "$STAGING/opt/grpc_demo/python_server/"
cp -r "$SCRIPT_DIR/python_server/generated"      "$STAGING/opt/grpc_demo/python_server/"
ok "Python server files copied"

# Benchmark servers (grpc_bench_client.dart resolves them via ../benchmark/)
cp "$SCRIPT_DIR/benchmark/grpc_bench_server.py"  "$STAGING/opt/grpc_demo/benchmark/"
cp "$SCRIPT_DIR/benchmark/old_server.py"          "$STAGING/opt/grpc_demo/benchmark/"
ok "Benchmark server files copied"

# ── /usr/local/bin launcher ────────────────────────────────────────────────────
cat > "$STAGING/usr/local/bin/grpc-demo-app" << 'EOF'
#!/bin/bash
exec /opt/grpc_demo/app/grpc_demo_app "$@"
EOF
chmod 755 "$STAGING/usr/local/bin/grpc-demo-app"
ok "Launcher script created"

# ── .desktop entry ─────────────────────────────────────────────────────────────
cat > "$STAGING/usr/share/applications/grpc-demo-app.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Name=gRPC Demo
Comment=Flutter gRPC Demo & NFR Benchmark
Exec=/opt/grpc_demo/app/grpc_demo_app
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Development;Utility;
StartupWMClass=grpc_demo_app
EOF
ok ".desktop entry created"

# ── DEBIAN/control ─────────────────────────────────────────────────────────────
cat > "$STAGING/DEBIAN/control" << EOF
Package: $PKG_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: Shubham Bansal <shubham.bansal@aarogyatech.com>
Depends: python3 (>= 3.9), python3-venv,
 libgtk-3-0, libglib2.0-0, libpango-1.0-0, libcairo2,
 libgdk-pixbuf-2.0-0, libatk1.0-0,
 libegl1, libgles2,
 libx11-6, libxcomposite1, libxcursor1, libxdamage1,
 libxext6, libxfixes3, libxi6, libxrandr2, libxrender1,
 libblkid1, liblzma5
Description: gRPC Demo Flutter Application
 A Flutter desktop app demonstrating gRPC communication with a Python server.
 Includes an NFR benchmarking tool comparing gRPC vs the old stdio+WebSocket
 architecture, measuring p50/p95/p99 latency and throughput.
 Built for Raspberry Pi (ARM64) running Debian 12.
EOF
ok "DEBIAN/control written"

# ── DEBIAN/postinst — create Python venv on the target ─────────────────────────
cat > "$STAGING/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
SERVER_DIR="/opt/grpc_demo/python_server"

echo "Setting up Python environment for gRPC Demo..."
if [ ! -d "$SERVER_DIR/venv" ]; then
  python3 -m venv "$SERVER_DIR/venv"
fi
"$SERVER_DIR/venv/bin/pip" install --quiet --upgrade pip
"$SERVER_DIR/venv/bin/pip" install --quiet -r "$SERVER_DIR/requirements.txt"

# Ensure the app binary is executable
chmod 755 /opt/grpc_demo/app/grpc_demo_app
chmod -R a+rX /opt/grpc_demo/

echo "✅ gRPC Demo installed successfully."
echo "   Launch: grpc-demo-app  (terminal) or find it in your application menu."
EOF
chmod 755 "$STAGING/DEBIAN/postinst"

# ── DEBIAN/prerm — stop running instances before upgrade/removal ───────────────
cat > "$STAGING/DEBIAN/prerm" << 'EOF'
#!/bin/bash
pkill -f grpc_demo_app     2>/dev/null || true
pkill -f grpc_bench_server 2>/dev/null || true
pkill -f old_server        2>/dev/null || true
exit 0
EOF
chmod 755 "$STAGING/DEBIAN/prerm"

# ── DEBIAN/postrm — purge removes the venv ────────────────────────────────────
cat > "$STAGING/DEBIAN/postrm" << 'EOF'
#!/bin/bash
if [ "$1" = "purge" ]; then
  rm -rf /opt/grpc_demo/python_server/venv
  rmdir --ignore-fail-on-non-empty /opt/grpc_demo 2>/dev/null || true
fi
exit 0
EOF
chmod 755 "$STAGING/DEBIAN/postrm"

# ── Build .deb ─────────────────────────────────────────────────────────────────
banner "Building .deb"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"
dpkg-deb --build --root-owner-group "$DEB_STEM"
ok ".deb created: dist/${DEB_STEM}.deb"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        .deb package ready!               ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  File:  dist/${DEB_STEM}.deb"
echo "  Size:  $(du -sh "$OUT_DIR/${DEB_STEM}.deb" | cut -f1)"
echo ""
echo "  ── Install on target machine ──"
echo "  sudo dpkg -i ${DEB_STEM}.deb"
echo "  sudo apt-get install -f    # pull in any missing system libs"
echo ""
echo "  ── Run ──"
echo "  grpc-demo-app              # terminal"
echo "  (or launch from the application menu)"
echo ""
