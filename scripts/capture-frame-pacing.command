#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ADB="$(tft_resolve_adb)"
readonly ADB
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly GAME_ACTIVITY="$PACKAGE/com.epicgames.unreal.GameActivity"
readonly SCENE="${TFT_SCENE:-}"
readonly VARIANT="${TFT_VARIANT:-}"
readonly OUTPUT_ROOT="${TFT_MEASUREMENT_ROOT:-$PROJECT_DIR/runtime/measurements}"
readonly ROUNDS="${TFT_MEASUREMENT_ROUNDS:-5}"
readonly WINDOW_SECONDS="${TFT_MEASUREMENT_WINDOW_SECONDS:-2}"
readonly RENDERER_HINT="${TFT_RENDERER:-}"
readonly GUEST_GL_DRIVER_HINT="${TFT_GUEST_GL_DRIVER:-}"
readonly PROFILE_PATH_OVERRIDE="${TFT_PROFILE_PATH:-}"
readonly EXPECTED_STAGE="${TFT_EXPECTED_STAGE:-}"
readonly EXPECTED_PHASE="${TFT_EXPECTED_PHASE:-}"
readonly SEMANTIC_BEFORE_IMAGE="${TFT_SEMANTIC_BEFORE_IMAGE:-}"
readonly SCREEN_CLASSIFIER="${TFT_SCREEN_CLASSIFIER_BINARY:-$PROJECT_DIR/runtime/tft-screen-classifier}"
readonly SCREEN_CLASSIFIER_SOURCE="$PROJECT_DIR/tools/tft-screen-classifier.swift"
readonly SCREEN_CLASSIFIER_BUILD="$PROJECT_DIR/scripts/build-tft-screen-classifier.command"
readonly JQ="${TFT_JQ:-$(command -v jq 2>/dev/null || true)}"
readonly ORIGINAL_BASE_SHA256="2f4996a620623d0b958383bfe58bdec78fb70cca095099ca2474f3d08c62ff18"
readonly DIRECT_VULKAN_APK_SHA256="3cabacef5ba122467d2eea8fb2874f41530a8d0c1b8cda3f391a58134b936236"
readonly ANGLE_OPENGL_APK_SHA256="f3a257750e1875298a1203c40e9bb98aaf9521b4466f75a53d16fd2d6ea63865"
readonly DIRECT_VULKAN_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-direct-vulkan/Android_Codex.DeviceProfiles.ini"
readonly ANGLE_OPENGL_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.ini"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

validate_label() {
    local label_name="$1"
    local label_value="$2"
    if [[ -z "$label_value" ]] || ! print -r -- "$label_value" | grep -Eq '^[a-z0-9][a-z0-9_-]*$'; then
        print "$label_name is required and must match [a-z0-9][a-z0-9_-]*."
        exit 2
    fi
}

read_host_power_source() {
    pmset -g ps 2>/dev/null \
        | sed -n "1s/^Now drawing from '\(.*\)'$/\1/p"
}

read_host_power_mode() {
    local wanted_source="$1"
    pmset -g custom 2>/dev/null \
        | awk -v wanted="$wanted_source" '
            /^[[:alnum:] ]+Power:$/ {
                current = $0
                sub(/:$/, "", current)
                next
            }
            current == wanted && $1 == "powermode" { print $2; exit }
          '
}

read_host_thermal_state() {
    local thermal_state
    thermal_state="$(
        pmset -g therm 2>/dev/null \
            | tr '\n' ' ' \
            | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
    )"
    [[ -n "$thermal_state" ]] && print -r -- "$thermal_state" || print unavailable
}

validate_label TFT_SCENE "$SCENE"
validate_label TFT_VARIANT "$VARIANT"

if [[ -n "$EXPECTED_STAGE" ]] \
        && ! print -r -- "$EXPECTED_STAGE" | grep -Eq '^[1-9]-(1[0-9]|[1-9])$'; then
    print "TFT_EXPECTED_STAGE must use a value such as 1-2."
    exit 2
fi
case "$EXPECTED_PHASE" in
    ""|combat|planning) ;;
    *)
        print "TFT_EXPECTED_PHASE must be combat or planning."
        exit 2
        ;;
esac

case "$RENDERER_HINT" in
    ""|angle|angle-opengl|direct-vulkan) ;;
    *)
        print "TFT_RENDERER must be angle, angle-opengl, or direct-vulkan."
        exit 2
        ;;
