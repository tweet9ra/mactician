#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"

readonly LABEL="${1:-}"
readonly ROUNDS="${2:-8}"
readonly FRAMES="${3:-120}"
readonly DRAWS_PER_FRAME="${4:-256}"
readonly WARMUP_ROUNDS="${5:-$(( ROUNDS > 8 ? 7 : 3 ))}"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly EXPECTED_GRAPHICS_PROFILE="${TFT_GLES_DRAW_EXPECTED_GRAPHICS_PROFILE:-}"
readonly EXPECTED_ANGLE_ENABLED="${TFT_GLES_DRAW_EXPECTED_ANGLE_ENABLED:-}"
readonly EXPECTED_ANGLE_DISABLED="${TFT_GLES_DRAW_EXPECTED_ANGLE_DISABLED:-}"
readonly PROBE="${TFT_GLES_DRAW_PROBE:-$PROJECT_DIR/runtime/mactician-gles-draw-stress.apk}"
readonly MEASUREMENT_ROOT="${TFT_GLES_DRAW_ROOT:-$PROJECT_DIR/runtime/measurements/android-gles-draw-stress}"
readonly GAME_PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly PROBE_PACKAGE="dev.sergeinaumov.mactician.glesdraw"
readonly PROBE_ACTIVITY="$PROBE_PACKAGE/.DrawStressActivity"
readonly ADB="$(tft_resolve_adb)"
readonly JQ="${TFT_JQ:-$(command -v jq 2>/dev/null || true)}"

if [[ -z "$LABEL" || ! "$LABEL" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' ]]; then
    print -u2 "Usage: ${0:t} <profile-label> [rounds frames draws-per-frame warmup-rounds]"
    exit 2
fi
for numeric_name numeric_value minimum maximum in \
        rounds "$ROUNDS" 2 30 \
        frames "$FRAMES" 1 2000 \
        draws-per-frame "$DRAWS_PER_FRAME" 1 2048 \
        warmup-rounds "$WARMUP_ROUNDS" 1 29; do
    if [[ "$numeric_value" != <-> ]] \
            || (( numeric_value < minimum || numeric_value > maximum )); then
        print -u2 "$numeric_name must be an integer from $minimum through $maximum."
        exit 2
    fi
done
if (( WARMUP_ROUNDS >= ROUNDS )); then
    print -u2 "warmup-rounds must be less than rounds."
    exit 2
fi
if [[ ! "$ADB_SERVER_PORT" =~ '^[0-9]+$' ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print -u2 "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
if [[ -z "$JQ" || ! -x "$JQ" ]]; then
    print -u2 "jq is required to validate and summarize GLES draw-stress evidence."
    exit 1
fi
if [[ ! -f "$PROBE" ]]; then
    print -u2 "The Android GLES draw-stress APK is unavailable: $PROBE"
    exit 1
fi
if [[ ! "$EXPECTED_GRAPHICS_PROFILE" =~ '^[a-z0-9][a-z0-9-]*$' ]]; then
    print -u2 "TFT_GLES_DRAW_EXPECTED_GRAPHICS_PROFILE is required."
    exit 2
fi
for feature_expectation in "$EXPECTED_ANGLE_ENABLED" "$EXPECTED_ANGLE_DISABLED"; do
    if [[ -n "$feature_expectation" \
            && ! "$feature_expectation" =~ '^([A-Za-z0-9_]+[*]?)(:[A-Za-z0-9_]+[*]?)*$' ]]; then
        print -u2 "Expected ANGLE features must be a feature or colon-separated list."
        exit 2
    fi
done

unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null
if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print -u2 "The GLES draw-stress probe requires an already running AVD on $SERIAL."
    exit 1
fi

readonly ACTIVE_GRAPHICS_PROFILE="$(
    "$ADB" -s "$SERIAL" shell getprop ro.boot.mactician.graphics_profile 2>/dev/null \
        | tr -d '\r'
)"
readonly ACTIVE_ANGLE_ENABLED="$(
    "$ADB" -s "$SERIAL" shell getprop debug.angle.feature_overrides_enabled 2>/dev/null \
        | tr -d '\r'
)"
readonly ACTIVE_ANGLE_DISABLED="$(
    "$ADB" -s "$SERIAL" shell getprop debug.angle.feature_overrides_disabled 2>/dev/null \
        | tr -d '\r'
)"
readonly ACTIVE_TRANSPORT="$(
    "$ADB" -s "$SERIAL" shell getprop ro.boot.hardware.gltransport 2>/dev/null \
        | tr -d '\r'
)"
if [[ "$ACTIVE_GRAPHICS_PROFILE" != "$EXPECTED_GRAPHICS_PROFILE" ]]; then
    print -u2 "Active graphics profile is '${ACTIVE_GRAPHICS_PROFILE:-<empty>}', expected '$EXPECTED_GRAPHICS_PROFILE'."
    exit 1
