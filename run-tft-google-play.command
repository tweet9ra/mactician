#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"

readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
SDK_ROOT="$(tft_resolve_android_sdk_root)"
readonly SDK_ROOT
EMULATOR="$(tft_resolve_emulator)"
readonly EMULATOR
ADB="$(tft_resolve_adb)"
readonly ADB
readonly AVD_HOME="${TFT_ROOT_AVD_HOME:-$(tft_resolve_avd_home)}"
readonly AVD_NAME="${TFT_AVD_NAME:-TftPlay}"
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly EMULATOR_PORT="${TFT_EMULATOR_PORT:-${SERIAL#emulator-}}"
readonly BOOT_TIMEOUT_SECONDS="${TFT_BOOT_TIMEOUT_SECONDS:-180}"
readonly DISPLAY_SIZE="${TFT_DISPLAY_SIZE:-1920x1080}"
readonly DISPLAY_DENSITY="${TFT_DISPLAY_DENSITY:-320}"
readonly CPU_CORES="${TFT_CPU_CORES:-6}"
readonly MEMORY_MB="${TFT_MEMORY_MB:-6144}"
readonly GAME_LANGUAGE="${TFT_GAME_LANGUAGE:-en-US}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttacticsvn}"
readonly FALLBACK_PACKAGE="${TFT_FALLBACK_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly OPENGL_ES_VERSION=196610
readonly EMULATOR_GRAPHICS_FEATURES='GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts'
readonly ANGLE_FEATURES='exposeNonConformantExtensionsAndVersions:exposeES32ForTesting'
readonly ANGLE_DISABLED_FEATURES="${TFT_ANGLE_DISABLED_FEATURES:-}"
readonly PACKAGED_EMULATOR_APP="$PROJECT_DIR/Mactician Game Host.app"

case "$PACKAGE" in
    com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn) ;;
    *) print -u2 "Unsupported preferred TFT package: $PACKAGE"; exit 2 ;;
esac
case "$FALLBACK_PACKAGE" in
    com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn) ;;
    *) print -u2 "Unsupported fallback TFT package: $FALLBACK_PACKAGE"; exit 2 ;;
esac
if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print -u2 "TFT_ADB_SERVER_PORT must be a TCP port from 1024 to 65534."
    exit 2
fi
if [[ "$EMULATOR_PORT" != <-> || "$SERIAL" != "emulator-$EMULATOR_PORT" ]]; then
    print -u2 "TFT_SERIAL/TFT_EMULATOR_PORT must be a matching emulator-PORT and PORT pair."
    exit 2
fi
if [[ ! -x "$EMULATOR" || ! -x "$ADB" ]]; then
    print -u2 "The Android emulator runtime is incomplete."
    exit 1
fi
if [[ ! -f "$AVD_HOME/$AVD_NAME.ini" ]]; then
    print -u2 "The Google Play AVD was not found: $AVD_HOME/$AVD_NAME.ini"
    exit 1
fi

unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_AVD_HOME="$AVD_HOME"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ADB_MDNS_AUTO_CONNECT=""
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print -u2 "$AVD_NAME is already running on $SERIAL."
    exit 1
fi

typeset -a emulator_arguments
emulator_arguments=(
    "@$AVD_NAME"
    -id "TFT-$AVD_NAME"
    -port "$EMULATOR_PORT"
    -gpu host
    -feature "$EMULATOR_GRAPHICS_FEATURES"
    -append-userspace-opt "androidboot.opengles.version=$OPENGL_ES_VERSION"
    -append-userspace-opt androidboot.mactician.graphics_profile=osft
    -skin "$DISPLAY_SIZE"
    -vsync-rate 60
    -dns-server 1.1.1.1,8.8.8.8
    -cores "$CPU_CORES"
    -memory "$MEMORY_MB"
    -no-snapshot
    -no-metrics
    -no-boot-anim
    -crash-report-mode disabled
)

if [[ -x "$PACKAGED_EMULATOR_APP/Contents/MacOS/MacticianGameHost" ]]; then
    /usr/bin/open -n -W \
        --env "ANDROID_SDK_ROOT=$SDK_ROOT" \
        --env "ANDROID_AVD_HOME=$AVD_HOME" \
        --env "ANDROID_ADB_SERVER_PORT=$ADB_SERVER_PORT" \
        --env "ADB_MDNS_AUTO_CONNECT=" \
        "$PACKAGED_EMULATOR_APP" --args "${emulator_arguments[@]}" &
