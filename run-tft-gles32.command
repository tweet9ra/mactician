#!/bin/zsh
set -euo pipefail

# zsh enables BG_NICE by default and otherwise adds nice=5 to the emulator
# merely because it is launched in the background for boot orchestration.
# Keep normal host scheduling priority so short input/render bursts are not
# deferred behind unrelated macOS work.
unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ANDROID_SDK_ROOT="$(tft_resolve_android_sdk_root)"
readonly ANDROID_SDK_ROOT
EMULATOR="$(tft_resolve_emulator)"
readonly EMULATOR
ADB="$(tft_resolve_adb)"
readonly ADB

# Existing AVD data is external to the repository.
readonly AVD_HOME="$(tft_resolve_avd_home)"
readonly AVD_NAME="${TFT_AVD_NAME:-Tft}"
readonly SERIAL="emulator-5572"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly ACTIVITY="com.epicgames.unreal.SplashActivity"
readonly ANGLE_FEATURES="exposeNonConformantExtensionsAndVersions:exposeES32ForTesting"
# 1600x900 is the balanced fallback: it gives TFT 56% more source pixels than
# 720p without the 2.25x pixel cost of a full 1920x1080 surface.
readonly DISPLAY_SIZE="1600x900"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

export ANDROID_SDK_ROOT
export ANDROID_AVD_HOME="$AVD_HOME"

if [[ ! -x "$EMULATOR" ]]; then
    print "Android Emulator was not found or is not executable: $EMULATOR"
    exit 1
fi

if [[ ! -f "$AVD_HOME/$AVD_NAME.ini" ]]; then
    print "TFT AVD was not found: $AVD_HOME/$AVD_NAME.ini"
    print "Set TFT_AVD_HOME and TFT_AVD_NAME to select an existing AVD."
    exit 1
fi

if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "A TFT emulator is already running on $SERIAL. Close it first."
    exit 1
fi

"$EMULATOR" "@$AVD_NAME" \
    -id TFT-Tft \
    -port 5572 \
    -gpu host \
    -feature VulkanNativeSwapchain \
    -skin "$DISPLAY_SIZE" \
    -vsync-rate 60 \
    -cores 7 \
    -memory 6144 \
    -no-snapshot \
    -no-metrics \
    -no-boot-anim &
readonly EMULATOR_PID=$!

cleanup() {
    if kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
        wait "$EMULATOR_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

print "Waiting for the TFT emulator to boot…"
until "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
    if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        print "The emulator exited before ADB became available."
        exit 1
    fi
    sleep 1
done

until [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    sleep 1
done

# ANGLE's Vulkan renderer runs on Apple Metal through the emulator's MoltenVK
# backend. It needs both compatibility features to expose its ES 3.2 context
# on this host; the second feature is the current ANGLE testing gate for 3.2.
"$ADB" -s "$SERIAL" shell settings put global angle_gl_driver_selection_pkgs "$PACKAGE"
"$ADB" -s "$SERIAL" shell settings put global angle_gl_driver_selection_values angle
"$ADB" -s "$SERIAL" shell settings put global angle_egl_features "$ANGLE_FEATURES"
"$ADB" -s "$SERIAL" shell setprop debug.angle.feature_overrides_enabled "$ANGLE_FEATURES"
"$ADB" -s "$SERIAL" shell settings put global show_angle_in_use_dialog_box 0

print "TFT graphics: ANGLE ES 3.2 → Vulkan → Metal (Apple GPU)"
print "Display: $DISPLAY_SIZE at 60 Hz; 7 vCPU; 6 GiB RAM"
print "Native Vulkan/Metal window without a software scrcpy video stream"

"$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE"
"$ADB" -s "$SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

print "Opening TFT. Closing the Android Emulator window shuts down the virtual device."
wait "$EMULATOR_PID"
