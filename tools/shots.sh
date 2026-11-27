#!/usr/bin/env bash
# Takes docs/screenshots/*.png under Xvfb (software GL, Compatibility renderer). Needs ~/opt/xvfb or Xvfb on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/opt/xvfb/usr/bin:$PATH"
D=:97
if ! pgrep -f "Xvfb $D" >/dev/null; then (Xvfb $D -screen 0 720x1280x24 >/dev/null 2>&1 &); sleep 2; fi
mkdir -p docs/screenshots
SKYFLING_SAVE=user://shots.json DISPLAY=$D timeout 120 godot --rendering-method gl_compatibility --display-driver x11 --resolution 720x1280 --path . -s res://tools/shots.gd
ls -la docs/screenshots