esac
case "$GUEST_GL_DRIVER_HINT" in
    ""|angle|native) ;;
    *)
        print "TFT_GUEST_GL_DRIVER must be angle or native."
        exit 2
        ;;
esac

if [[ -n "$PROFILE_PATH_OVERRIDE" && ! -f "$PROFILE_PATH_OVERRIDE" ]]; then
    print "TFT_PROFILE_PATH does not point to an existing file: $PROFILE_PATH_OVERRIDE"
    exit 2
fi
if [[ -n "$SEMANTIC_BEFORE_IMAGE" \
        && ( "$SEMANTIC_BEFORE_IMAGE" != /* || ! -f "$SEMANTIC_BEFORE_IMAGE" ) ]]; then
    print "TFT_SEMANTIC_BEFORE_IMAGE must point to an existing PNG by absolute path."
    exit 2
fi

if (( ROUNDS < 1 || ROUNDS > 20 )); then
    print "TFT_MEASUREMENT_ROUNDS must be from 1 through 20."
    exit 2
fi
if (( WINDOW_SECONDS < 1 || WINDOW_SECONDS > 10 )); then
    print "TFT_MEASUREMENT_WINDOW_SECONDS must be from 1 through 10."
    exit 2
fi

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The TFT AVD is not connected on $SERIAL."
    exit 1
fi

readonly UTC_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
readonly OUTPUT_DIR="$OUTPUT_ROOT/${UTC_STAMP}__${SCENE}__${VARIANT}"
mkdir -p "$OUTPUT_DIR"

if [[ ! -x "$JQ" ]]; then
    print "jq was not found. Set TFT_JQ or install jq on PATH."
    exit 1
fi
if [[ ! -x "$SCREEN_CLASSIFIER" || "$SCREEN_CLASSIFIER_SOURCE" -nt "$SCREEN_CLASSIFIER" ]]; then
    TFT_SCREEN_CLASSIFIER_BINARY="$SCREEN_CLASSIFIER" \
        "$SCREEN_CLASSIFIER_BUILD" > "$OUTPUT_DIR/classifier-build.txt"
fi
if [[ ! -x "$SCREEN_CLASSIFIER" ]]; then
    print "Could not build the screen classifier: $SCREEN_CLASSIFIER"
    exit 1
fi

capture_activity() {
    local destination="$1"
    "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
        | tr -d '\r' \
        | grep -E 'topResumedActivity|mResumedActivity|mFocusedApp|mCurrentFocus' \
        > "$destination" || true
}

capture_screenshot() {
    local destination="$1"
    "$ADB" -s "$SERIAL" exec-out screencap -p > "$destination"
}

validate_battle_scene() {
    local image="$1"
    local classification="$2"
    local required_phase="${3:-}"
    local state stage phase

    if ! "$SCREEN_CLASSIFIER" "$image" > "$classification" 2> "$classification.stderr"; then
        print "The screen classifier failed for ${image:t}."
        return 1
    fi
    state="$("$JQ" -r '.state // "unknown"' "$classification" 2>/dev/null || print invalid_json)"
    stage="$("$JQ" -r '.stage // ""' "$classification" 2>/dev/null || true)"
    phase="$("$JQ" -r '.phase // ""' "$classification" 2>/dev/null || true)"

    if [[ "$state" != "battle" ]]; then
        print "Screen classifier: expected battle, got $state."
        return 1
    fi
    if [[ -n "$EXPECTED_STAGE" && "$stage" != "$EXPECTED_STAGE" ]]; then
        print "Screen classifier: expected stage $EXPECTED_STAGE, got ${stage:-none}."
        return 1
    fi
    if [[ -n "$required_phase" && "$phase" != "$required_phase" ]]; then
        print "Screen classifier: expected phase $required_phase, got ${phase:-none}."
        return 1
    fi
}

extract_layer() {
    local source_file="$1"
    local match_file="$OUTPUT_DIR/layer-matches.tmp"
    grep -F "SurfaceView[$GAME_ACTIVITY](BLAST)" "$source_file" > "$match_file" || true
    local match_count="$(wc -l < "$match_file" | tr -d ' ')"
    if [[ "$match_count" != "1" ]]; then
        print "Expected one TFT BLAST SurfaceView, found: $match_count."
        return 1
    fi
    sed -E 's/^RequestedLayerState\{(.*) parentId=[^}]*\}$/\1/' "$match_file"
}

capture_activity "$OUTPUT_DIR/activity-before.txt"
if ! grep -F "topResumedActivity=" "$OUTPUT_DIR/activity-before.txt" | grep -Fq "$GAME_ACTIVITY"; then
    print "TFT GameActivity is not in the foreground."
    exit 1
fi

"$ADB" -s "$SERIAL" shell dumpsys SurfaceFlinger --list 2>/dev/null \
    | tr -d '\r' > "$OUTPUT_DIR/layers-before.txt"
readonly LAYER="$(extract_layer "$OUTPUT_DIR/layers-before.txt")"
print -r -- "$LAYER" > "$OUTPUT_DIR/selected-layer.txt"

if [[ -n "$SEMANTIC_BEFORE_IMAGE" ]]; then
    cp "$SEMANTIC_BEFORE_IMAGE" "$OUTPUT_DIR/before.png"
else
    capture_screenshot "$OUTPUT_DIR/before.png"
fi
if ! validate_battle_scene \
        "$OUTPUT_DIR/before.png" "$OUTPUT_DIR/classification-before.json" "$EXPECTED_PHASE"; then
    print "INVALID: the pre-measurement screen failed the semantic battle gate." > "$OUTPUT_DIR/summary.txt"
    print "Invalid measurement: the pre-measurement screen does not match the expected battle. Artifacts: $OUTPUT_DIR"
    exit 3
fi
sleep 1

readonly HOST_POWER_SOURCE_BEFORE="$(read_host_power_source)"
readonly HOST_POWER_MODE_BEFORE="$(read_host_power_mode "$HOST_POWER_SOURCE_BEFORE")"
readonly HOST_THERMAL_STATE_BEFORE="$(read_host_thermal_state)"

print 'round,frame,delta_ms' > "$OUTPUT_DIR/frame-times.csv"
print 'round,start_monotonic_seconds,end_monotonic_seconds' > "$OUTPUT_DIR/round-times.csv"
zmodload zsh/datetime
integer round
typeset raw_file round_start round_end
for (( round = 1; round <= ROUNDS; round++ )); do
    raw_file="$OUTPUT_DIR/latency-round-${round}.txt"
    round_start="$EPOCHREALTIME"
    "$ADB" -s "$SERIAL" shell "dumpsys SurfaceFlinger --latency-clear \"$LAYER\"" >/dev/null
    sleep "$WINDOW_SECONDS"
    "$ADB" -s "$SERIAL" shell "dumpsys SurfaceFlinger --latency \"$LAYER\"" \
        | tr -d '\r' > "$raw_file"
    round_end="$EPOCHREALTIME"
    print "$round,$round_start,$round_end" >> "$OUTPUT_DIR/round-times.csv"
    awk -v round="$round" '
        NR > 1 && $2 + 0 > 0 {
            if (previous > 0) {
                delta = ($2 - previous) / 1000000
                if (delta > 0 && delta < 1000) {
                    frame++
                    printf "%d,%d,%.6f\n", round, frame, delta
                }
            }
            previous = $2
        }
    ' "$raw_file" >> "$OUTPUT_DIR/frame-times.csv"
done

readonly HOST_POWER_SOURCE_AFTER="$(read_host_power_source)"
readonly HOST_POWER_MODE_AFTER="$(read_host_power_mode "$HOST_POWER_SOURCE_AFTER")"
readonly HOST_THERMAL_STATE_AFTER="$(read_host_thermal_state)"
HOST_CONDITIONS_STABLE=no
if [[ -n "$HOST_POWER_SOURCE_BEFORE" \
        && -n "$HOST_POWER_MODE_BEFORE" \
        && "$HOST_THERMAL_STATE_BEFORE" != unavailable \
        && "$HOST_POWER_SOURCE_BEFORE" == "$HOST_POWER_SOURCE_AFTER" \
        && "$HOST_POWER_MODE_BEFORE" == "$HOST_POWER_MODE_AFTER" \
        && "$HOST_THERMAL_STATE_BEFORE" == "$HOST_THERMAL_STATE_AFTER" ]]; then
    HOST_CONDITIONS_STABLE=yes
fi

capture_screenshot "$OUTPUT_DIR/after.png"
if ! validate_battle_scene \
        "$OUTPUT_DIR/after.png" "$OUTPUT_DIR/classification-after.json" "$EXPECTED_PHASE"; then
    print "INVALID: the post-measurement screen failed the semantic battle gate." > "$OUTPUT_DIR/summary.txt"
    print "Invalid measurement: the post-measurement screen does not match the expected battle. Artifacts: $OUTPUT_DIR"
    exit 3
fi
capture_activity "$OUTPUT_DIR/activity-after.txt"
"$ADB" -s "$SERIAL" shell dumpsys SurfaceFlinger --list 2>/dev/null \
    | tr -d '\r' > "$OUTPUT_DIR/layers-after.txt"
readonly LAYER_AFTER="$(extract_layer "$OUTPUT_DIR/layers-after.txt")"

if ! grep -F "topResumedActivity=" "$OUTPUT_DIR/activity-after.txt" | grep -Fq "$GAME_ACTIVITY" \
        || [[ "$LAYER_AFTER" != "$LAYER" ]]; then
    print "INVALID: the activity or SurfaceView changed during measurement." > "$OUTPUT_DIR/summary.txt"
    print "Invalid measurement: the activity or SurfaceView changed. Artifacts: $OUTPUT_DIR"
    exit 3
fi

awk -F, 'NR > 1 { print $3 }' "$OUTPUT_DIR/frame-times.csv" > "$OUTPUT_DIR/frame-times.txt"
sort -n "$OUTPUT_DIR/frame-times.txt" > "$OUTPUT_DIR/frame-times-sorted.txt"
readonly COUNT="$(wc -l < "$OUTPUT_DIR/frame-times.txt" | tr -d ' ')"
if (( COUNT < 10 )); then
    print "INVALID: not enough frames: $COUNT" > "$OUTPUT_DIR/summary.txt"
    print "Not enough frames: $COUNT. Artifacts: $OUTPUT_DIR"
    exit 3
fi

readonly P50_INDEX=$(( (COUNT - 1) * 50 / 100 + 1 ))
readonly P95_INDEX=$(( (COUNT - 1) * 95 / 100 + 1 ))
readonly P99_INDEX=$(( (COUNT - 1) * 99 / 100 + 1 ))
readonly P50="$(sed -n "${P50_INDEX}p" "$OUTPUT_DIR/frame-times-sorted.txt")"
readonly P95="$(sed -n "${P95_INDEX}p" "$OUTPUT_DIR/frame-times-sorted.txt")"
readonly P99="$(sed -n "${P99_INDEX}p" "$OUTPUT_DIR/frame-times-sorted.txt")"
readonly MAX="$(tail -n 1 "$OUTPUT_DIR/frame-times-sorted.txt")"

read -r MEAN OVER16 OVER20 OVER33 OVER40 OVER50 OVER60 OVER100 <<< "$(
    awk '
        {
            sum += $1
            if ($1 > 16.67) over16++
            if ($1 > 20) over20++
            if ($1 > 33.33) over33++
            if ($1 > 40) over40++
            if ($1 > 50) over50++
            if ($1 > 60) over60++
            if ($1 > 100) over100++
        }
        END { printf "%.2f %d %d %d %d %d %d %d", sum / NR, over16, over20, over33, over40, over50, over60, over100 }
    ' "$OUTPUT_DIR/frame-times.txt"
)"
readonly FPS="$(awk -v mean="$MEAN" 'BEGIN { printf "%.1f", 1000 / mean }')"

readonly BASE_PATH="$("$ADB" -s "$SERIAL" shell pm path "$PACKAGE" 2>/dev/null \
    | tr -d '\r' \
    | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p' \
    | head -n 1)"
readonly VERSION_NAME="$("$ADB" -s "$SERIAL" shell dumpsys package "$PACKAGE" 2>/dev/null \
    | tr -d '\r' \
    | sed -n 's/^[[:space:]]*versionName=//p' \
    | head -n 1)"
readonly ACTIVE_APK_SHA="$("$ADB" -s "$SERIAL" shell sha256sum "$BASE_PATH" 2>/dev/null \
    | awk '{ print $1 }')"
readonly MOUNT_INFO="$("$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo 2>/dev/null \
    | grep -F " $BASE_PATH " || true)"
readonly GAME_PID_RAW="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')"
readonly GAME_PID="${GAME_PID_RAW%% *}"
if [[ -z "$GAME_PID" ]]; then
    print "INVALID: the TFT PID was not found after measurement." > "$OUTPUT_DIR/summary.txt"
    print "Invalid measurement: the TFT PID was not found. Artifacts: $OUTPUT_DIR"
    exit 3
fi
"$ADB" -s "$SERIAL" shell dumpsys meminfo "$PACKAGE" 2>/dev/null \
    | tr -d '\r' > "$OUTPUT_DIR/meminfo.txt" || true
TOTAL_PSS_KB="$(
    sed -n 's/.*TOTAL PSS:[[:space:]]*\([0-9,]*\).*/\1/p' "$OUTPUT_DIR/meminfo.txt" \
        | head -n 1 | tr -d ','
)"
TOTAL_RSS_KB="$(
    sed -n 's/.*TOTAL RSS:[[:space:]]*\([0-9,]*\).*/\1/p' "$OUTPUT_DIR/meminfo.txt" \
        | head -n 1 | tr -d ','
)"
[[ "$TOTAL_PSS_KB" == <-> ]] || TOTAL_PSS_KB=0
[[ "$TOTAL_RSS_KB" == <-> ]] || TOTAL_RSS_KB=0
readonly GAME_MAPS="$("$ADB" -s "$SERIAL" shell cat "/proc/$GAME_PID/maps" 2>/dev/null \
    | tr -d '\r' || true)"
readonly SUBMIT_ENV_MATCHES="$(
    "$ADB" -s "$SERIAL" shell cat "/proc/$GAME_PID/environ" 2>/dev/null \
        | tr '\0' '\n' \
        | grep -E '^MESA_VK_ENABLE_SUBMIT_THREAD=' || true
)"
SUBMIT_ENV_PRESENT=no
SUBMIT_ENV_ONE_PRESENT=no
[[ -n "$SUBMIT_ENV_MATCHES" ]] && SUBMIT_ENV_PRESENT=yes
[[ "$SUBMIT_ENV_MATCHES" == "MESA_VK_ENABLE_SUBMIT_THREAD=1" ]] && SUBMIT_ENV_ONE_PRESENT=yes