fi
if [[ "$ACTIVE_ANGLE_ENABLED" != "$EXPECTED_ANGLE_ENABLED" \
        || "$ACTIVE_ANGLE_DISABLED" != "$EXPECTED_ANGLE_DISABLED" ]]; then
    print -u2 "Active ANGLE feature overrides do not match the requested draw candidate."
    print -u2 "Enabled: ${ACTIVE_ANGLE_ENABLED:-<empty>}"
    print -u2 "Disabled: ${ACTIVE_ANGLE_DISABLED:-<empty>}"
    exit 1
fi

readonly UTC="$(date -u '+%Y%m%dT%H%M%SZ')"
readonly RUN_DIR="$MEASUREMENT_ROOT/${UTC}__${LABEL}__$$"
readonly RAW_OUTPUT="$RUN_DIR/raw-output.txt"
readonly ROUNDS_JSONL="$RUN_DIR/rounds.jsonl"
readonly SUMMARY="$RUN_DIR/summary.json"
readonly RUN_ID="${LABEL}-${UTC}-$$"
mkdir -p "$RUN_DIR"

cleanup() {
    set +e
    "$ADB" -s "$SERIAL" shell am force-stop "$PROBE_PACKAGE" >/dev/null 2>&1
    "$ADB" -s "$SERIAL" uninstall "$PROBE_PACKAGE" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM HUP

"$ADB" -s "$SERIAL" shell am force-stop "$GAME_PACKAGE" >/dev/null
"$ADB" -s "$SERIAL" install -r -t "$PROBE" > "$RUN_DIR/install.txt"

set +e
"$ADB" -s "$SERIAL" shell am start -W \
    -n "$PROBE_ACTIVITY" \
    --es run_id "$RUN_ID" \
    --ei rounds "$ROUNDS" \
    --ei frames "$FRAMES" \
    --ei draws_per_frame "$DRAWS_PER_FRAME" \
    --ei warmup_rounds "$WARMUP_ROUNDS" \
    > "$RUN_DIR/start.txt" 2>&1
readonly START_STATUS=$?
set -e
if (( START_STATUS != 0 )) || ! grep -Fq 'Status: ok' "$RUN_DIR/start.txt"; then
    print -u2 "The Android GLES draw-stress activity did not start: $RUN_DIR/start.txt"
    exit 1
fi

integer waited=0
while (( waited < 120 )); do
    "$ADB" -s "$SERIAL" logcat -d -v raw -s MacticianGLESDraw:I '*:S' \
        2>/dev/null | tr -d '\r' > "$RAW_OUTPUT.next"
    mv -f "$RAW_OUTPUT.next" "$RAW_OUTPUT"
    if grep -F "$RUN_ID" "$RAW_OUTPUT" | grep -Fq '"kind":"draw_stress_summary"'; then
        break
    fi
    if grep -F "$RUN_ID" "$RAW_OUTPUT" | grep -Fq '"kind":"failure"'; then
        print -u2 "The Android GLES draw-stress activity reported a failure: $RAW_OUTPUT"
        exit 1
    fi
    sleep 1
    (( waited += 1 ))
done
grep -F "$RUN_ID" "$RAW_OUTPUT" | grep -E '^\{' > "$ROUNDS_JSONL" || true
if ! grep -Fq '"kind":"draw_stress_summary"' "$ROUNDS_JSONL"; then
    print -u2 "The Android GLES draw-stress activity timed out: $RAW_OUTPUT"
    exit 1
fi
if ! "$JQ" -e -s \
        '([.[] | select(.kind == "attestation")][0]
           | (.renderer | contains("ANGLE") and contains("Vulkan"))
             and .guest_angle_mapped == true
             and .ranchu_vulkan_mapped == true)' \
        "$ROUNDS_JSONL" >/dev/null; then
    print -u2 "The draw probe did not attest the guest ANGLE -> Vulkan renderer: $RAW_OUTPUT"
    exit 1
