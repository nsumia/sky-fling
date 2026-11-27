#!/usr/bin/env bash
# Builds build/SkyFling.apk (arm64-v8a, minSdk 24, debug-keystore signed, installable).
# Needs: Godot 4.7.2 + matching export templates, JDK 17, Android SDK (build-tools 34, platform 34).
# Override the paths below with environment variables if yours differ.
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$(ls -d "$HOME"/opt/amazon-corretto-17* | head -1)}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/opt/android-sdk}"
KS="${KEYSTORE:-$HOME/.android/debug.keystore}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${KEYSTORE_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${KEYSTORE_PASS:-android}"
mkdir -p build
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "Android" build/SkyFling.apk
rm -f build/SkyFling.apk.idsig
ls -la build/SkyFling.apk