ACTIVE_GUEST_GL_DRIVER="unknown"
GUEST_GL_DRIVER_SOURCE="process_maps"
GUEST_ANGLE_MAPPED=no
GFXSTREAM_GLES_ENCODER_MAPPED=no
GUEST_VULKAN_RANCHU_MAPPED=no
[[ "$GAME_MAPS" == *libGLESv2_angle.so* ]] && GUEST_ANGLE_MAPPED=yes
[[ "$GAME_MAPS" == *libGLESv2_enc.so* ]] && GFXSTREAM_GLES_ENCODER_MAPPED=yes
[[ "$GAME_MAPS" == *vulkan.ranchu.so* ]] && GUEST_VULKAN_RANCHU_MAPPED=yes
if [[ "$GUEST_ANGLE_MAPPED" == "yes" ]]; then
    ACTIVE_GUEST_GL_DRIVER="angle"
elif [[ "$GAME_MAPS" == *libEGL_emulation.so* \
        && "$GAME_MAPS" == *libGLESv2_emulation.so* \
        && "$GFXSTREAM_GLES_ENCODER_MAPPED" == "yes" ]]; then
    ACTIVE_GUEST_GL_DRIVER="native"
elif [[ -n "$GUEST_GL_DRIVER_HINT" ]]; then
    ACTIVE_GUEST_GL_DRIVER="$GUEST_GL_DRIVER_HINT"
    GUEST_GL_DRIVER_SOURCE="TFT_GUEST_GL_DRIVER_hint"
