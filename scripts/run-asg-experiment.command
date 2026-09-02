#!/bin/zsh
set -euo pipefail

# Do not let zsh lower the priority of the stable launcher merely because this
# wrapper backgrounds it long enough to verify the active graphics transport.
unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ADB="$(tft_resolve_adb)"
readonly ADB
readonly AVD_HOME="$(tft_resolve_avd_home)"
readonly AVD_NAME="${TFT_AVD_NAME:-Tft}"
readonly SERIAL="${TFT_SERIAL:-emulator-5572}"
readonly LAUNCHER="${TFT_LAUNCHER:-$PROJECT_DIR/run-tft-gles32.command}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly CONFIG="$AVD_HOME/$AVD_NAME.avd/config.ini"
readonly HARDWARE_CONFIG="$AVD_HOME/$AVD_NAME.avd/hardware-qemu.ini"
readonly CONFIG_BACKUP="$CONFIG.mactician-asg-backup"
readonly HARDWARE_CONFIG_BACKUP="$HARDWARE_CONFIG.mactician-asg-backup"
readonly LOCK_FILE="$AVD_HOME/$AVD_NAME.avd/.mactician-avd.lock"
readonly TRANSPORT="${TFT_GLTRANSPORT:-virtio-gpu-asg}"
readonly EXPECTED_BASELINE_TRANSPORT="${TFT_EXPECTED_GLTRANSPORT_BASELINE:-pipe}"
readonly DRAW_FLUSH_INTERVAL="${TFT_GL_DRAW_FLUSH_INTERVAL:-}"
readonly ASG_WRITE_BUFFER_SIZE="${TFT_ASG_WRITE_BUFFER_SIZE:-}"
readonly ASG_WRITE_STEP_SIZE="${TFT_ASG_WRITE_STEP_SIZE:-}"
readonly ASG_DATA_RING_SIZE="${TFT_ASG_DATA_RING_SIZE:-}"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 to 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

case "$TRANSPORT" in
    virtio-gpu-asg|virtio-gpu-pipe) ;;
    *)
        print "Unsupported test transport: $TRANSPORT"
        print "Allowed values: virtio-gpu-asg, virtio-gpu-pipe"
        exit 2
        ;;
esac

if [[ -n "$DRAW_FLUSH_INTERVAL" ]]; then
    if [[ "$DRAW_FLUSH_INTERVAL" != <-> ]] \
            || (( DRAW_FLUSH_INTERVAL < 100 || DRAW_FLUSH_INTERVAL > 10000 )); then
        print "TFT_GL_DRAW_FLUSH_INTERVAL must be an integer from 100 to 10000 microseconds."
        exit 2
    fi
fi
if [[ -n "$ASG_WRITE_BUFFER_SIZE" ]]; then
    if [[ "$ASG_WRITE_BUFFER_SIZE" != <-> ]] \
            || (( ASG_WRITE_BUFFER_SIZE < 65536 || ASG_WRITE_BUFFER_SIZE > 1048576 )); then
        print "TFT_ASG_WRITE_BUFFER_SIZE must be from 65536 to 1048576 bytes; a larger buffer crashes this emulator ABI."
        exit 2
    fi
fi
if [[ -n "$ASG_WRITE_STEP_SIZE" ]]; then
    if [[ "$ASG_WRITE_STEP_SIZE" != <-> ]] \
            || (( ASG_WRITE_STEP_SIZE < 1024 || ASG_WRITE_STEP_SIZE > 1048576 )); then
        print "TFT_ASG_WRITE_STEP_SIZE must be an integer from 1024 to 1048576 bytes."
        exit 2
    fi
fi
if [[ -n "$ASG_DATA_RING_SIZE" ]]; then
    if [[ "$ASG_DATA_RING_SIZE" != <-> ]] \
            || (( ASG_DATA_RING_SIZE < 4096 || ASG_DATA_RING_SIZE > 1048576 )); then
        print "TFT_ASG_DATA_RING_SIZE must be an integer from 4096 to 1048576 bytes."
        exit 2
    fi
fi
readonly EFFECTIVE_ASG_WRITE_BUFFER_SIZE="${ASG_WRITE_BUFFER_SIZE:-1048576}"
if [[ -n "$ASG_WRITE_STEP_SIZE" ]] \
        && (( ASG_WRITE_STEP_SIZE > EFFECTIVE_ASG_WRITE_BUFFER_SIZE )); then
    print "TFT_ASG_WRITE_STEP_SIZE cannot exceed TFT_ASG_WRITE_BUFFER_SIZE."
    exit 2
fi
typeset ASG_POWER_OF_TWO_VALUE
for ASG_POWER_OF_TWO_VALUE in "$ASG_WRITE_BUFFER_SIZE" "$ASG_WRITE_STEP_SIZE" "$ASG_DATA_RING_SIZE"; do
    if [[ -n "$ASG_POWER_OF_TWO_VALUE" ]] \
            && (( (ASG_POWER_OF_TWO_VALUE & (ASG_POWER_OF_TWO_VALUE - 1)) != 0 )); then
        print "ASG buffer, step, and ring settings must be powers of two."
        exit 2
    fi
