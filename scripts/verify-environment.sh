#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
EMULATOR="$(tft_resolve_emulator)"
readonly EMULATOR
ADB="$(tft_resolve_adb)"
readonly ADB
readonly AVD_HOME="$(tft_resolve_avd_home)"
readonly AVD_NAME="${TFT_AVD_NAME:-Tft}"
readonly SERIAL="emulator-5572"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

print "Project: $PROJECT_DIR"
print "Host: $(uname -m), $(sw_vers -productVersion)"
print "Emulator: $EMULATOR"
grep -E '^(Pkg.Revision|Pkg.BuildId|Pkg.Desc)=' "${EMULATOR:h}/source.properties"
"$EMULATOR" -accel-check 2>&1
print "AVD home: $AVD_HOME"

if [[ ! -f "$AVD_HOME/$AVD_NAME.ini" ]]; then
    print "Live TFT AVD not found. Set TFT_AVD_HOME to its avd-home directory."
    exit 2
fi

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "TFT emulator is not running. Static environment is valid."
    exit 0
fi

print "Android: $("$ADB" -s "$SERIAL" shell getprop ro.build.version.release | tr -d '\r')"
print "ABI: $("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')"
print "Build type: $("$ADB" -s "$SERIAL" shell getprop ro.build.type | tr -d '\r')"
"$ADB" -s "$SERIAL" shell wm size
"$ADB" -s "$SERIAL" shell wm density
print "TFT PID: $("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" | tr -d '\r')"
"$ADB" -s "$SERIAL" shell cat /proc/meminfo \
    | grep -E '^(MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree):'
