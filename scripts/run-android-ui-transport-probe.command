#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"

readonly LABEL="${1:-}"
readonly ROUNDS="${2:-6}"
readonly SWIPE_PAIRS="${TFT_UI_TRANSPORT_SWIPE_PAIRS:-15}"
readonly SWIPE_DURATION_MS="${TFT_UI_TRANSPORT_SWIPE_DURATION_MS:-180}"
readonly MINIMUM_FRAMES_PER_ROUND="${TFT_UI_TRANSPORT_MINIMUM_FRAMES_PER_ROUND:-$(( SWIPE_PAIRS * 8 ))}"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly EXPECTED_GRAPHICS_PROFILE="${TFT_UI_TRANSPORT_EXPECTED_GRAPHICS_PROFILE:-}"
readonly EXPECTED_ANGLE_ENABLED="${TFT_UI_TRANSPORT_EXPECTED_ANGLE_ENABLED:-}"
readonly EXPECTED_ANGLE_DISABLED="${TFT_UI_TRANSPORT_EXPECTED_ANGLE_DISABLED:-}"
readonly EXPECT_ANGLE_MAPPED="${TFT_UI_TRANSPORT_EXPECT_ANGLE_MAPPED:-}"
readonly MEASUREMENT_ROOT="${TFT_UI_TRANSPORT_ROOT:-$PROJECT_DIR/runtime/measurements/android-ui-transport}"
readonly TFT_PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly SETTINGS_PACKAGE="com.android.settings"
readonly ADB="$(tft_resolve_adb)"
readonly JQ="$(command -v jq || true)"

if [[ ! "$LABEL" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' ]]; then
    print -u2 "Usage: ${0:t} <profile-label> [rounds]"
    print -u2 "The profile label may contain letters, digits, dots, underscores, and dashes."
    exit 2
fi
for numeric_name numeric_value in \
        rounds "$ROUNDS" \
        swipe-pairs "$SWIPE_PAIRS" \
        swipe-duration-ms "$SWIPE_DURATION_MS" \
        minimum-frames-per-round "$MINIMUM_FRAMES_PER_ROUND"; do
    if [[ "$numeric_value" != <-> ]] || (( numeric_value < 1 )); then
        print -u2 "$numeric_name must be a positive integer."
        exit 2
    fi
done
if [[ -z "$JQ" ]]; then
    print -u2 "jq is required to write the transport-probe summary."
    exit 1
fi
if [[ ! "$EXPECTED_GRAPHICS_PROFILE" =~ '^[a-z0-9][a-z0-9-]*$' ]]; then
    print -u2 "TFT_UI_TRANSPORT_EXPECTED_GRAPHICS_PROFILE is required and must use lowercase letters, digits, and dashes."
    exit 2
fi
for feature_expectation in "$EXPECTED_ANGLE_ENABLED" "$EXPECTED_ANGLE_DISABLED"; do
    if [[ -n "$feature_expectation" \
            && ! "$feature_expectation" =~ '^([A-Za-z0-9_]+[*]?)(:[A-Za-z0-9_]+[*]?)*$' ]]; then
        print -u2 "Expected ANGLE features must be a feature or a colon-separated list."
        exit 2
    fi
done
if [[ -n "$EXPECT_ANGLE_MAPPED" && "$EXPECT_ANGLE_MAPPED" != 0 \
        && "$EXPECT_ANGLE_MAPPED" != 1 ]]; then
    print -u2 "TFT_UI_TRANSPORT_EXPECT_ANGLE_MAPPED must be 0 or 1 when set."
    exit 2
fi
if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print -u2 "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi

unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null
if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print -u2 "The transport probe requires an already running AVD on $SERIAL."
    exit 1
fi
readonly ACTIVE_GRAPHICS_PROFILE="$(
    "$ADB" -s "$SERIAL" shell getprop ro.boot.mactician.graphics_profile 2>/dev/null \
        | tr -d '\r'
)"
if [[ "$ACTIVE_GRAPHICS_PROFILE" != "$EXPECTED_GRAPHICS_PROFILE" ]]; then
    print -u2 "The running AVD graphics profile is '${ACTIVE_GRAPHICS_PROFILE:-<unattested>}', expected '$EXPECTED_GRAPHICS_PROFILE'."
    print -u2 "Cold-boot the requested profile before collecting transport evidence."
    exit 1
fi
readonly TRANSPORT="$(
    "$ADB" -s "$SERIAL" shell getprop ro.boot.hardware.gltransport 2>/dev/null \
        | tr -d '\r'
)"
readonly HWUI_RENDERER="$(
    "$ADB" -s "$SERIAL" shell getprop debug.hwui.renderer 2>/dev/null \
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
if [[ -n "$EXPECTED_ANGLE_ENABLED" \
        && "$ACTIVE_ANGLE_ENABLED" != "$EXPECTED_ANGLE_ENABLED" ]]; then
    print -u2 "Active ANGLE enabled features do not match the requested transport profile."
    print -u2 "Actual: ${ACTIVE_ANGLE_ENABLED:-<empty>}"
    exit 1