else
    "$EMULATOR" "${emulator_arguments[@]}" &
fi
readonly EMULATOR_PID=$!

stop_emulator() {
    if kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
        wait "$EMULATOR_PID" >/dev/null 2>&1 || true
    fi
}
trap stop_emulator INT TERM HUP

typeset -i waited=0
until "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1 \
        && [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        print -u2 "The emulator exited before Android finished booting."
        wait "$EMULATOR_PID" || true
        exit 1
    fi
    if (( waited >= BOOT_TIMEOUT_SECONDS )); then
        print -u2 "Android did not finish booting within ${BOOT_TIMEOUT_SECONDS} seconds."
        stop_emulator
        exit 1
    fi
    sleep 1
    (( waited += 1 ))
done

readonly REPORTED_OPENGL_ES_VERSION="$(
    "$ADB" -s "$SERIAL" shell getprop ro.opengles.version 2>/dev/null | tr -d '\r'
)"
readonly REPORTED_OPENGL_ES_FEATURES="$(
    "$ADB" -s "$SERIAL" shell pm list features 2>/dev/null | tr -d '\r'
)"
if [[ "$REPORTED_OPENGL_ES_VERSION" != "$OPENGL_ES_VERSION" ]] \
        || [[ "$REPORTED_OPENGL_ES_FEATURES" != *'feature:reqGlEsVersion=0x30002'* ]]; then
    print -u2 "Android did not expose TFT's required OpenGL ES 3.2 capability."
    print -u2 "Reported OpenGL ES version: ${REPORTED_OPENGL_ES_VERSION:-unknown}."
    stop_emulator
    exit 1
fi

"$ADB" -s "$SERIAL" shell wm size "$DISPLAY_SIZE" >/dev/null
"$ADB" -s "$SERIAL" shell wm density "$DISPLAY_DENSITY" >/dev/null

typeset angle_packages="$PACKAGE"
typeset angle_values="angle"
if [[ "$FALLBACK_PACKAGE" != "$PACKAGE" ]]; then
    angle_packages+=",$FALLBACK_PACKAGE"
    angle_values+=",angle"
fi
"$ADB" -s "$SERIAL" shell settings put global \
    angle_gl_driver_selection_pkgs "$angle_packages" >/dev/null
"$ADB" -s "$SERIAL" shell settings put global \
    angle_gl_driver_selection_values "$angle_values" >/dev/null
"$ADB" -s "$SERIAL" shell settings put global \
    angle_egl_features "$ANGLE_FEATURES" >/dev/null
"$ADB" -s "$SERIAL" shell setprop \
    debug.angle.feature_overrides_enabled "$ANGLE_FEATURES"
if [[ -n "$ANGLE_DISABLED_FEATURES" ]]; then
    "$ADB" -s "$SERIAL" shell setprop \
        debug.angle.feature_overrides_disabled "$ANGLE_DISABLED_FEATURES"
else
    "$ADB" -s "$SERIAL" shell "setprop debug.angle.feature_overrides_disabled ''"
fi
"$ADB" -s "$SERIAL" shell settings put global show_angle_in_use_dialog_box 0 >/dev/null

typeset launch_package=""
typeset candidate
typeset candidate_paths
for candidate in "$PACKAGE" "$FALLBACK_PACKAGE"; do
    "$ADB" -s "$SERIAL" shell cmd locale set-app-locales \
        "$candidate" "$GAME_LANGUAGE" >/dev/null 2>&1 || true
    if [[ -z "$launch_package" ]]; then
        candidate_paths="$("$ADB" -s "$SERIAL" shell pm path "$candidate" 2>/dev/null | tr -d '\r' || true)"
        if [[ "$candidate_paths" == package:* ]]; then
            launch_package="$candidate"
        fi
    fi
done

if [[ -n "$launch_package" ]]; then
    "$ADB" -s "$SERIAL" shell am start -n \
        "$launch_package/com.epicgames.unreal.SplashActivity" >/dev/null
    print "Started $launch_package from the persistent Google Play device."
else
    "$ADB" -s "$SERIAL" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
    print "Android is ready. Install TFT from Google Play; the device will remain open."
fi

wait "$EMULATOR_PID"
