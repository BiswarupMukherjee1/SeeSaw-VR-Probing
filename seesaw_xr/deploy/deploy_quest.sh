#!/usr/bin/env bash
# Build the APK and install it on the Quest 3 over USB (adb)..
#   ./deploy_quest.sh 192.168.1.50            # build + install + launch
#   SKIP_BUILD=1 ./deploy_quest.sh 192.168.1.50
# Set GODOT=/path/to/godot if it is not on PATH. Needs Android SDK (ANDROID_HOME), JDK 17, Godot 4.7.2 export templates.
set -euo pipefail
SERVER_IP="${1:?usage: deploy_quest.sh <server-ip> [port]}"
PORT="${2:-8765}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/godot"
APK="$ROOT/build/seesaw_xr.apk"
PACKAGE="com.seesaw.xr"
GODOT="${GODOT:-godot}"
ADB="${ANDROID_HOME:?set ANDROID_HOME}/platform-tools/adb"

mkdir -p "$ROOT/build"
printf '{\n\t"host": "%s",\n\t"port": %s\n}\n' "$SERVER_IP" "$PORT" > "$PROJ/config/server.json"
echo "server.json -> $SERVER_IP:$PORT"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  if [ ! -f "$PROJ/android/build/build.gradle" ]; then
    ZIP="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable/android_source.zip"
    [ -f "$ZIP" ] || { echo "Export templates 4.7.2.stable missing"; exit 1; }
    mkdir -p "$PROJ/android/build"
    unzip -oq "$ZIP" -d "$PROJ/android/build"
    printf '4.7.2.stable' > "$PROJ/android/.build_version"
  fi
  "$GODOT" --headless --path "$PROJ" --import
  "$GODOT" --headless --path "$PROJ" --export-debug "MetaQuest" "$APK"
fi
[ -f "$APK" ] || { echo "No APK at $APK"; exit 1; }

"$ADB" devices | tail -n +2 | grep -q 'device$' || { echo "No headset: plug in the Quest and accept USB debugging."; exit 1; }
"$ADB" install -r "$APK"
"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched $PACKAGE. Server for the headset: http://$SERVER_IP:$PORT"