fi
if [[ -n "$EXPECTED_ANGLE_DISABLED" \
        && "$ACTIVE_ANGLE_DISABLED" != "$EXPECTED_ANGLE_DISABLED" ]]; then
    print -u2 "Active ANGLE disabled features do not match the requested transport profile."
    print -u2 "Actual: ${ACTIVE_ANGLE_DISABLED:-<empty>}"
    exit 1
fi

readonly DISPLAY_SIZE="$(
    "$ADB" -s "$SERIAL" shell wm size 2>/dev/null \
        | tr -d '\r' \
        | sed -n \
            -e 's/^Physical size: \([0-9][0-9]*x[0-9][0-9]*\)$/\1/p' \
            -e 's/^Override size: \([0-9][0-9]*x[0-9][0-9]*\)$/\1/p' \
        | tail -n 1
)"
if [[ ! "$DISPLAY_SIZE" =~ '^([0-9]+)x([0-9]+)$' ]]; then
    print -u2 "Could not determine the active AVD display size."
    exit 1
fi
readonly DISPLAY_WIDTH="${match[1]}"
readonly DISPLAY_HEIGHT="${match[2]}"
readonly DISPLAY_DENSITY="$(
    "$ADB" -s "$SERIAL" shell wm density 2>/dev/null \
        | tr -d '\r' \
        | sed -n \
            -e 's/^Physical density: \([0-9][0-9]*\)$/\1/p' \
            -e 's/^Override density: \([0-9][0-9]*\)$/\1/p' \
        | tail -n 1
)"
if [[ "$DISPLAY_DENSITY" != <-> ]]; then
    print -u2 "Could not determine the active AVD display density."
    exit 1
fi
readonly SWIPE_X=$(( DISPLAY_WIDTH / 2 ))
readonly SWIPE_LOW_Y=$(( DISPLAY_HEIGHT * 3 / 4 ))
readonly SWIPE_HIGH_Y=$(( DISPLAY_HEIGHT / 4 ))

readonly UTC="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$MEASUREMENT_ROOT/${UTC}__${LABEL}"
readonly ROUNDS_JSONL="$RUN_DIR/rounds.jsonl"
mkdir -p "${RUN_DIR:h}"
if ! mkdir "$RUN_DIR" 2>/dev/null; then
    if [[ -e "$RUN_DIR" ]]; then
        print -u2 "Transport-probe evidence directory already exists: $RUN_DIR"
        print -u2 "Use a distinct label; existing evidence will not be overwritten."
    else
        print -u2 "Could not create the transport-probe evidence directory: $RUN_DIR"
    fi
    exit 1
fi
: > "$ROUNDS_JSONL"
typeset SETTINGS_ANGLE_MAPPED=unknown

write_rejected_summary() {
    local reason="$1"
    "$JQ" -s \
        --arg utc "$UTC" \
        --arg profile_label "$LABEL" \
        --arg graphics_profile "$ACTIVE_GRAPHICS_PROFILE" \
        --arg serial "$SERIAL" \
        --arg display "$DISPLAY_SIZE" \
        --argjson display_density "$DISPLAY_DENSITY" \
        --arg transport "$TRANSPORT" \
        --arg hwui_renderer "$HWUI_RENDERER" \
        --arg angle_enabled "$ACTIVE_ANGLE_ENABLED" \
        --arg angle_disabled "$ACTIVE_ANGLE_DISABLED" \
        --arg settings_angle_mapped "$SETTINGS_ANGLE_MAPPED" \
        --arg rejected_reason "$reason" \
        --argjson swipe_pairs "$SWIPE_PAIRS" \
        --argjson swipe_duration_ms "$SWIPE_DURATION_MS" \
        --argjson minimum_frames_per_round "$MINIMUM_FRAMES_PER_ROUND" \
        '{schema_version: 5, utc: $utc, "label": $profile_label, serial: $serial,
          graphics_profile: $graphics_profile,
          display: $display, display_density: $display_density,
          transport: $transport, hwui_renderer: $hwui_renderer,
          angle_features: {enabled: $angle_enabled, disabled: $angle_disabled},
          settings_guest_angle_mapped: $settings_angle_mapped,
          swipe_pairs: $swipe_pairs, swipe_duration_ms: $swipe_duration_ms,
          minimum_frames_per_round: $minimum_frames_per_round,
          rejected_reason: $rejected_reason, rounds: .}' \
        "$ROUNDS_JSONL" > "$RUN_DIR/summary.json"
}

