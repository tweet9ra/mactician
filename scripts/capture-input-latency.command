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
readonly INPUT_DEVICE="${TFT_INPUT_EVENT_DEVICE:-/dev/input/event1}"
readonly ROUNDS="${TFT_INPUT_LATENCY_ROUNDS:-3}"
readonly WINDOW_SECONDS="${TFT_INPUT_LATENCY_WINDOW_SECONDS:-12}"
readonly SCENE="${TFT_SCENE:-manual}"
readonly OUTPUT_ROOT="${TFT_INPUT_LATENCY_ROOT:-$PROJECT_DIR/runtime/measurements/input-latency}"
readonly CURRENT_RUN_FILE="$OUTPUT_ROOT/current-run"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
if [[ "$ROUNDS" != <-> ]] || (( ROUNDS < 1 || ROUNDS > 10 )); then
    print "TFT_INPUT_LATENCY_ROUNDS must be from 1 through 10."
    exit 2
fi
if [[ "$WINDOW_SECONDS" != <-> ]] || (( WINDOW_SECONDS < 5 || WINDOW_SECONDS > 30 )); then
    print "TFT_INPUT_LATENCY_WINDOW_SECONDS must be from 5 through 30 seconds."
    exit 2
fi
if [[ ! "$SCENE" =~ '^[a-z0-9][a-z0-9_-]*$' ]]; then
    print "TFT_SCENE must match [a-z0-9][a-z0-9_-]*."
    exit 2
fi
if [[ ! -f "$CURRENT_RUN_FILE" ]]; then
    print "No current latency run was found. Start scripts/run-input-latency-experiment.command first."
    exit 1
fi

typeset RUN_DIR=""
IFS= read -r RUN_DIR < "$CURRENT_RUN_FILE" || true
if [[ -z "$RUN_DIR" || ! -d "$RUN_DIR" || ! -f "$RUN_DIR/launcher-metadata.txt" ]]; then
    print "Invalid current-run pointer: ${RUN_DIR:-empty}."
    exit 1
fi
readonly RUN_DIR
readonly HOST_INPUT_LOG="$RUN_DIR/host-input.jsonl"
readonly UTC_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
readonly OUTPUT_DIR="$RUN_DIR/${UTC_STAMP}__${SCENE}"
mkdir -p "$OUTPUT_DIR"

unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

adb_device() {
    "$ADB" -P "$ADB_SERVER_PORT" -s "$SERIAL" "$@"
}

if ! adb_device get-state >/dev/null 2>&1; then
    print "The TFT AVD is not connected on $SERIAL."
    exit 1
fi

adb_device shell dumpsys activity activities 2>/dev/null \
    | tr -d '\r' \
    | grep -E 'topResumedActivity|mResumedActivity|mCurrentFocus' \
    > "$OUTPUT_DIR/activity-before.txt" || true
if ! grep -F "topResumedActivity=" "$OUTPUT_DIR/activity-before.txt" | grep -Fq "$GAME_ACTIVITY"; then
    print "TFT GameActivity is not in the foreground."
    exit 1
fi

readonly DISPLAY_SIZE="$(adb_device shell wm size 2>/dev/null | tr -d '\r')"
if [[ "$DISPLAY_SIZE" != *"2560x1440"* ]]; then
    print "Expected display 2560x1440, got: $DISPLAY_SIZE"
    exit 1
fi

adb_device shell getevent -lp "$INPUT_DEVICE" 2>/dev/null \
    | tr -d '\r' > "$OUTPUT_DIR/input-device.txt"
if ! grep -Fq 'virtio_input_multi_touch_1' "$OUTPUT_DIR/input-device.txt"; then
    print "$INPUT_DEVICE is not the primary display touchscreen."
    exit 1
fi

adb_device shell dumpsys SurfaceFlinger --list 2>/dev/null \
    | tr -d '\r' > "$OUTPUT_DIR/layers-before.txt"
readonly LAYER_MATCH_FILE="$OUTPUT_DIR/layer-matches.txt"
grep -F "SurfaceView[$GAME_ACTIVITY](BLAST)" "$OUTPUT_DIR/layers-before.txt" \
    > "$LAYER_MATCH_FILE" || true
readonly LAYER_MATCH_COUNT="$(wc -l < "$LAYER_MATCH_FILE" | tr -d ' ')"
if [[ "$LAYER_MATCH_COUNT" != "1" ]]; then
    print "Expected one TFT BLAST SurfaceView, found: $LAYER_MATCH_COUNT."
    exit 1