done

typeset LAUNCHER_PID=""
typeset CONFIG_EDITED=""
typeset LOCK_HELD="0"

release_lock() {
    if [[ "$LOCK_HELD" != "1" ]]; then
        return
    fi
    typeset lock_owner=""
    if [[ -f "$LOCK_FILE" ]]; then
        IFS= read -r lock_owner < "$LOCK_FILE" || true
    fi
    if [[ "$lock_owner" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    else
        print "Warning: the AVD lock changed owners; the foreign lock was not removed."
    fi
    LOCK_HELD=0
}

restore_config() {
    if [[ -n "$CONFIG_BACKUP" && -f "$CONFIG_BACKUP" ]]; then
        cp -p "$CONFIG_BACKUP" "$CONFIG"
        rm -f "$CONFIG_BACKUP"
        print "The stable graphics transport configuration was restored."
    fi
    if [[ -n "$CONFIG_EDITED" ]]; then
        rm -f "$CONFIG_EDITED"
    fi
    if [[ -n "$HARDWARE_CONFIG_BACKUP" && -f "$HARDWARE_CONFIG_BACKUP" ]]; then
        cp -p "$HARDWARE_CONFIG_BACKUP" "$HARDWARE_CONFIG"
        rm -f "$HARDWARE_CONFIG_BACKUP"
        print "The generated hardware graphics configuration was restored."
    fi
    release_lock
}

abort_test() {
    if [[ -n "$LAUNCHER_PID" ]] && kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
        kill -TERM "$LAUNCHER_PID" >/dev/null 2>&1 || true
        wait "$LAUNCHER_PID" >/dev/null 2>&1 || true
    fi
    exit 130
}

if [[ ! -f "$CONFIG" ]]; then
    print "The working TFT AVD configuration was not found: $CONFIG"
    exit 1
fi
if [[ ! -f "$HARDWARE_CONFIG" ]]; then
    print "The generated hardware configuration for the working TFT AVD was not found: $HARDWARE_CONFIG"
    exit 1
fi
if [[ ! -x "$LAUNCHER" ]]; then
    print "The executable TFT launcher was not found: $LAUNCHER"
    exit 1
fi

if ! /usr/bin/shlock -f "$LOCK_FILE" -p "$$"; then
    typeset active_lock_pid="unknown"
    if [[ -f "$LOCK_FILE" ]]; then
        IFS= read -r active_lock_pid < "$LOCK_FILE" || true
    fi
    print "Another TFT launcher already owns the AVD lock (PID $active_lock_pid)."
    exit 1
fi
LOCK_HELD=1
export TFT_AVD_LOCK_OWNER_PID="$$"
trap release_lock EXIT

if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The TFT emulator is already running. Close it first."
    exit 1
fi

if [[ -f "$CONFIG_BACKUP" || -f "$HARDWARE_CONFIG_BACKUP" ]]; then
    if [[ -f "$CONFIG_BACKUP" ]]; then
        cp -p "$CONFIG_BACKUP" "$CONFIG"
        rm -f "$CONFIG_BACKUP"
    fi
    if [[ -f "$HARDWARE_CONFIG_BACKUP" ]]; then
        cp -p "$HARDWARE_CONFIG_BACKUP" "$HARDWARE_CONFIG"
        rm -f "$HARDWARE_CONFIG_BACKUP"
    fi
    print "The configuration was restored after an interrupted ASG launch."
fi

readonly BASELINE_TRANSPORT="$(
    sed -n 's/^hw[.]gltransport=//p' "$CONFIG"
)"
if [[ "$BASELINE_TRANSPORT" != "$EXPECTED_BASELINE_TRANSPORT" ]]; then
    print "Refusing to change the graphics transport: expected baseline $EXPECTED_BASELINE_TRANSPORT, found $BASELINE_TRANSPORT."
    print "Check manually: $CONFIG"
    exit 1
fi

CONFIG_EDITED="$(mktemp -t tft-gltransport-config-edited)"
trap restore_config EXIT
trap abort_test INT TERM HUP
cp -p "$CONFIG" "$CONFIG_BACKUP"
cp -p "$HARDWARE_CONFIG" "$HARDWARE_CONFIG_BACKUP"

awk -v transport="$TRANSPORT" \
    -v flush_interval="$DRAW_FLUSH_INTERVAL" \
    -v asg_write_buffer_size="$ASG_WRITE_BUFFER_SIZE" \
    -v asg_write_step_size="$ASG_WRITE_STEP_SIZE" \
    -v asg_data_ring_size="$ASG_DATA_RING_SIZE" '
    BEGIN {
        replaced = 0
        flush_replaced = 0
        asg_write_buffer_replaced = 0
        asg_write_step_replaced = 0
        asg_data_ring_replaced = 0
    }
    /^hw[.]gltransport=/ {
        print "hw.gltransport=" transport
        replaced = 1
        next
    }
    /^hw[.]gltransport[.]drawFlushInterval=/ {
        if (flush_interval != "") {
            print "hw.gltransport.drawFlushInterval=" flush_interval
        } else {
            print
        }
        flush_replaced = 1
        next
    }
    /^hw[.]gltransport[.]asg[.]writeBufferSize=/ {
        if (asg_write_buffer_size != "") {
            print "hw.gltransport.asg.writeBufferSize=" asg_write_buffer_size
        } else {
            print
        }
        asg_write_buffer_replaced = 1
        next
    }
    /^hw[.]gltransport[.]asg[.]writeStepSize=/ {
        if (asg_write_step_size != "") {
            print "hw.gltransport.asg.writeStepSize=" asg_write_step_size
        } else {
            print
        }
        asg_write_step_replaced = 1
        next
    }
    /^hw[.]gltransport[.]asg[.]dataRingSize=/ {
        if (asg_data_ring_size != "") {
            print "hw.gltransport.asg.dataRingSize=" asg_data_ring_size
        } else {
            print
        }
        asg_data_ring_replaced = 1
        next
    }
    { print }
    END {
        if (!replaced) {
            print "hw.gltransport=" transport
        }
        if (flush_interval != "" && !flush_replaced) {
            print "hw.gltransport.drawFlushInterval=" flush_interval
        }
        if (asg_write_buffer_size != "" && !asg_write_buffer_replaced) {
            print "hw.gltransport.asg.writeBufferSize=" asg_write_buffer_size
        }
        if (asg_write_step_size != "" && !asg_write_step_replaced) {
            print "hw.gltransport.asg.writeStepSize=" asg_write_step_size
        }
        if (asg_data_ring_size != "" && !asg_data_ring_replaced) {
            print "hw.gltransport.asg.dataRingSize=" asg_data_ring_size
        }
    }
' "$CONFIG" > "$CONFIG_EDITED"
cp "$CONFIG_EDITED" "$CONFIG"
rm -f "$CONFIG_EDITED"

print "Experiment: graphics transport $TRANSPORT"
if [[ -n "$DRAW_FLUSH_INTERVAL" ]]; then
    print "Experiment: draw flush interval $DRAW_FLUSH_INTERVAL microseconds"
fi
if [[ -n "$ASG_WRITE_BUFFER_SIZE" ]]; then
    print "Experiment: ASG write buffer $ASG_WRITE_BUFFER_SIZE bytes"
fi
if [[ -n "$ASG_WRITE_STEP_SIZE" ]]; then
    print "Experiment: ASG write step $ASG_WRITE_STEP_SIZE bytes"
fi
if [[ -n "$ASG_DATA_RING_SIZE" ]]; then
    print "Experiment: ASG data ring $ASG_DATA_RING_SIZE bytes"
fi
print "Launcher: $LAUNCHER; ADB serial: $SERIAL"
print "After the emulator closes, the original config.ini will be restored automatically."
print "After an unexpected exit, the next launch will restore the baseline from the sidecar backup."

"$LAUNCHER" &
LAUNCHER_PID=$!

typeset -i waited=0
until "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
    if ! kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
        wait "$LAUNCHER_PID"
        exit $?
    fi
    if (( waited >= 90 )); then
        print "ADB did not become available within 90 seconds; ending the experiment."
        kill -TERM "$LAUNCHER_PID" >/dev/null 2>&1 || true
        wait "$LAUNCHER_PID" >/dev/null 2>&1 || true
        exit 1
    fi
    sleep 1
    (( waited += 1 ))
done

print "Active guest graphics transport properties:"
"$ADB" -s "$SERIAL" shell getprop \
    | grep -i 'gltransport' \
    | tr -d '\r' \
    || true
if [[ -n "$ASG_WRITE_BUFFER_SIZE" || -n "$ASG_WRITE_STEP_SIZE" || -n "$ASG_DATA_RING_SIZE" ]]; then
    print "Active generated ASG settings:"
    grep -E '^hw[.]gltransport[.]asg[.](writeBufferSize|writeStepSize|dataRingSize)[[:space:]]*=' \
        "$AVD_HOME/$AVD_NAME.avd/hardware-qemu.ini" \
        || true
fi

typeset -i game_waited=0
until [[ -n "$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')" ]]; do
    if ! kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
        wait "$LAUNCHER_PID"
        exit $?
    fi
    if (( game_waited >= 90 )); then
        print "TFT did not start within 90 seconds; the transport was verified only during Android boot."
        break
    fi
    sleep 1
    (( game_waited += 1 ))
done

readonly GAME_PID="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')"
if [[ -n "$GAME_PID" ]]; then
    print "TFT is running, PID: $GAME_PID"
fi

print "Leaving the experimental emulator open for gameplay testing."
print "Close it with the regular window button; the stable transport will be restored automatically."

wait "$LAUNCHER_PID"
