#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ADB="$(tft_resolve_adb)"
readonly ADB
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly WATCH_INTERVAL="${TFT_PSO_WATCH_INTERVAL:-10}"
readonly PSO_CPU_LIST="${TFT_PSO_CPU_LIST:-0-6}"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 to 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

if [[ "$PSO_CPU_LIST" != 0-<-> ]]; then
    print "TFT_PSO_CPU_LIST must be a 0-N range."
    exit 2
fi
readonly PSO_CPU_LAST="${PSO_CPU_LIST#0-}"
if (( PSO_CPU_LAST < 0 || PSO_CPU_LAST > 15 )); then
    print "TFT_PSO_CPU_LIST: N must be from 0 to 15."
    exit 2
fi
typeset computed_pso_cpu_mask
printf -v computed_pso_cpu_mask '%x' "$(( (1 << (PSO_CPU_LAST + 1)) - 1 ))"
readonly PSO_CPU_MASK="$computed_pso_cpu_mask"

case "$WATCH_INTERVAL" in
    0|[1-9]|[1-9][0-9]) ;;
    *)
        print "TFT_PSO_WATCH_INTERVAL must be an integer from 0 to 99 seconds."
        exit 2
        ;;
esac

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The rootable TFT AVD is not connected on $SERIAL."
    exit 1
fi

if [[ "$("$ADB" -s "$SERIAL" shell id -u 2>/dev/null | tr -d '\r')" != "0" ]]; then
    print "adbd on $SERIAL is not running as root. Run: $ADB -s $SERIAL root"
    exit 1
fi

print "PSO watcher: affinity ${PSO_CPU_LIST}; ANGLE-Worker nice 0; interval ${WATCH_INTERVAL}s."

while "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
    "$ADB" -s "$SERIAL" shell '
        pso_cpu_list='"$PSO_CPU_LIST"'
        pso_cpu_mask='"$PSO_CPU_MASK"'
        pso_changed=0
        for pso_pid in $(pidof \
            "${PACKAGE}:psoprogramservice" \
            "${PACKAGE}:psoprogramservice1" \
            "${PACKAGE}:psoprogramservice2" \
            "${PACKAGE}:psoprogramservice3"); do
            [ -d "/proc/$pso_pid/task" ] || continue
            for pso_task in /proc/$pso_pid/task/*; do
                [ -r "$pso_task/status" ] || continue
                pso_tid=${pso_task##*/}
                pso_cpus=$(awk "/^Cpus_allowed_list:/ {print \$2}" "$pso_task/status")
                if [ "$pso_cpus" != "$pso_cpu_list" ]; then
                    if taskset -p "$pso_cpu_mask" "$pso_tid" >/dev/null 2>&1; then
                        pso_changed=$((pso_changed+1))
                    fi
                fi

                [ -r "$pso_task/comm" ] || continue
                [ "$(cat "$pso_task/comm")" = "ANGLE-Worker" ] || continue
                [ -r "$pso_task/stat" ] || continue
                pso_nice=$(sed "s/^[^)]*) //" "$pso_task/stat" | cut -d" " -f17)
                case "$pso_nice" in
                    ""|*[!0-9-]*) continue ;;
                esac
                if [ "$pso_nice" -gt 0 ]; then
                    pso_delta=$((-pso_nice))
                    if renice -n "$pso_delta" -p "$pso_tid" >/dev/null 2>&1; then
                        pso_changed=$((pso_changed+1))
                    fi
                fi
            done
        done
        [ "$pso_changed" -eq 0 ] || printf "PSO watcher applied %s adjustments\n" "$pso_changed"
    ' 2>/dev/null || true
    [[ "$WATCH_INTERVAL" == "0" ]] && break
    sleep "$WATCH_INTERVAL"
done

if [[ "$WATCH_INTERVAL" == "0" ]]; then
    print "PSO tuning was applied once."
else
    print "PSO watcher: the AVD disconnected."
fi