fi

ACTIVE_RENDERER="unknown"
RENDERER_SOURCE="unknown"
case "$ACTIVE_APK_SHA" in
    "$DIRECT_VULKAN_APK_SHA256")
        ACTIVE_RENDERER="direct-vulkan"
        RENDERER_SOURCE="active_apk_sha256"
        ;;
    "$ANGLE_OPENGL_APK_SHA256")
        ACTIVE_RENDERER="angle-opengl"
        RENDERER_SOURCE="active_apk_sha256"
        ;;
    "$ORIGINAL_BASE_SHA256")
        ACTIVE_RENDERER="angle"
        RENDERER_SOURCE="active_apk_sha256"
        ;;
esac

if [[ "$ACTIVE_RENDERER" == "unknown" && -n "$RENDERER_HINT" ]]; then
    ACTIVE_RENDERER="$RENDERER_HINT"
    RENDERER_SOURCE="TFT_RENDERER_hint"
fi

if [[ "$ACTIVE_RENDERER" == "unknown" ]]; then
    case "$VARIANT" in
        direct-vulkan*|direct_vulkan*|direct-vk*|direct_vk*|vulkan*)
            ACTIVE_RENDERER="direct-vulkan"
            RENDERER_SOURCE="TFT_VARIANT_fallback"
            ;;
        angle-opengl*|angle_opengl*|opengl*)
            ACTIVE_RENDERER="angle-opengl"
            RENDERER_SOURCE="TFT_VARIANT_fallback"
            ;;
        angle|angle-*|angle_*|stock*|baseline*)
            ACTIVE_RENDERER="angle"
            RENDERER_SOURCE="TFT_VARIANT_fallback"
            ;;
    esac
