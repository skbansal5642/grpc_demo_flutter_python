#!/bin/bash
# Activates the local venv and starts the gRPC server.
# This is what DemoClient spawns via dart:io Process.
cd "$(dirname "$0")"
source venv/bin/activate
exec python server.py