fi
readonly LAYER="$(sed -n '1p' "$LAYER_MATCH_FILE")"
print -r -- "$LAYER" > "$OUTPUT_DIR/selected-layer.txt"

print 'round,frame,delta_ms' > "$OUTPUT_DIR/frame-times.csv"
print 'round,gap_ms' > "$OUTPUT_DIR/input-gaps.csv"
: > "$OUTPUT_DIR/host-input.jsonl"

integer round
integer host_start_line host_end_line
typeset getevent_pid raw_input raw_frames input_state host_round
for (( round = 1; round <= ROUNDS; round++ )); do
    print
    print "Round $round/$ROUNDS: prepare a unit for the drag test in scene '$SCENE'."
    read -r "?Press Enter; the ${WINDOW_SECONDS}s window starts in 3 seconds... "
    sleep 3
    print "START: continuously drag the held unit left and right."

    raw_input="$OUTPUT_DIR/getevent-round-${round}.txt"
    raw_frames="$OUTPUT_DIR/surfaceflinger-round-${round}.txt"
    input_state="$OUTPUT_DIR/input-state-round-${round}.txt"
    host_round="$OUTPUT_DIR/host-input-round-${round}.jsonl"
    host_start_line=0
    if [[ -f "$HOST_INPUT_LOG" ]]; then
        host_start_line="$(wc -l < "$HOST_INPUT_LOG" | tr -d ' ')"
    fi

    adb_device shell "dumpsys SurfaceFlinger --latency-clear \"$LAYER\"" >/dev/null
    adb_device shell "timeout $WINDOW_SECONDS getevent -lt $INPUT_DEVICE" \
        > "$raw_input" &
    getevent_pid=$!
    wait "$getevent_pid" || true
    sleep 0.2
    print "STOP."

    adb_device shell "dumpsys SurfaceFlinger --latency \"$LAYER\"" \
        | tr -d '\r' > "$raw_frames"
    adb_device shell dumpsys input 2>/dev/null \
        | tr -d '\r' \
        | grep -E "channelName=.*$PACKAGE|PendingEvent:|InboundQueue:|CommandQueue:|mLastSlowEventTime|mNumEventsSinceLastSlowEventReport" \
        > "$input_state" || true

    host_end_line=0
    if [[ -f "$HOST_INPUT_LOG" ]]; then
        host_end_line="$(wc -l < "$HOST_INPUT_LOG" | tr -d ' ')"
    fi
    if (( host_end_line > host_start_line )); then
        sed -n "$(( host_start_line + 1 )),${host_end_line}p" "$HOST_INPUT_LOG" > "$host_round"
        sed -n "$(( host_start_line + 1 )),${host_end_line}p" "$HOST_INPUT_LOG" >> "$OUTPUT_DIR/host-input.jsonl"
    else
        : > "$host_round"
    fi

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
    ' "$raw_frames" >> "$OUTPUT_DIR/frame-times.csv"

    awk -v round="$round" '
        /EV_SYN[[:space:]]+SYN_REPORT/ {
            value = $2
            gsub(/[][]/, "", value)
            now = value + 0
            if (previous > 0) {
                gap = (now - previous) * 1000
                if (gap > 0 && gap <= 50) {
                    printf "%d,%.6f\n", round, gap
                }
            }
            previous = now
        }
    ' "$raw_input" >> "$OUTPUT_DIR/input-gaps.csv"
done

adb_device shell dumpsys activity activities 2>/dev/null \
    | tr -d '\r' \
    | grep -E 'topResumedActivity|mResumedActivity|mCurrentFocus' \
    > "$OUTPUT_DIR/activity-after.txt" || true
if ! grep -F "topResumedActivity=" "$OUTPUT_DIR/activity-after.txt" | grep -Fq "$GAME_ACTIVITY"; then
    print "INVALID: GameActivity left the foreground during measurement."
    exit 3
fi

awk -F, 'NR > 1 { print $3 }' "$OUTPUT_DIR/frame-times.csv" > "$OUTPUT_DIR/frame-times.txt"
sort -n "$OUTPUT_DIR/frame-times.txt" > "$OUTPUT_DIR/frame-times-sorted.txt"
readonly FRAME_COUNT="$(wc -l < "$OUTPUT_DIR/frame-times.txt" | tr -d ' ')"
if (( FRAME_COUNT < 30 )); then
    print "INVALID: not enough frame samples: $FRAME_COUNT."
    exit 3