fi

PROFILE_PATH=""
PROFILE_SOURCE="none"
if [[ -n "$PROFILE_PATH_OVERRIDE" ]]; then
    PROFILE_PATH="${PROFILE_PATH_OVERRIDE:A}"
    PROFILE_SOURCE="TFT_PROFILE_PATH"
else
    case "$ACTIVE_RENDERER" in
        direct-vulkan)
            PROFILE_PATH="$DIRECT_VULKAN_PROFILE"
            PROFILE_SOURCE="active_renderer"
            ;;
        angle-opengl)
            PROFILE_PATH="$ANGLE_OPENGL_PROFILE"
            PROFILE_SOURCE="active_renderer"
            ;;
    esac
fi

if [[ -n "$PROFILE_PATH" && -f "$PROFILE_PATH" ]]; then
    PROFILE_SHA="$(shasum -a 256 "$PROFILE_PATH" | awk '{ print $1 }')"
elif [[ -n "$PROFILE_PATH" ]]; then
    PROFILE_SHA="missing"
else
    PROFILE_SHA="none"
fi

readonly CLASSIFIED_STAGE_BEFORE="$("$JQ" -r '.stage // ""' "$OUTPUT_DIR/classification-before.json")"
readonly CLASSIFIED_STAGE_AFTER="$("$JQ" -r '.stage // ""' "$OUTPUT_DIR/classification-after.json")"
readonly CLASSIFIED_PHASE_BEFORE="$("$JQ" -r '.phase // ""' "$OUTPUT_DIR/classification-before.json")"
readonly CLASSIFIED_PHASE_AFTER="$("$JQ" -r '.phase // ""' "$OUTPUT_DIR/classification-after.json")"
EMULATOR_BIN="$(tft_resolve_emulator)"
EMULATOR_RUNTIME_ROOT="${EMULATOR_BIN:A:h}"
EMULATOR_QEMU="$EMULATOR_RUNTIME_ROOT/qemu/darwin-aarch64/qemu-system-aarch64"
EMULATOR_GFXSTREAM="$EMULATOR_RUNTIME_ROOT/lib64/libgfxstream_backend.dylib"
EMULATOR_QEMU_SHA="missing"
EMULATOR_GFXSTREAM_SHA="missing"
[[ -f "$EMULATOR_QEMU" ]] \
    && EMULATOR_QEMU_SHA="$(shasum -a 256 "$EMULATOR_QEMU" | awk '{ print $1 }')"