"$ADB" -s "$SERIAL" shell am force-stop "$TFT_PACKAGE"
"$ADB" -s "$SERIAL" shell am start -W -a android.settings.SETTINGS > "$RUN_DIR/start.txt"
if ! grep -Fqx 'Status: ok' "$RUN_DIR/start.txt" \
        || ! grep -Eq '^Activity: com[.]android[.]settings/' "$RUN_DIR/start.txt"; then
    write_rejected_summary settings_not_foreground
    print -u2 "Android Settings did not become the measured foreground activity."
    print -u2 "Partial evidence is retained: $RUN_DIR"
    exit 1
fi
sleep 2

settings_pid="$(
    "$ADB" -s "$SERIAL" shell pidof "$SETTINGS_PACKAGE" 2>/dev/null \
        | tr -d '\r' | awk '{ print $1 }'
)"
if [[ "$settings_pid" == <-> ]] \
        && "$ADB" -s "$SERIAL" shell \
            "grep -Fq libGLESv2_angle.so /proc/$settings_pid/maps" 2>/dev/null; then
    SETTINGS_ANGLE_MAPPED=yes
else
    SETTINGS_ANGLE_MAPPED=no
fi
if [[ -n "$EXPECT_ANGLE_MAPPED" \
        && ( ( "$EXPECT_ANGLE_MAPPED" == 1 && "$SETTINGS_ANGLE_MAPPED" != yes ) \
            || ( "$EXPECT_ANGLE_MAPPED" == 0 && "$SETTINGS_ANGLE_MAPPED" != no ) ) ]]; then
    write_rejected_summary settings_angle_mapping_mismatch
    print -u2 "Settings guest ANGLE mapping is '$SETTINGS_ANGLE_MAPPED', expected '$EXPECT_ANGLE_MAPPED'."
    exit 1
fi

integer round pair
for (( round = 1; round <= ROUNDS; round++ )); do
    round_gfxinfo="$RUN_DIR/round-$round-gfxinfo.txt"
    "$ADB" -s "$SERIAL" shell dumpsys gfxinfo "$SETTINGS_PACKAGE" reset >/dev/null
    start_ns="$(date +%s%N)"
    for (( pair = 1; pair <= SWIPE_PAIRS; pair++ )); do
        "$ADB" -s "$SERIAL" shell input swipe \
            "$SWIPE_X" "$SWIPE_LOW_Y" "$SWIPE_X" "$SWIPE_HIGH_Y" \
            "$SWIPE_DURATION_MS" >/dev/null
        "$ADB" -s "$SERIAL" shell input swipe \
            "$SWIPE_X" "$SWIPE_HIGH_Y" "$SWIPE_X" "$SWIPE_LOW_Y" \
            "$SWIPE_DURATION_MS" >/dev/null
    done
    end_ns="$(date +%s%N)"
    elapsed_ns=$(( end_ns - start_ns ))
    "$ADB" -s "$SERIAL" shell dumpsys gfxinfo "$SETTINGS_PACKAGE" > "$round_gfxinfo"

    total_frames="$(sed -n 's/^Total frames rendered: \([0-9][0-9]*\)$/\1/p' "$round_gfxinfo" | head -n 1)"
    janky_frames="$(sed -n 's/^Janky frames: \([0-9][0-9]*\) .*/\1/p' "$round_gfxinfo" | head -n 1)"
    p50_ms="$(sed -n 's/^50th percentile: \([0-9][0-9]*\)ms$/\1/p' "$round_gfxinfo" | head -n 1)"
    p90_ms="$(sed -n 's/^90th percentile: \([0-9][0-9]*\)ms$/\1/p' "$round_gfxinfo" | head -n 1)"
    p95_ms="$(sed -n 's/^95th percentile: \([0-9][0-9]*\)ms$/\1/p' "$round_gfxinfo" | head -n 1)"
    p99_ms="$(sed -n 's/^99th percentile: \([0-9][0-9]*\)ms$/\1/p' "$round_gfxinfo" | head -n 1)"
    if [[ -z "$total_frames" || -z "$janky_frames" || -z "$p50_ms" \
            || -z "$p90_ms" || -z "$p95_ms" || -z "$p99_ms" ]]; then
        write_rejected_summary "gfxinfo_parse_round_$round"
        print -u2 "Could not parse Android gfxinfo for round $round."
        exit 1
    fi

    "$JQ" -n \
        --argjson round "$round" \
        --argjson elapsed_ns "$elapsed_ns" \
        --argjson total_frames "$total_frames" \
        --argjson janky_frames "$janky_frames" \
        --argjson p50_ms "$p50_ms" \
        --argjson p90_ms "$p90_ms" \
        --argjson p95_ms "$p95_ms" \
        --argjson p99_ms "$p99_ms" \
        '{round: $round, elapsed_ns: $elapsed_ns, total_frames: $total_frames,
          janky_frames: $janky_frames, p50_ms: $p50_ms, p90_ms: $p90_ms,
          p95_ms: $p95_ms, p99_ms: $p99_ms}' >> "$ROUNDS_JSONL"
    if (( total_frames < MINIMUM_FRAMES_PER_ROUND )); then
        write_rejected_summary "non_rendering_round_$round"
        print -u2 "Transport probe became non-rendering in round $round: $total_frames frames, expected at least $MINIMUM_FRAMES_PER_ROUND."
        print -u2 "Partial evidence is retained: $RUN_DIR"
        exit 1
    fi