fi
readonly FRAME_P95_INDEX=$(( (FRAME_COUNT - 1) * 95 / 100 + 1 ))
readonly FRAME_P95="$(sed -n "${FRAME_P95_INDEX}p" "$OUTPUT_DIR/frame-times-sorted.txt")"
readonly FRAME_MEAN="$(awk '{ sum += $1 } END { printf "%.2f", sum / NR }' "$OUTPUT_DIR/frame-times.txt")"
readonly FPS="$(awk -v mean="$FRAME_MEAN" 'BEGIN { printf "%.1f", 1000 / mean }')"

awk -F, 'NR > 1 { print $2 }' "$OUTPUT_DIR/input-gaps.csv" > "$OUTPUT_DIR/input-gaps.txt"
sort -n "$OUTPUT_DIR/input-gaps.txt" > "$OUTPUT_DIR/input-gaps-sorted.txt"
readonly INPUT_GAP_COUNT="$(wc -l < "$OUTPUT_DIR/input-gaps.txt" | tr -d ' ')"
if (( INPUT_GAP_COUNT < 30 )); then
    print "INVALID: not enough touchscreen samples: $INPUT_GAP_COUNT."
    exit 3
fi
readonly INPUT_P95_INDEX=$(( (INPUT_GAP_COUNT - 1) * 95 / 100 + 1 ))
readonly INPUT_P95="$(sed -n "${INPUT_P95_INDEX}p" "$OUTPUT_DIR/input-gaps-sorted.txt")"
readonly INPUT_MEAN="$(awk '{ sum += $1 } END { printf "%.2f", sum / NR }' "$OUTPUT_DIR/input-gaps.txt")"
readonly INPUT_HZ="$(awk -v mean="$INPUT_MEAN" 'BEGIN { printf "%.1f", 1000 / mean }')"
readonly HOST_GESTURES="$(grep -c '"action":"down"' "$OUTPUT_DIR/host-input.jsonl" || true)"
if (( HOST_GESTURES < ROUNDS )); then
    print "INVALID: the click marker recorded only $HOST_GESTURES gestures for $ROUNDS rounds."
    print "Check Accessibility permission and release the button before each window ends."
    exit 3
fi

integer QUEUES_OK=1
for input_state in "$OUTPUT_DIR"/input-state-round-*.txt; do
    grep -Fq "channelName=" "$input_state" || QUEUES_OK=0
    grep -Fq "status=NORMAL" "$input_state" || QUEUES_OK=0
    grep -Fq "responsive=true" "$input_state" || QUEUES_OK=0
    grep -Fq "PendingEvent: <none>" "$input_state" || QUEUES_OK=0
    grep -Fq "InboundQueue: <empty>" "$input_state" || QUEUES_OK=0
    grep -Fq "CommandQueue: <empty>" "$input_state" || QUEUES_OK=0
done

{
    print "scene=$SCENE"
    print "rounds=$ROUNDS"
    print "window_seconds=$WINDOW_SECONDS"
    print "display=$DISPLAY_SIZE"
    print "input_device=$INPUT_DEVICE"
    print "host_gestures=$HOST_GESTURES"
    print "touch_samples=$INPUT_GAP_COUNT"
    print "touch_mean_gap_ms=$INPUT_MEAN"
    print "touch_p95_gap_ms=$INPUT_P95"
    print "touch_rate_hz=$INPUT_HZ"
    print "frame_samples=$FRAME_COUNT"
    print "fps=$FPS"
    print "frame_mean_ms=$FRAME_MEAN"
    print "frame_p95_ms=$FRAME_P95"
    print "input_queues_ok=$QUEUES_OK"
} > "$OUTPUT_DIR/summary.txt"

print
print "TFT input latency — $(sed -n 's/^variant=//p' "$RUN_DIR/launcher-metadata.txt") / $SCENE"
print "touch≈${INPUT_HZ}Hz mean-gap=${INPUT_MEAN}ms p95-gap=${INPUT_P95}ms queues_ok=$QUEUES_OK"
print "fps≈$FPS mean=${FRAME_MEAN}ms p95=${FRAME_P95}ms host_gestures=$HOST_GESTURES"
print "Artifacts: $OUTPUT_DIR"