[[ -f "$EMULATOR_GFXSTREAM" ]] \
    && EMULATOR_GFXSTREAM_SHA="$(shasum -a 256 "$EMULATOR_GFXSTREAM" | awk '{ print $1 }')"

{
    print "utc=$UTC_STAMP"
    print "scene=$SCENE"
    print "variant=$VARIANT"
    print "serial=$SERIAL"
    print "version_name=$VERSION_NAME"
    print "renderer=$ACTIVE_RENDERER"
    print "renderer_source=$RENDERER_SOURCE"
    print "renderer_hint=${RENDERER_HINT:-none}"
    print "guest_gl_driver=$ACTIVE_GUEST_GL_DRIVER"
    print "guest_gl_driver_source=$GUEST_GL_DRIVER_SOURCE"
    print "guest_gl_driver_hint=${GUEST_GL_DRIVER_HINT:-none}"
    print "guest_gl_driver_setting=$("$ADB" -s "$SERIAL" shell settings get global angle_gl_driver_selection_values 2>/dev/null | tr -d '\r')"
    print "guest_angle_mapped=$GUEST_ANGLE_MAPPED"
    print "gfxstream_gles_encoder_mapped=$GFXSTREAM_GLES_ENCODER_MAPPED"
    print "guest_vulkan_ranchu_mapped=$GUEST_VULKAN_RANCHU_MAPPED"
    print "base_path=$BASE_PATH"
    print "active_apk_sha256=$ACTIVE_APK_SHA"
    print "device_profile_path=${PROFILE_PATH:-none}"
    print "device_profile_source=$PROFILE_SOURCE"
    print "device_profile_sha256=$PROFILE_SHA"
    print "rounds=$ROUNDS"
    print "window_seconds=$WINDOW_SECONDS"
    print "expected_stage=${EXPECTED_STAGE:-none}"
    print "expected_phase=${EXPECTED_PHASE:-none}"
    print "submit_thread_env_present=$SUBMIT_ENV_PRESENT"
    print "submit_thread_env_one_present=$SUBMIT_ENV_ONE_PRESENT"
    print "display=$("$ADB" -s "$SERIAL" shell wm size 2>/dev/null | tr -d '\r')"
    print "density=$("$ADB" -s "$SERIAL" shell wm density 2>/dev/null | tr -d '\r')"
    print "angle_egl_features=$("$ADB" -s "$SERIAL" shell settings get global angle_egl_features 2>/dev/null | tr -d '\r')"
    print "angle_features_enabled=$("$ADB" -s "$SERIAL" shell getprop debug.angle.feature_overrides_enabled 2>/dev/null | tr -d '\r')"
    print "angle_features_disabled=$("$ADB" -s "$SERIAL" shell getprop debug.angle.feature_overrides_disabled 2>/dev/null | tr -d '\r')"
    print "mount_info=$MOUNT_INFO"
    print "host_conditions_stable=$HOST_CONDITIONS_STABLE"
    print "host_power_source_before=${HOST_POWER_SOURCE_BEFORE:-unknown}"
    print "host_power_source_after=${HOST_POWER_SOURCE_AFTER:-unknown}"
    print "host_power_mode_before=${HOST_POWER_MODE_BEFORE:-unknown}"
    print "host_power_mode_after=${HOST_POWER_MODE_AFTER:-unknown}"
    print "host_thermal_state_before=$HOST_THERMAL_STATE_BEFORE"
    print "host_thermal_state_after=$HOST_THERMAL_STATE_AFTER"
    print "game_total_pss_kb=$TOTAL_PSS_KB"
    print "game_total_rss_kb=$TOTAL_RSS_KB"
    print "emulator_binary=$EMULATOR_BIN"
    print "emulator_qemu_sha256=$EMULATOR_QEMU_SHA"
    print "emulator_gfxstream_sha256=$EMULATOR_GFXSTREAM_SHA"
} > "$OUTPUT_DIR/metadata.txt"