done

"$JQ" -s \
    --arg utc "$UTC" \
    --arg profile_label "$LABEL" \
    --arg graphics_profile "$ACTIVE_GRAPHICS_PROFILE" \
    --arg serial "$SERIAL" \
    --arg display "$DISPLAY_SIZE" \
    --argjson display_density "$DISPLAY_DENSITY" \
    --arg transport "$TRANSPORT" \
    --arg hwui_renderer "$HWUI_RENDERER" \
    --arg angle_enabled "$ACTIVE_ANGLE_ENABLED" \
    --arg angle_disabled "$ACTIVE_ANGLE_DISABLED" \
    --arg settings_angle_mapped "$SETTINGS_ANGLE_MAPPED" \
    --argjson swipe_pairs "$SWIPE_PAIRS" \
    --argjson swipe_duration_ms "$SWIPE_DURATION_MS" \
    --argjson minimum_frames_per_round "$MINIMUM_FRAMES_PER_ROUND" \
    'def median:
       sort as $sorted
       | ($sorted | length) as $count
       | if ($count % 2) == 1 then $sorted[($count / 2 | floor)]
         else (($sorted[$count / 2 - 1] + $sorted[$count / 2]) / 2)
         end;
     . as $all
     | ($all | if length > 3 then .[3:] else . end) as $warm
     | {schema_version: 5, utc: $utc, "label": $profile_label, serial: $serial,
        graphics_profile: $graphics_profile,
        display: $display, display_density: $display_density,
        transport: $transport, hwui_renderer: $hwui_renderer,
        angle_features: {enabled: $angle_enabled, disabled: $angle_disabled},
        settings_guest_angle_mapped: $settings_angle_mapped,
        swipe_pairs: $swipe_pairs,
        swipe_duration_ms: $swipe_duration_ms,
        minimum_frames_per_round: $minimum_frames_per_round, rounds: $all,
        warmup_rounds_discarded: (($all | length) - ($warm | length)),
        mean_elapsed_ms: (($all | map(.elapsed_ns) | add) / ($all | length) / 1000000),
        median_elapsed_ms: (($all | map(.elapsed_ns) | median) / 1000000),
        max_p95_ms: ($all | map(.p95_ms) | max),
        max_p99_ms: ($all | map(.p99_ms) | max),
        total_janky_frames: ($all | map(.janky_frames) | add),
        warm_mean_elapsed_ms: (($warm | map(.elapsed_ns) | add) / ($warm | length) / 1000000),
        warm_median_elapsed_ms: (($warm | map(.elapsed_ns) | median) / 1000000),
        warm_max_p95_ms: ($warm | map(.p95_ms) | max),
        warm_max_p99_ms: ($warm | map(.p99_ms) | max),
        warm_total_janky_frames: ($warm | map(.janky_frames) | add)}' \
    "$ROUNDS_JSONL" > "$RUN_DIR/summary.json"

print "Android UI transport probe complete: $RUN_DIR"
"$JQ" '{"label": .label, graphics_profile, transport, hwui_renderer,
        angle_features, settings_guest_angle_mapped, warm_mean_elapsed_ms,
        warm_median_elapsed_ms, warm_max_p95_ms, warm_max_p99_ms,
        warm_total_janky_frames}' "$RUN_DIR/summary.json"
print "TFT remains stopped in the running experimental AVD."