fi
if ! "$JQ" -e -s \
        --argjson rounds "$ROUNDS" \
        --argjson warmup_rounds "$WARMUP_ROUNDS" \
        '([.[] | select(.kind == "draw_stress_round")] | length) == $rounds
         and ([.[] | select(.kind == "draw_stress_summary")] | length) == 1
         and all(.[]; (.gl_error? // 0) == 0)
         and ([.[] | select(.kind == "draw_stress_summary")][0].measured_rounds == ($rounds - $warmup_rounds))
         and ([.[] | select(.kind == "draw_stress_round" and .warmup == true)] | length) == $warmup_rounds' \
        "$ROUNDS_JSONL" >/dev/null; then
    print -u2 "The draw probe output was incomplete or reported a GLES error: $RAW_OUTPUT"
    exit 1
fi

readonly PROBE_SHA256="$(shasum -a 256 "$PROBE" | awk '{ print $1 }')"
readonly RENDERER="$(
    "$JQ" -rs '[.[] | select(.kind == "attestation")][0].renderer' "$ROUNDS_JSONL"
)"
"$JQ" -s \
    --arg utc "$UTC" \
    --arg profile_label "$LABEL" \
    --arg serial "$SERIAL" \
    --arg graphics_profile "$ACTIVE_GRAPHICS_PROFILE" \
    --arg transport "$ACTIVE_TRANSPORT" \
    --arg angle_enabled "$ACTIVE_ANGLE_ENABLED" \
    --arg angle_disabled "$ACTIVE_ANGLE_DISABLED" \
    --arg renderer "$RENDERER" \
    --arg probe_sha256 "$PROBE_SHA256" \
    --argjson rounds "$ROUNDS" \
    --argjson warmup_rounds "$WARMUP_ROUNDS" \
    --argjson frames "$FRAMES" \
    --argjson draws_per_frame "$DRAWS_PER_FRAME" \
    '{schema_version: 1, utc: $utc, "label": $profile_label, serial: $serial,
      graphics_profile: $graphics_profile, transport: $transport,
      angle_features: {enabled: $angle_enabled, disabled: $angle_disabled},
      renderer: $renderer, probe_sha256: $probe_sha256,
      workload: {rounds: $rounds, warmup_rounds: $warmup_rounds,
                 measured_rounds: ($rounds - $warmup_rounds), frames: $frames,
                 draws_per_frame: $draws_per_frame,
                 total_draw_calls_per_round: ($frames * ($draws_per_frame + 1)),
                 render_target_size: 512},
      attestation: ([.[] | select(.kind == "attestation")][0]),
      rounds: [.[] | select(.kind == "draw_stress_round")],
      result: ([.[] | select(.kind == "draw_stress_summary")][0])}' \
    "$ROUNDS_JSONL" > "$SUMMARY"

print "$SUMMARY"