"$JQ" -n \
    --arg utc "$UTC_STAMP" \
    --arg scene "$SCENE" \
    --arg variant "$VARIANT" \
    --arg serial "$SERIAL" \
    --arg version_name "$VERSION_NAME" \
    --arg renderer "$ACTIVE_RENDERER" \
    --arg guest_gl_driver "$ACTIVE_GUEST_GL_DRIVER" \
    --arg active_apk_sha256 "$ACTIVE_APK_SHA" \
    --arg profile_path "${PROFILE_PATH:-none}" \
    --arg profile_sha256 "$PROFILE_SHA" \
    --arg expected_stage "${EXPECTED_STAGE:-none}" \
    --arg expected_phase "${EXPECTED_PHASE:-none}" \
    --arg stage_before "${CLASSIFIED_STAGE_BEFORE:-none}" \
    --arg stage_after "${CLASSIFIED_STAGE_AFTER:-none}" \
    --arg phase_before "${CLASSIFIED_PHASE_BEFORE:-none}" \
    --arg phase_after "${CLASSIFIED_PHASE_AFTER:-none}" \
    --arg display "$("$ADB" -s "$SERIAL" shell wm size 2>/dev/null | tr -d '\r')" \
    --arg density "$("$ADB" -s "$SERIAL" shell wm density 2>/dev/null | tr -d '\r')" \
    --arg host_conditions_stable "$HOST_CONDITIONS_STABLE" \
    --arg power_source_before "${HOST_POWER_SOURCE_BEFORE:-unknown}" \
    --arg power_source_after "${HOST_POWER_SOURCE_AFTER:-unknown}" \
    --arg power_mode_before "${HOST_POWER_MODE_BEFORE:-unknown}" \
    --arg power_mode_after "${HOST_POWER_MODE_AFTER:-unknown}" \
    --arg thermal_state_before "$HOST_THERMAL_STATE_BEFORE" \
    --arg thermal_state_after "$HOST_THERMAL_STATE_AFTER" \
    --arg emulator_binary "$EMULATOR_BIN" \
    --arg emulator_qemu_sha256 "$EMULATOR_QEMU_SHA" \
    --arg emulator_gfxstream_sha256 "$EMULATOR_GFXSTREAM_SHA" \
    --argjson samples "$COUNT" \
    --argjson rounds "$ROUNDS" \
    --argjson window_seconds "$WINDOW_SECONDS" \
    --argjson fps "$FPS" \
    --argjson mean_ms "$MEAN" \
    --argjson p50_ms "$P50" \
    --argjson p95_ms "$P95" \
    --argjson p99_ms "$P99" \
    --argjson max_ms "$MAX" \
    --argjson over_16_67_ms "$OVER16" \
    --argjson over_20_ms "$OVER20" \
    --argjson over_33_33_ms "$OVER33" \
    --argjson over_40_ms "$OVER40" \
    --argjson over_50_ms "$OVER50" \
    --argjson over_60_ms "$OVER60" \
    --argjson over_100_ms "$OVER100" \
    --argjson total_pss_kb "$TOTAL_PSS_KB" \
    --argjson total_rss_kb "$TOTAL_RSS_KB" \
    --arg submit_env_present "$SUBMIT_ENV_PRESENT" \
    --arg submit_env_one_present "$SUBMIT_ENV_ONE_PRESENT" \
    '{
        schema_version: 1,
        utc: $utc,
        scene: $scene,
        variant: $variant,
        device: {serial: $serial, version_name: $version_name, display: $display, density: $density},
        semantic_gate: {
            expected_stage: $expected_stage,
            expected_phase: $expected_phase,
            stage_before: $stage_before,
            stage_after: $stage_after,
            phase_before: $phase_before,
            phase_after: $phase_after,
            valid: (($stage_before == $stage_after) and ($phase_before == $phase_after))
        },
        graphics: {
            renderer: $renderer,
            guest_gl_driver: $guest_gl_driver,
            active_apk_sha256: $active_apk_sha256,
            profile_path: $profile_path,
            profile_sha256: $profile_sha256,
            submit_env_present: ($submit_env_present == "yes"),
            submit_env_one_present: ($submit_env_one_present == "yes"),
            emulator_binary: $emulator_binary,
            emulator_qemu_sha256: $emulator_qemu_sha256,
            emulator_gfxstream_sha256: $emulator_gfxstream_sha256
        },
        host: {
            stable: ($host_conditions_stable == "yes"),
            power_source: $power_source_before,
            power_mode: $power_mode_before,
            thermal_state: $thermal_state_before,
            before: {power_source: $power_source_before, power_mode: $power_mode_before,
                thermal_state: $thermal_state_before},
            after: {power_source: $power_source_after, power_mode: $power_mode_after,
                thermal_state: $thermal_state_after}
        },
        memory: {game_total_pss_kb: $total_pss_kb, game_total_rss_kb: $total_rss_kb},
        pacing: {
            samples: $samples,
            rounds: $rounds,
            window_seconds: $window_seconds,
            fps: $fps,
            mean_ms: $mean_ms,
            p50_ms: $p50_ms,
            p95_ms: $p95_ms,
            p99_ms: $p99_ms,
            max_ms: $max_ms,
            frames_over_ms: {
                "16.67": $over_16_67_ms,
                "20": $over_20_ms,
                "33.33": $over_33_33_ms,
                "40": $over_40_ms,
                "50": $over_50_ms,
                "60": $over_60_ms,
                "100": $over_100_ms
            }
        },
        rollback: {verified: null, reason: "pending_outer_launcher_cleanup"}
    }' > "$OUTPUT_DIR/summary.json.next"
mv -f "$OUTPUT_DIR/summary.json.next" "$OUTPUT_DIR/summary.json"

{
    print "TFT frame pacing — $SCENE / $VARIANT — renderer=$ACTIVE_RENDERER guest_gl=$ACTIVE_GUEST_GL_DRIVER"
    print "samples=$COUNT fps≈$FPS mean=${MEAN}ms p50=${P50}ms p95=${P95}ms p99=${P99}ms max=${MAX}ms"
    print ">16.67ms=$OVER16 >20ms=$OVER20 >33.33ms=$OVER33 >40ms=$OVER40 >50ms=$OVER50 >60ms=$OVER60 >100ms=$OVER100"
} > "$OUTPUT_DIR/summary.txt"

sed -n '1,3p' "$OUTPUT_DIR/summary.txt"
print "Artifacts: $OUTPUT_DIR"
