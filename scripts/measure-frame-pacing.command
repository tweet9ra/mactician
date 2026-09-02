#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ADB="$(tft_resolve_adb)"
readonly ADB
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

readonly TIMES_FILE="$(mktemp "${TMPDIR:-/tmp}/tft-frame-times.XXXXXX")"

cleanup() {
    rm -f "$TIMES_FILE"
}
trap cleanup EXIT

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The TFT AVD is not connected on $SERIAL."
    exit 1
fi

LAYER="$(
    "$ADB" -s "$SERIAL" shell dumpsys SurfaceFlinger --list 2>/dev/null \
        | tr -d '\r' \
        | grep -F "SurfaceView[$PACKAGE/com.epicgames.unreal.GameActivity](BLAST)" \
        | tail -n 1 \
        | sed -E 's/^RequestedLayerState\{(.*) parentId=[^}]*\}$/\1/' || true
)"

if [[ -z "$LAYER" ]]; then
    print "No active TFT GameActivity SurfaceView was found."
    exit 1
fi

"$ADB" -s "$SERIAL" shell "dumpsys SurfaceFlinger --latency \"$LAYER\"" \
    | tr -d '\r' \
    | awk 'NR > 1 && $2 + 0 > 0 { print $2 }' \
    | sort -n \
    | awk '
        NR > 1 {
            delta = ($1 - previous) / 1000000
            if (delta > 0 && delta < 1000) print delta
        }
        { previous = $1 }
    ' \
    | sort -n > "$TIMES_FILE"

readonly COUNT="$(wc -l < "$TIMES_FILE" | tr -d ' ')"
if (( COUNT < 10 )); then
    print "Not enough frames to measure: $COUNT."
    exit 1
fi

readonly P50_INDEX=$(( (COUNT - 1) * 50 / 100 + 1 ))
readonly P95_INDEX=$(( (COUNT - 1) * 95 / 100 + 1 ))
readonly P99_INDEX=$(( (COUNT - 1) * 99 / 100 + 1 ))
readonly P50="$(sed -n "${P50_INDEX}p" "$TIMES_FILE")"
readonly P95="$(sed -n "${P95_INDEX}p" "$TIMES_FILE")"
readonly P99="$(sed -n "${P99_INDEX}p" "$TIMES_FILE")"

read -r MEAN OVER20 OVER40 OVER60 <<< "$(
    awk '
        { sum += $1; if ($1 > 20) over20++; if ($1 > 40) over40++; if ($1 > 60) over60++ }
        END { printf "%.2f %d %d %d", sum / NR, over20, over40, over60 }
    ' "$TIMES_FILE"
)"
readonly FPS="$(awk -v mean="$MEAN" 'BEGIN { printf "%.1f", 1000 / mean }')"

print "TFT frame pacing — $SERIAL"
print "samples=$COUNT fps≈$FPS mean=${MEAN}ms p50=${P50}ms p95=${P95}ms p99=${P99}ms"
print ">20ms=$OVER20 >40ms=$OVER40 >60ms=$OVER60"
