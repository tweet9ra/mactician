#!/bin/zsh
set -euo pipefail

unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly CANDIDATE_ID="${1:-}"
readonly CANDIDATE_MANIFEST="${TFT_PERFORMANCE_CANDIDATES:-$PROJECT_DIR/scripts/performance-candidates.json}"
readonly TARGET_PHASE="${TFT_TRIAL_TARGET_PHASE:-combat}"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ADB="$(tft_resolve_adb)"
readonly ADB
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly GAME_ACTIVITY="$PACKAGE/com.epicgames.unreal.GameActivity"
readonly CLASSIFIER="${TFT_SCREEN_CLASSIFIER_BINARY:-$PROJECT_DIR/runtime/tft-screen-classifier}"
readonly CLASSIFIER_SOURCE="$PROJECT_DIR/tools/tft-screen-classifier.swift"
readonly CLASSIFIER_BUILD="$PROJECT_DIR/scripts/build-tft-screen-classifier.command"
readonly CAPTURE="$PROJECT_DIR/scripts/capture-frame-pacing.command"
readonly UI_TRANSPORT_PROBE="$PROJECT_DIR/scripts/run-android-ui-transport-probe.command"
readonly GLES_BUFFER_STRESS_PROBE="$PROJECT_DIR/scripts/run-android-gles-buffer-stress.command"
readonly GLES_DRAW_STRESS_PROBE="$PROJECT_DIR/scripts/run-android-gles-draw-stress.command"
readonly LOGIN_HELPER="$PROJECT_DIR/scripts/login-tft-from-keychain.command"
readonly JQ="${TFT_JQ:-$(command -v jq 2>/dev/null || true)}"
readonly RUN_ROOT="${TFT_AUTONOMOUS_TRIAL_ROOT:-$PROJECT_DIR/runtime/measurements/autonomous-trial}"
readonly NAVIGATION_TIMEOUT="${TFT_TRIAL_NAVIGATION_TIMEOUT:-2400}"
readonly UNKNOWN_TIMEOUT="${TFT_TRIAL_UNKNOWN_TIMEOUT:-120}"
readonly MAX_TRIAL_ATTEMPTS="${TFT_TRIAL_MAX_ATTEMPTS:-3}"
readonly MAX_CAPTURE_ATTEMPTS="${TFT_TRIAL_MAX_CAPTURE_ATTEMPTS:-2}"
readonly MEASUREMENT_ROUNDS="${TFT_TRIAL_MEASUREMENT_ROUNDS:-3}"
readonly MEASUREMENT_WINDOW_SECONDS="${TFT_TRIAL_MEASUREMENT_WINDOW_SECONDS:-1}"
readonly UI_TRANSPORT_ROUNDS="${TFT_TRIAL_UI_TRANSPORT_ROUNDS:-0}"
readonly GLES_STRESS_ROUNDS="${TFT_TRIAL_GLES_STRESS_ROUNDS:-0}"
readonly GLES_STRESS_UPDATES="${TFT_TRIAL_GLES_STRESS_UPDATES:-4000}"
readonly GLES_STRESS_BYTES="${TFT_TRIAL_GLES_STRESS_BYTES:-16384}"
readonly GLES_STRESS_SYNC_EVERY="${TFT_TRIAL_GLES_STRESS_SYNC_EVERY:-120}"
readonly GLES_STRESS_BARRIER_EVERY="${TFT_TRIAL_GLES_STRESS_BARRIER_EVERY:-64}"
readonly GLES_STRESS_WARMUP_ROUNDS="${TFT_TRIAL_GLES_STRESS_WARMUP_ROUNDS:-$(( GLES_STRESS_ROUNDS > 8 ? 7 : 1 ))}"
readonly GLES_DRAW_ROUNDS="${TFT_TRIAL_GLES_DRAW_ROUNDS:-0}"
readonly GLES_DRAW_FRAMES="${TFT_TRIAL_GLES_DRAW_FRAMES:-120}"
readonly GLES_DRAW_DRAWS_PER_FRAME="${TFT_TRIAL_GLES_DRAW_DRAWS_PER_FRAME:-256}"
readonly GLES_DRAW_WARMUP_ROUNDS="${TFT_TRIAL_GLES_DRAW_WARMUP_ROUNDS:-$(( GLES_DRAW_ROUNDS > 8 ? 7 : 3 ))}"
readonly AVD_HOME="${TFT_ROOT_AVD_HOME:-$(tft_resolve_avd_home)}"
readonly AVD_NAME="${TFT_AVD_NAME:-TftRootAffinity}"
readonly AVD_DIR="$AVD_HOME/$AVD_NAME.avd"
readonly CONFIG="$AVD_DIR/config.ini"
readonly HARDWARE_CONFIG="$AVD_DIR/hardware-qemu.ini"
readonly ASG_CONFIG_BACKUP="$CONFIG.mactician-asg-backup"
readonly ASG_HARDWARE_BACKUP="$HARDWARE_CONFIG.mactician-asg-backup"
readonly AVD_LOCK="$AVD_DIR/.mactician-avd.lock"
readonly WRAP_PROPERTY="wrap.$PACKAGE"

if [[ -z "$CANDIDATE_ID" ]] \
        || ! print -r -- "$CANDIDATE_ID" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
    print "Usage: ${0:t} CANDIDATE_ID"
    print "Candidate list: $CANDIDATE_MANIFEST"
    exit 2
fi
if [[ ! -x "$JQ" || ! -f "$CANDIDATE_MANIFEST" ]]; then
    print "jq or the candidate manifest was not found: $CANDIDATE_MANIFEST"
    exit 1
fi
if ! "$JQ" -e '.schemaVersion == 1 and (.candidates | type == "array")' \
        "$CANDIDATE_MANIFEST" >/dev/null; then
    print "Invalid performance candidate manifest: $CANDIDATE_MANIFEST"
    exit 2
fi
readonly CANDIDATE_COUNT="$(
    "$JQ" --arg id "$CANDIDATE_ID" '[.candidates[] | select(.id == $id)] | length' \
        "$CANDIDATE_MANIFEST"
)"
if [[ "$CANDIDATE_COUNT" != "1" ]]; then
    print "Candidate ID must occur exactly once: $CANDIDATE_ID"
    exit 2
fi
readonly CANDIDATE_JSON="$(
    "$JQ" -c --arg id "$CANDIDATE_ID" '.candidates[] | select(.id == $id)' \
        "$CANDIDATE_MANIFEST"
)"
readonly CANDIDATE_ANGLE_EXTRA="$(
    print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.env.TFT_ANGLE_EXTRA_FEATURES // ""'
)"
readonly CANDIDATE_ANGLE_DISABLED="$(
    print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.env.TFT_ANGLE_DISABLED_FEATURES // ""'
)"
readonly LAUNCHER_RELATIVE="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.launcher')"
if [[ "$LAUNCHER_RELATIVE" == /* || "$LAUNCHER_RELATIVE" == *..* \
        || ! "$LAUNCHER_RELATIVE" =~ '^[A-Za-z0-9._/-]+$' ]]; then
    print "Unsafe launcher path in candidate manifest: $LAUNCHER_RELATIVE"
    exit 2
fi
readonly LAUNCHER="$PROJECT_DIR/$LAUNCHER_RELATIVE"
readonly VARIANT="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.variant')"
readonly CANDIDATE_DISPLAY="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.display')"
readonly CANDIDATE_DENSITY="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.density')"
readonly PROFILE_STAGE="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.profileStage // ""')"
readonly MINIMUM_TRIAL_SECONDS="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.minimumTrialSeconds // 0')"
readonly PROFILE_RELATIVE="$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.profile // ""')"
typeset PROFILE_PATH=""
typeset -a TARGET_STAGES CANDIDATE_ENV
TARGET_STAGES=("${(@f)$(print -r -- "$CANDIDATE_JSON" | "$JQ" -r '.stages[]')}")
CANDIDATE_ENV=()
while IFS= read -r candidate_assignment; do
    [[ -n "$candidate_assignment" ]] && CANDIDATE_ENV+=("$candidate_assignment")
done < <(
    print -r -- "$CANDIDATE_JSON" \
        | "$JQ" -r '.env // {} | to_entries[] | "\(.key)=\(.value)"'
)
if [[ -n "$PROFILE_RELATIVE" ]]; then
    if [[ "$PROFILE_RELATIVE" == /* || "$PROFILE_RELATIVE" == *..* \
            || ! "$PROFILE_RELATIVE" =~ '^[A-Za-z0-9._/-]+$' ]]; then
        print "Unsafe profile path in candidate manifest: $PROFILE_RELATIVE"
        exit 2
    fi
    PROFILE_PATH="$PROJECT_DIR/$PROFILE_RELATIVE"
    if [[ ! -f "$PROFILE_PATH" ]]; then
        print "Candidate profile was not found: $PROFILE_PATH"
        exit 1
    fi
    CANDIDATE_ENV+=(
        "TFT_ANGLE_OPENGL_PROFILE=$PROFILE_PATH"
        "TFT_ANGLE_OPENGL_PROFILE_SHA256=$(shasum -a 256 "$PROFILE_PATH" | awk '{ print $1 }')"
        "TFT_PROFILE_PATH=$PROFILE_PATH"
    )
fi
if (( ${#TARGET_STAGES} == 0 )); then
    print "Candidate $CANDIDATE_ID does not declare target stages."
    exit 2
fi
for candidate_assignment in "${CANDIDATE_ENV[@]}"; do
    if [[ -n "$candidate_assignment" ]] \
            && ! print -r -- "$candidate_assignment" \
                | grep -Eq '^[A-Z][A-Z0-9_]*=[-A-Za-z0-9_./:]+$'; then
        print "Unsafe candidate environment assignment: $candidate_assignment"
        exit 2
    fi
done
if ! print -r -- "$VARIANT" | grep -Eq '^[a-z0-9][a-z0-9_-]*$'; then
    print "Invalid variant in candidate manifest: $VARIANT"
    exit 2
fi
if ! print -r -- "$CANDIDATE_DISPLAY" | grep -Eq '^(2560x1440|2880x1620|3200x1800|3840x2160)$' \
        || [[ "$CANDIDATE_DENSITY" != <-> ]] \
        || (( CANDIDATE_DENSITY < 120 || CANDIDATE_DENSITY > 640 )); then
    print "Invalid candidate display/density: $CANDIDATE_DISPLAY/$CANDIDATE_DENSITY"
    exit 2
fi

recover_interrupted_asg_state() {
    local receipt="$1"
    local lock_owner=""

    if [[ ! -e "$ASG_CONFIG_BACKUP" && ! -e "$ASG_HARDWARE_BACKUP" ]]; then
        if [[ -e "$AVD_LOCK" ]]; then
            IFS= read -r lock_owner < "$AVD_LOCK" || true
            if [[ "$lock_owner" != <-> ]] || kill -0 "$lock_owner" >/dev/null 2>&1; then
                print "recovered=no\nreason=active_or_invalid_lock\nlock_owner=${lock_owner:-unknown}" > "$receipt"
                return 1
            fi
            rm -f "$AVD_LOCK"
            print "recovered=yes\nreason=stale_lock_only\nlock_owner=$lock_owner" > "$receipt"
        else
            print "recovered=not_needed" > "$receipt"
        fi
        return 0
    fi

    if [[ ! -f "$ASG_CONFIG_BACKUP" || ! -f "$ASG_HARDWARE_BACKUP" ]]; then
        print "recovered=no\nreason=incomplete_backup_pair" > "$receipt"
        return 1
    fi
    if [[ -e "$AVD_LOCK" ]]; then
        IFS= read -r lock_owner < "$AVD_LOCK" || true
        if [[ "$lock_owner" != <-> ]] || kill -0 "$lock_owner" >/dev/null 2>&1; then
            print "recovered=no\nreason=active_or_invalid_lock\nlock_owner=${lock_owner:-unknown}" > "$receipt"
            return 1
        fi
    fi

    local backup_transport config_backup_sha hardware_backup_sha
    backup_transport="$(sed -n 's/^hw[.]gltransport=//p' "$ASG_CONFIG_BACKUP")"
    if [[ "$backup_transport" != "pipe" ]]; then
        print "recovered=no\nreason=unexpected_backup_transport\ntransport=${backup_transport:-unknown}" > "$receipt"
        return 1
    fi
    config_backup_sha="$(shasum -a 256 "$ASG_CONFIG_BACKUP" | awk '{ print $1 }')"
    hardware_backup_sha="$(shasum -a 256 "$ASG_HARDWARE_BACKUP" | awk '{ print $1 }')"
    cp -p "$ASG_CONFIG_BACKUP" "$CONFIG"
    cp -p "$ASG_HARDWARE_BACKUP" "$HARDWARE_CONFIG"
    if [[ "$(shasum -a 256 "$CONFIG" | awk '{ print $1 }')" != "$config_backup_sha" \
            || "$(shasum -a 256 "$HARDWARE_CONFIG" | awk '{ print $1 }')" != "$hardware_backup_sha" ]]; then
        print "recovered=no\nreason=restore_sha_mismatch" > "$receipt"
        return 1
    fi
    rm -f "$ASG_CONFIG_BACKUP" "$ASG_HARDWARE_BACKUP"
    [[ -e "$AVD_LOCK" ]] && rm -f "$AVD_LOCK"
    {
        print "recovered=yes"
        print "reason=verified_backup_restore"
        print "config_sha256=$config_backup_sha"
        print "hardware_config_sha256=$hardware_backup_sha"
        print "lock_owner=${lock_owner:-none}"
    } > "$receipt"
}

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
typeset target_stage
for target_stage in "${TARGET_STAGES[@]}"; do
    if ! print -r -- "$target_stage" | grep -Eq '^[1-9]-(1[0-9]|[1-9])$'; then
        print "Target stage must use a value such as 1-2: $target_stage"
        exit 2
    fi
done
if [[ "$TARGET_PHASE" != "combat" ]]; then
    print "The autonomous Trial benchmark currently accepts only TFT_TRIAL_TARGET_PHASE=combat."
    exit 2
fi
if [[ "$NAVIGATION_TIMEOUT" != <-> ]] || (( NAVIGATION_TIMEOUT < 60 || NAVIGATION_TIMEOUT > 7200 )); then
    print "TFT_TRIAL_NAVIGATION_TIMEOUT must be from 60 through 7200 seconds."
    exit 2
fi
if [[ -n "$PROFILE_STAGE" ]] \
        && ! print -r -- "$PROFILE_STAGE" | grep -Eq '^[1-9]-(1[0-9]|[1-9])$'; then
    print "profileStage must use a value such as 1-8: $PROFILE_STAGE"
    exit 2
fi
if [[ "$MINIMUM_TRIAL_SECONDS" != <-> ]] \
        || (( MINIMUM_TRIAL_SECONDS < 0 || MINIMUM_TRIAL_SECONDS > 3600 )); then
    print "minimumTrialSeconds must be from 0 through 3600."
    exit 2
fi
if [[ "$UI_TRANSPORT_ROUNDS" != <-> ]] \
        || (( UI_TRANSPORT_ROUNDS < 0 || UI_TRANSPORT_ROUNDS > 30 )); then
    print "TFT_TRIAL_UI_TRANSPORT_ROUNDS must be from 0 through 30."
    exit 2
fi
for stress_name stress_value stress_minimum stress_maximum in \
        rounds "$GLES_STRESS_ROUNDS" 0 30 \
        updates "$GLES_STRESS_UPDATES" 1 100000 \
        bytes "$GLES_STRESS_BYTES" 256 1048576 \
        sync-every "$GLES_STRESS_SYNC_EVERY" 1 100000 \
        barrier-every "$GLES_STRESS_BARRIER_EVERY" 0 100000 \
        warmup-rounds "$GLES_STRESS_WARMUP_ROUNDS" 1 29; do
    if [[ "$stress_value" != <-> ]] \
            || (( stress_value < stress_minimum || stress_value > stress_maximum )); then
        print "TFT_TRIAL_GLES_STRESS_${(U)stress_name//-/_} must be from $stress_minimum through $stress_maximum."
        exit 2
    fi
done
if (( GLES_STRESS_ROUNDS == 1 )); then
    print "TFT_TRIAL_GLES_STRESS_ROUNDS must be 0 or at least 2."
    exit 2
fi
if (( GLES_STRESS_ROUNDS > 0 && GLES_STRESS_WARMUP_ROUNDS >= GLES_STRESS_ROUNDS )); then
    print "TFT_TRIAL_GLES_STRESS_WARMUP_ROUNDS must be less than TFT_TRIAL_GLES_STRESS_ROUNDS."
    exit 2
fi
for draw_name draw_value draw_minimum draw_maximum in \
        rounds "$GLES_DRAW_ROUNDS" 0 30 \
        frames "$GLES_DRAW_FRAMES" 1 2000 \
        draws-per-frame "$GLES_DRAW_DRAWS_PER_FRAME" 1 2048 \
        warmup-rounds "$GLES_DRAW_WARMUP_ROUNDS" 1 29; do
    if [[ "$draw_value" != <-> ]] \
            || (( draw_value < draw_minimum || draw_value > draw_maximum )); then
        print "TFT_TRIAL_GLES_DRAW_${(U)draw_name//-/_} must be from $draw_minimum through $draw_maximum."
        exit 2
    fi
done
if (( GLES_DRAW_ROUNDS == 1 )); then
    print "TFT_TRIAL_GLES_DRAW_ROUNDS must be 0 or at least 2."
    exit 2
fi
if (( GLES_DRAW_ROUNDS > 0 && GLES_DRAW_WARMUP_ROUNDS >= GLES_DRAW_ROUNDS )); then
    print "TFT_TRIAL_GLES_DRAW_WARMUP_ROUNDS must be less than TFT_TRIAL_GLES_DRAW_ROUNDS."
    exit 2
fi
if [[ "$UNKNOWN_TIMEOUT" != <-> ]] || (( UNKNOWN_TIMEOUT < 10 || UNKNOWN_TIMEOUT > 300 )); then
    print "TFT_TRIAL_UNKNOWN_TIMEOUT must be from 10 through 300 seconds."
    exit 2
fi
if ! print -r -- "$AVD_NAME" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    print "TFT_AVD_NAME contains unsupported characters: $AVD_NAME"
    exit 2
fi
if [[ "$MAX_TRIAL_ATTEMPTS" != <-> ]] \
        || (( MAX_TRIAL_ATTEMPTS < 1 || MAX_TRIAL_ATTEMPTS > 5 )); then
    print "TFT_TRIAL_MAX_ATTEMPTS must be from 1 through 5."
    exit 2
fi
if [[ "$MAX_CAPTURE_ATTEMPTS" != <-> ]] \
        || (( MAX_CAPTURE_ATTEMPTS < 1 || MAX_CAPTURE_ATTEMPTS > 3 )); then
    print "TFT_TRIAL_MAX_CAPTURE_ATTEMPTS must be from 1 through 3."
    exit 2
fi
for required_file in "$ADB" "$LAUNCHER" "$CLASSIFIER_BUILD" "$CAPTURE" "$LOGIN_HELPER" \
        "$JQ" "$CONFIG" "$HARDWARE_CONFIG" "$CANDIDATE_MANIFEST"; do
    if [[ ! -e "$required_file" ]]; then
        print "Required file not found: $required_file"
        exit 1
    fi
done
if (( UI_TRANSPORT_ROUNDS > 0 )) && [[ ! -x "$UI_TRANSPORT_PROBE" ]]; then
    print "The Android UI transport probe is unavailable: $UI_TRANSPORT_PROBE"
    exit 1
fi
if (( GLES_STRESS_ROUNDS > 0 )) && [[ ! -x "$GLES_BUFFER_STRESS_PROBE" ]]; then
    print "The Android GLES buffer stress probe is unavailable: $GLES_BUFFER_STRESS_PROBE"
    exit 1
fi
if (( GLES_DRAW_ROUNDS > 0 )) && [[ ! -x "$GLES_DRAW_STRESS_PROBE" ]]; then
    print "The Android GLES draw stress probe is unavailable: $GLES_DRAW_STRESS_PROBE"
    exit 1
fi

readonly UTC_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
readonly RUN_DIR="$RUN_ROOT/${UTC_STAMP}__${CANDIDATE_ID}__$$"
readonly MEASUREMENT_ROOT="$RUN_DIR/measurements"
mkdir -p "$RUN_DIR" "$MEASUREMENT_ROOT"

if [[ ! -x "$CLASSIFIER" || "$CLASSIFIER_SOURCE" -nt "$CLASSIFIER" ]]; then
    TFT_SCREEN_CLASSIFIER_BINARY="$CLASSIFIER" \
        "$CLASSIFIER_BUILD" > "$RUN_DIR/classifier-build.txt"
fi
if [[ ! -x "$CLASSIFIER" ]]; then
    print "Could not build the screen classifier: $CLASSIFIER"
    exit 1
fi

if ! recover_interrupted_asg_state "$RUN_DIR/preflight-recovery.txt"; then
    print "Could not safely restore state from an interrupted ASG launch: $RUN_DIR/preflight-recovery.txt"
    exit 1
fi
if grep -Fq 'recovered=yes' "$RUN_DIR/preflight-recovery.txt"; then
    print "Restored the verified state after an interrupted ASG launch."
fi

readonly CONFIG_SHA_BEFORE="$(shasum -a 256 "$CONFIG" | awk '{ print $1 }')"
readonly HARDWARE_SHA_BEFORE="$(shasum -a 256 "$HARDWARE_CONFIG" | awk '{ print $1 }')"

unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export TFT_SERIAL="$SERIAL"
export TFT_ROOT_AVD_HOME="$AVD_HOME"
export TFT_AVD_HOME="$AVD_HOME"
export TFT_AVD_NAME="$AVD_NAME"

"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null
if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "An emulator is already running on $SERIAL; the autonomous cold-boot test refused to continue."
    exit 1
fi

{
    print "utc=$UTC_STAMP"
    print "candidate=$CANDIDATE_ID"
    print "variant=$VARIANT"
    print "target_stages=${(j:,:)TARGET_STAGES}"
    print "target_phase=$TARGET_PHASE"
    print "display=$CANDIDATE_DISPLAY"
    print "density=$CANDIDATE_DENSITY"
    print "serial=$SERIAL"
    print "adb_server_port=$ADB_SERVER_PORT"
    print "launcher=$LAUNCHER"
    print "candidate_manifest=$CANDIDATE_MANIFEST"
    print "candidate_json=$CANDIDATE_JSON"
    print "profile_stage=${PROFILE_STAGE:-none}"
    print "profile=${PROFILE_PATH:-launcher_default}"
    print "minimum_trial_seconds=$MINIMUM_TRIAL_SECONDS"
    print "ui_transport_rounds=$UI_TRANSPORT_ROUNDS"
    print "gles_stress_rounds=$GLES_STRESS_ROUNDS"
    print "gles_stress_updates=$GLES_STRESS_UPDATES"
    print "gles_stress_bytes=$GLES_STRESS_BYTES"
    print "gles_stress_sync_every=$GLES_STRESS_SYNC_EVERY"
    print "gles_stress_barrier_every=$GLES_STRESS_BARRIER_EVERY"
    print "gles_stress_warmup_rounds=$GLES_STRESS_WARMUP_ROUNDS"
    print "gles_draw_rounds=$GLES_DRAW_ROUNDS"
    print "gles_draw_frames=$GLES_DRAW_FRAMES"
    print "gles_draw_draws_per_frame=$GLES_DRAW_DRAWS_PER_FRAME"
    print "gles_draw_warmup_rounds=$GLES_DRAW_WARMUP_ROUNDS"
    print "max_trial_attempts=$MAX_TRIAL_ATTEMPTS"
    print "max_capture_attempts=$MAX_CAPTURE_ATTEMPTS"
    print "config_sha256_before=$CONFIG_SHA_BEFORE"
    print "hardware_config_sha256_before=$HARDWARE_SHA_BEFORE"
} > "$RUN_DIR/manifest.txt"

typeset LAUNCHER_PID=""
typeset CLEANING_UP=0
typeset BENCHMARK_SUCCEEDED=0
typeset TRANSPORT_SCREEN_SUCCEEDED=0
typeset GLES_STRESS_SUCCEEDED=0
typeset GLES_DRAW_SUCCEEDED=0
typeset MEASUREMENTS_COMPLETE=0
typeset REQUIRE_VERIFIED_WRAP_RESTORE=0

cleanup() {
    typeset original_status=$?
    if [[ "$CLEANING_UP" == "1" ]]; then
        return
    fi
    CLEANING_UP=1
    trap - EXIT
    trap '' INT TERM HUP
    set +e

    typeset launcher_wait_status="not_started"
    typeset launcher_stopped=yes
    if [[ -n "$LAUNCHER_PID" ]]; then
        if kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
            kill -TERM "$LAUNCHER_PID" >/dev/null 2>&1
            integer cleanup_waited=0
            while kill -0 "$LAUNCHER_PID" >/dev/null 2>&1 && (( cleanup_waited < 120 )); do
                sleep 1
                (( cleanup_waited += 1 ))
            done
        fi
        if kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
            launcher_stopped=no
            launcher_wait_status="timeout"
        else
            wait "$LAUNCHER_PID"
            launcher_wait_status="$?"
        fi
    fi

    typeset device_stopped=yes
    if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        device_stopped=no
    fi
    typeset cleanup_recovery=not_needed
    if [[ "$device_stopped" == yes \
            && ( -e "$ASG_CONFIG_BACKUP" || -e "$ASG_HARDWARE_BACKUP" || -e "$AVD_LOCK" ) ]]; then
        if recover_interrupted_asg_state "$RUN_DIR/cleanup-recovery.txt"; then
            cleanup_recovery=success
        else
            cleanup_recovery=failed
        fi
    fi
    typeset config_sha_after hardware_sha_after
    config_sha_after="$(shasum -a 256 "$CONFIG" 2>/dev/null | awk '{ print $1 }')"
    hardware_sha_after="$(shasum -a 256 "$HARDWARE_CONFIG" 2>/dev/null | awk '{ print $1 }')"
    typeset config_restored=no hardware_restored=no backups_absent=yes lock_absent=yes
    typeset wrap_restore_verified=no
    [[ "$config_sha_after" == "$CONFIG_SHA_BEFORE" ]] && config_restored=yes
    [[ "$hardware_sha_after" == "$HARDWARE_SHA_BEFORE" ]] && hardware_restored=yes
    [[ -e "$ASG_CONFIG_BACKUP" || -e "$ASG_HARDWARE_BACKUP" ]] && backups_absent=no
    [[ -e "$AVD_LOCK" ]] && lock_absent=no
    if grep -Fq "The original Android process wrapper was restored and verified." \
            "$RUN_DIR/launcher.log" 2>/dev/null; then
        wrap_restore_verified=yes
    fi

    {
        print "launcher_stopped=$launcher_stopped"
        print "launcher_wait_status=$launcher_wait_status"
        print "device_stopped=$device_stopped"
        print "config_restored=$config_restored"
        print "hardware_config_restored=$hardware_restored"
        print "asg_backups_absent=$backups_absent"
        print "avd_lock_absent=$lock_absent"
        print "wrap_restore_verified=$wrap_restore_verified"
        print "cleanup_recovery=$cleanup_recovery"
        print "config_sha256_after=$config_sha_after"
        print "hardware_config_sha256_after=$hardware_sha_after"
    } > "$RUN_DIR/cleanup.txt"

    typeset rollback_verified=false rollback_reason=cleanup_incomplete
    if [[ "$launcher_stopped" == yes && "$device_stopped" == yes \
            && "$config_restored" == yes && "$hardware_restored" == yes \
            && "$backups_absent" == yes && "$lock_absent" == yes \
            && ( "$REQUIRE_VERIFIED_WRAP_RESTORE" != "1" || "$wrap_restore_verified" == yes ) ]]; then
        rollback_verified=true
        rollback_reason=verified_launcher_and_avd_restore
    fi
    typeset summary_json summary_json_next
    while IFS= read -r summary_json; do
        [[ -n "$summary_json" && -f "$summary_json" ]] || continue
        summary_json_next="$summary_json.next.$$"
        "$JQ" \
            --argjson verified "$rollback_verified" \
            --arg reason "$rollback_reason" \
            '.rollback = {verified: $verified, reason: $reason}' \
            "$summary_json" > "$summary_json_next" \
            && mv -f "$summary_json_next" "$summary_json"
    done < <(
        find "$RUN_DIR" -type f \
            \( -name summary.json -o -name 'result-summary-*.json' \) \
            -print 2>/dev/null | sort
    )

    "$JQ" -n \
        --arg candidate "$CANDIDATE_ID" \
        --arg variant "$VARIANT" \
        --arg run_dir "$RUN_DIR" \
        --argjson benchmark_succeeded "$([[ "$BENCHMARK_SUCCEEDED" == 1 ]] && print true || print false)" \
        --argjson transport_screen_succeeded "$([[ "$TRANSPORT_SCREEN_SUCCEEDED" == 1 ]] && print true || print false)" \
        --argjson gles_stress_succeeded "$([[ "$GLES_STRESS_SUCCEEDED" == 1 ]] && print true || print false)" \
        --argjson gles_draw_succeeded "$([[ "$GLES_DRAW_SUCCEEDED" == 1 ]] && print true || print false)" \
        --argjson rollback_verified "$rollback_verified" \
        --arg rollback_reason "$rollback_reason" \
        --arg launcher_stopped "$launcher_stopped" \
        --arg device_stopped "$device_stopped" \
        '{
            schema_version: 1,
            candidate: $candidate,
            variant: $variant,
            run_dir: $run_dir,
            benchmark_succeeded: $benchmark_succeeded,
            transport_screen_succeeded: $transport_screen_succeeded,
            gles_stress_succeeded: $gles_stress_succeeded,
            gles_draw_succeeded: $gles_draw_succeeded,
            rollback: {verified: $rollback_verified, reason: $rollback_reason},
            launcher_stopped: ($launcher_stopped == "yes"),
            device_stopped: ($device_stopped == "yes")
        }' > "$RUN_DIR/run-result.json.next" \
        && mv -f "$RUN_DIR/run-result.json.next" "$RUN_DIR/run-result.json"

    if [[ "$launcher_stopped" != yes || "$device_stopped" != yes \
            || "$config_restored" != yes || "$hardware_restored" != yes \
            || "$backups_absent" != yes || "$lock_absent" != yes \
            || ( "$REQUIRE_VERIFIED_WRAP_RESTORE" == "1" && "$wrap_restore_verified" != yes ) ]]; then
        print "The autonomous launch exited, but rollback did not pass every check: $RUN_DIR/cleanup.txt"
        if (( original_status == 0 )); then
            original_status=4
        fi
    fi
    exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

print "Starting autonomous Trial benchmark: $CANDIDATE_ID → ${(j:,:)TARGET_STAGES} $TARGET_PHASE."
typeset -a LAUNCH_ENV
LAUNCH_ENV=(
    "${CANDIDATE_ENV[@]}"
    "TFT_DISPLAY_SIZE=$CANDIDATE_DISPLAY"
    "TFT_DISPLAY_DENSITY=$CANDIDATE_DENSITY"
    "TFT_INPUT_BRIDGE_ENABLED=0"
)
/usr/bin/env "${LAUNCH_ENV[@]}" "$LAUNCHER" > "$RUN_DIR/launcher.log" 2>&1 &
LAUNCHER_PID=$!

integer waited=0
until "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
    if ! kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
        wait "$LAUNCHER_PID" || true
        LAUNCHER_PID=""
        print "The launcher exited before ADB became available. Log: $RUN_DIR/launcher.log"
        exit 1
    fi
    if (( waited >= 120 )); then
        print "ADB did not become available within 120 seconds. Log: $RUN_DIR/launcher.log"
        exit 1
    fi
    sleep 1
    (( waited += 1 ))
done

# ADB appears before the launcher performs `adb root`; that restart briefly
# disconnects the serial. Do not start the state machine until all guest
# overlays and process-environment checks have completed.
integer launcher_ready_waited=0
until grep -Fq "TFT is running:" "$RUN_DIR/launcher.log" 2>/dev/null; do
    if ! kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
        wait "$LAUNCHER_PID" || true
        LAUNCHER_PID=""
        print "The launcher exited before TFT became ready. Log: $RUN_DIR/launcher.log"
        exit 1
    fi
    if (( launcher_ready_waited >= 180 )); then
        print "The launcher did not confirm TFT readiness within 180 seconds. Log: $RUN_DIR/launcher.log"
        exit 1
    fi
    sleep 1
    (( launcher_ready_waited += 1 ))
done
if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The launcher reported readiness, but ADB is unavailable. Log: $RUN_DIR/launcher.log"
    exit 1
fi
print "Launcher ready: guest overlay and submission mode verified."

readonly DISPLAY_REPORT="$("$ADB" -s "$SERIAL" shell wm size 2>/dev/null | tr -d '\r')"
readonly DENSITY_REPORT="$("$ADB" -s "$SERIAL" shell wm density 2>/dev/null | tr -d '\r')"
if [[ "$DISPLAY_REPORT" != *"$CANDIDATE_DISPLAY"* ]] \
        || [[ "$DENSITY_REPORT" != *"$CANDIDATE_DENSITY"* ]]; then
    print "Candidate display was not applied: $DISPLAY_REPORT / $DENSITY_REPORT"
    exit 1
fi

readonly ANGLE_BASE_FEATURES="exposeNonConformantExtensionsAndVersions:exposeES32ForTesting"
typeset EXPECTED_ANGLE_ENABLED="$ANGLE_BASE_FEATURES"
[[ -n "$CANDIDATE_ANGLE_EXTRA" ]] \
    && EXPECTED_ANGLE_ENABLED+=":$CANDIDATE_ANGLE_EXTRA"

if (( GLES_STRESS_ROUNDS > 0 )); then
    REQUIRE_VERIFIED_WRAP_RESTORE=1
    set +e
    TFT_GLES_STRESS_ROOT="$MEASUREMENT_ROOT/gles-buffer-stress" \
    TFT_GLES_STRESS_EXPECTED_GRAPHICS_PROFILE=osft \
    TFT_GLES_STRESS_EXPECTED_ANGLE_ENABLED="$EXPECTED_ANGLE_ENABLED" \
    TFT_GLES_STRESS_EXPECTED_ANGLE_DISABLED="$CANDIDATE_ANGLE_DISABLED" \
    TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT" \
    TFT_SERIAL="$SERIAL" \
        "$GLES_BUFFER_STRESS_PROBE" \
        "$CANDIDATE_ID" "$GLES_STRESS_ROUNDS" "$GLES_STRESS_UPDATES" \
        "$GLES_STRESS_BYTES" "$GLES_STRESS_SYNC_EVERY" "$GLES_STRESS_BARRIER_EVERY" \
        "$GLES_STRESS_WARMUP_ROUNDS" \
        > "$RUN_DIR/gles-buffer-stress.log" 2>&1
    gles_stress_status=$?
    set -e
    if (( gles_stress_status != 0 )); then
        print "The attested guest GLES buffer stress probe failed: $RUN_DIR/gles-buffer-stress.log"
        exit "$gles_stress_status"
    fi
    GLES_STRESS_SUCCEEDED=1
    MEASUREMENTS_COMPLETE=1
    print "Attested guest GLES buffer stress probe completed for $CANDIDATE_ID."
fi

if (( GLES_DRAW_ROUNDS > 0 )); then
    REQUIRE_VERIFIED_WRAP_RESTORE=1
    set +e
    TFT_GLES_DRAW_ROOT="$MEASUREMENT_ROOT/gles-draw-stress" \
    TFT_GLES_DRAW_EXPECTED_GRAPHICS_PROFILE=osft \
    TFT_GLES_DRAW_EXPECTED_ANGLE_ENABLED="$EXPECTED_ANGLE_ENABLED" \
    TFT_GLES_DRAW_EXPECTED_ANGLE_DISABLED="$CANDIDATE_ANGLE_DISABLED" \
    TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT" \
    TFT_SERIAL="$SERIAL" \
        "$GLES_DRAW_STRESS_PROBE" \
        "$CANDIDATE_ID" "$GLES_DRAW_ROUNDS" "$GLES_DRAW_FRAMES" \
        "$GLES_DRAW_DRAWS_PER_FRAME" "$GLES_DRAW_WARMUP_ROUNDS" \
        > "$RUN_DIR/gles-draw-stress.log" 2>&1
    gles_draw_status=$?
    set -e
    if (( gles_draw_status != 0 )); then
        print "The attested guest GLES draw stress probe failed: $RUN_DIR/gles-draw-stress.log"
        exit "$gles_draw_status"
    fi
    GLES_DRAW_SUCCEEDED=1
    MEASUREMENTS_COMPLETE=1
    print "Attested guest GLES draw stress probe completed for $CANDIDATE_ID."
fi

if (( UI_TRANSPORT_ROUNDS > 0 )); then
    REQUIRE_VERIFIED_WRAP_RESTORE=1
    set +e
    TFT_UI_TRANSPORT_ROOT="$MEASUREMENT_ROOT/ui-transport" \
    TFT_UI_TRANSPORT_EXPECTED_GRAPHICS_PROFILE=osft \
    TFT_UI_TRANSPORT_EXPECTED_ANGLE_ENABLED="$EXPECTED_ANGLE_ENABLED" \
    TFT_UI_TRANSPORT_EXPECTED_ANGLE_DISABLED="$CANDIDATE_ANGLE_DISABLED" \
    TFT_UI_TRANSPORT_EXPECT_ANGLE_MAPPED=1 \
    TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT" \
    TFT_SERIAL="$SERIAL" \
        "$UI_TRANSPORT_PROBE" "$CANDIDATE_ID" "$UI_TRANSPORT_ROUNDS" \
        > "$RUN_DIR/ui-transport.log" 2>&1
    transport_status=$?
    set -e
    if (( transport_status != 0 )); then
        print "The attested Android UI transport screen failed: $RUN_DIR/ui-transport.log"
        exit "$transport_status"
    fi
    TRANSPORT_SCREEN_SUCCEEDED=1
    MEASUREMENTS_COMPLETE=1
    print "Attested Android UI transport screen completed for $CANDIDATE_ID."
    exit 0
fi
if (( GLES_STRESS_ROUNDS > 0 || GLES_DRAW_ROUNDS > 0 )); then
    exit 0
fi

readonly DISPLAY_WIDTH="${CANDIDATE_DISPLAY%x*}"
readonly DISPLAY_HEIGHT="${CANDIDATE_DISPLAY#*x}"
# The game's Slate coordinates use a 2048x1152 reference while ADB input uses
# a viewport 5/4 larger than the physical SurfaceView. The old hard-coded
# 3200x1800 happened to be correct only for 2560x1440; derive it so the same
# normalized location remains valid at 1620p, 1800p and 2160p.
readonly INPUT_WIDTH=$(( DISPLAY_WIDTH * 5 / 4 ))
readonly INPUT_HEIGHT=$(( DISPLAY_HEIGHT * 5 / 4 ))

scale_x() {
    awk -v value="$1" -v width="$DISPLAY_WIDTH" \
        'BEGIN { printf "%d", value * width / 2560 + 0.5 }'
}

scale_y() {
    awk -v value="$1" -v height="$DISPLAY_HEIGHT" \
        'BEGIN { printf "%d", value * height / 1440 + 0.5 }'
}

game_scale_x() {
    awk -v value="$1" -v width="$INPUT_WIDTH" \
        'BEGIN { printf "%d", value * width / 2560 + 0.5 }'
}

game_scale_y() {
    awk -v value="$1" -v height="$INPUT_HEIGHT" \
        'BEGIN { printf "%d", value * height / 1440 + 0.5 }'
}

density_scale() {
    awk -v value="$1" -v density="$CANDIDATE_DENSITY" \
        'BEGIN { printf "%d", value * 416 / density + 0.5 }'
}

shop_card_x() {
    # The Trial shop is anchored to the fixed Slate right edge near x=2040;
    # card widths shrink as Android density rises.
    awk -v value="$1" -v density="$CANDIDATE_DENSITY" \
        'BEGIN { printf "%d", 2040 + (value - 2040) * 416 / density + 0.5 }'
}

tap_reference() {
    "$ADB" -s "$SERIAL" shell input tap "$(scale_x "$1")" "$(scale_y "$2")" >/dev/null
}

swipe_reference() {
    "$ADB" -s "$SERIAL" shell input swipe \
        "$(scale_x "$1")" "$(scale_y "$2")" \
        "$(scale_x "$3")" "$(scale_y "$4")" "$5" >/dev/null
}

tap_game_reference() {
    "$ADB" -s "$SERIAL" shell input tap \
        "$(game_scale_x "$1")" "$(game_scale_y "$2")" >/dev/null
}

swipe_game_reference() {
    "$ADB" -s "$SERIAL" shell input swipe \
        "$(game_scale_x "$1")" "$(game_scale_y "$2")" \
        "$(game_scale_x "$3")" "$(game_scale_y "$4")" "$5" >/dev/null
}

typeset -A ACTION_COUNT ACTION_LAST
typeset LAST_STATE=""
typeset LAST_SEMANTIC_STATE=""
typeset CURRENT_STATE="unknown"
typeset CURRENT_STAGE=""
typeset CURRENT_PHASE=""
typeset CURRENT_REASON=""
typeset CURRENT_EVIDENCE=""
typeset CURRENT_SHOP_OPEN=0
typeset CURRENT_FIGHT_VISIBLE=0
typeset CURRENT_SHOP_COSTS_JSON="[]"
typeset CURRENT_BOARD_UNITS=-1
typeset CURRENT_BOARD_CAPACITY=-1
typeset UNKNOWN_SINCE=""
typeset -A PREPARED_STAGE
typeset -A COMBAT_SEEN_STAGE LOSS_RECOVERY_COUNT
typeset -A SHOP_HANDLED_STAGE SHOP_OPEN_REQUESTED_STAGE
typeset -A CAPTURE_ATTEMPT
integer BENCH_UNITS_AVAILABLE=0
integer LAST_BOARD_SWIPES=0
integer LAST_ITEM_SWIPES=0
integer ITEMS_EQUIPPED=0
integer BOARD_PLACEMENTS_DONE=0
integer TRIAL_ATTEMPTS_STARTED=0
typeset LOGIN_HELPER_ATTEMPTS=0
typeset LOGIN_HELPER_SUBMITTED=0
typeset LOGIN_HELPER_LAST=0
typeset top_activity=""
typeset unknown_top_activity=""
typeset helper_status=0
typeset retry_action_key=""
typeset recovery_stage=""
typeset gameplay_action_key=""
typeset measurement_summary=""
typeset measurement_summary_json=""
typeset -A CAPTURED_STAGE
typeset -a MEASUREMENT_SUMMARIES_JSON
typeset PROFILE_CAPTURED=0
typeset TRIAL_STARTED_SECONDS=""
typeset FRESH_TRIAL_CONFIRMED=0
typeset RESETTING_STALE_TRIAL=0
typeset RETRY_CANDIDATE_STAGE=""
integer RETRY_CANDIDATE_SINCE=0
integer iteration=0
integer navigation_started=$SECONDS

take_state_screenshot() {
    (( iteration += 1 ))
    "$ADB" -s "$SERIAL" exec-out screencap -p > "$RUN_DIR/current.png"
    if ! "$CLASSIFIER" "$RUN_DIR/current.png" \
            > "$RUN_DIR/current.json" 2> "$RUN_DIR/current-classifier.stderr"; then
        cp "$RUN_DIR/current.png" "$RUN_DIR/classifier-failure-${iteration}.png"
        print "The screen classifier failed. Artifacts: $RUN_DIR"
        return 1
    fi
    CURRENT_STATE="$("$JQ" -r '.state // "unknown"' "$RUN_DIR/current.json")"
    CURRENT_STAGE="$("$JQ" -r '.stage // ""' "$RUN_DIR/current.json")"
    CURRENT_PHASE="$("$JQ" -r '.phase // ""' "$RUN_DIR/current.json")"
    CURRENT_REASON="$("$JQ" -r '.reason // ""' "$RUN_DIR/current.json")"
    CURRENT_EVIDENCE="$("$JQ" -r '[.evidence[]?] | join(" | ")' "$RUN_DIR/current.json")"
    CURRENT_SHOP_OPEN="$("$JQ" -r 'if .shop_open then 1 else 0 end' "$RUN_DIR/current.json")"
    CURRENT_FIGHT_VISIBLE="$("$JQ" -r 'if .fight_button_visible then 1 else 0 end' "$RUN_DIR/current.json")"
    CURRENT_SHOP_COSTS_JSON="$("$JQ" -c '.shop_costs // []' "$RUN_DIR/current.json")"
    CURRENT_BOARD_UNITS="$("$JQ" -r '.board_units // -1' "$RUN_DIR/current.json")"
    CURRENT_BOARD_CAPACITY="$("$JQ" -r '.board_capacity // -1' "$RUN_DIR/current.json")"

    # Retry bounds apply to one continuous semantic screen episode. Preserve
    # them across transient unknown animation frames, but reset a state's
    # budget after another recognized state has genuinely intervened (for
    # example, a second reconnect dialog after returning through the lobby).
    if [[ "$CURRENT_STATE" != unknown && "$CURRENT_STATE" != "$LAST_SEMANTIC_STATE" ]]; then
        ACTION_COUNT[$CURRENT_STATE]=0
        ACTION_LAST[$CURRENT_STATE]=0
        LAST_SEMANTIC_STATE="$CURRENT_STATE"
    fi
    "$JQ" -c \
        --arg utc "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --argjson iteration "$iteration" \
        '. + {utc: $utc, iteration: $iteration}' \
        "$RUN_DIR/current.json" >> "$RUN_DIR/navigation.jsonl"

    if [[ "$CURRENT_STATE" != "$LAST_STATE" ]]; then
        cp "$RUN_DIR/current.png" "$RUN_DIR/state-${iteration}-${CURRENT_STATE}.png"
        cp "$RUN_DIR/current.json" "$RUN_DIR/state-${iteration}-${CURRENT_STATE}.json"
        print "Trial state: $CURRENT_STATE stage=${CURRENT_STAGE:-none} phase=${CURRENT_PHASE:-none}"
        LAST_STATE="$CURRENT_STATE"
    fi
}

tap_recognized_state() {
    local state="$1"
    local label="$2"
    local x="$3"
    local y="$4"
    local coordinate_space="${5:-menu}"
    integer count="${ACTION_COUNT[$state]:-0}"
    integer last="${ACTION_LAST[$state]:-0}"
    integer limit=3
    integer retry_seconds=8

    if [[ "$state" == "login" ]]; then
        limit=5
        retry_seconds=12
    elif [[ "$state" == "login_service_error" ]]; then
        limit=5
        retry_seconds=15
    elif [[ "$state" == trial-choice-* || "$state" == post-combat-reward-* ]]; then
        # A single completed Trial round can expose four or more sequential
        # loot choices. Keep retries responsive while retaining a hard bound.
        limit=10
        retry_seconds=2
    fi
    if (( count > 0 && SECONDS - last < retry_seconds )); then
        return 0
    fi
    if (( count >= limit )); then
        print "Button $label did not move the screen from state $state after $limit attempts."
        return 1
    fi
    case "$coordinate_space" in
        game)
            tap_game_reference "$x" "$y"
            ;;
        display_right)
            # Top-right HUD buttons retain a constant pixel offset from the
            # right edge as density rises; proportional x scaling hits the
            # adjacent Missions button at 1800p/2160p.
            "$ADB" -s "$SERIAL" shell input tap \
                $(( DISPLAY_WIDTH - x )) "$y" >/dev/null
            ;;
        display_center)
            # Settings and confirmation modals retain a fixed pixel size and
            # are centered inside the physical SurfaceView.
            "$ADB" -s "$SERIAL" shell input tap \
                $(( DISPLAY_WIDTH / 2 + x )) \
                $(( DISPLAY_HEIGHT / 2 + y )) >/dev/null
            ;;
        *)
            tap_reference "$x" "$y"
            ;;
    esac
    ACTION_COUNT[$state]=$(( count + 1 ))
    ACTION_LAST[$state]=$SECONDS
    print "Trial action: $label (attempt $(( count + 1 )))."
}

attempt_keychain_login() {
    (( LOGIN_HELPER_ATTEMPTS += 1 ))
    local attempt_log="$RUN_DIR/login-helper-attempt-${LOGIN_HELPER_ATTEMPTS}.log"
    local failure_stage=""
    LOGIN_HELPER_LAST=$SECONDS
    if "$LOGIN_HELPER" > "$attempt_log" 2>&1; then
        LOGIN_HELPER_SUBMITTED=1
        print "The Riot login form was submitted by the scoped Keychain helper; waiting for the lobby."
        return 0
    fi
    if grep -Eq 'CAPTCHA|MFA' "$attempt_log" 2>/dev/null; then
        cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-login-helper.png"
        print "The scoped Keychain login helper detected CAPTCHA/MFA and stopped."
        return 2
    fi
    failure_stage="$(sed -n 's/^TFT_LOGIN_HELPER_STAGE=\([a-z_]*\)$/\1/p' "$attempt_log" | tail -n 1)"
    print "Riot login helper: attempt $LOGIN_HELPER_ATTEMPTS/5 is not ready; stage=${failure_stage:-unknown}."
    if (( LOGIN_HELPER_ATTEMPTS >= 5 )); then
        cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-login-helper.png"
        print "The Riot login helper could not safely submit the form after five attempts."
        return 3
    fi
    # The official WebView may exist before its DOM and DevTools socket are
    # ready. A failed preflight does not read secrets and is safe to retry.
    return 1
}

stage_number() {
    local stage="$1"
    local major="${stage%-*}"
    local round="${stage#*-}"
    print $(( major * 100 + round ))
}

is_target_stage() {
    local candidate_stage="$1"
    local configured_stage
    for configured_stage in "${TARGET_STAGES[@]}"; do
        [[ "$configured_stage" == "$candidate_stage" ]] && return 0
    done
    return 1
}

all_targets_captured() {
    local configured_stage
    for configured_stage in "${TARGET_STAGES[@]}"; do
        [[ "${CAPTURED_STAGE[$configured_stage]:-0}" == "1" ]] || return 1
    done
    return 0
}

any_target_captured() {
    local configured_stage
    for configured_stage in "${TARGET_STAGES[@]}"; do
        [[ "${CAPTURED_STAGE[$configured_stage]:-0}" == "1" ]] && return 0
    done
    return 1
}

minimum_trial_duration_reached() {
    [[ -n "$TRIAL_STARTED_SECONDS" ]] || return 1
    (( SECONDS - TRIAL_STARTED_SECONDS >= MINIMUM_TRIAL_SECONDS ))
}

missed_target_stage() {
    local current_number configured_stage configured_number
    current_number="$(stage_number "$1")"
    for configured_stage in "${TARGET_STAGES[@]}"; do
        configured_number="$(stage_number "$configured_stage")"
        if (( current_number > configured_number )) \
                && [[ "${CAPTURED_STAGE[$configured_stage]:-0}" != "1" ]]; then
            print -r -- "$configured_stage"
            return 0
        fi
    done
    return 1
}

collect_trial_rewards_fast() {
    local reward_point input_script=""
    typeset -a reward_points
    # Three waypoints form a triangle through the common orb field. Send the
    # whole route over one ADB shell and let the Little Legend traverse it while
    # planning is active; the old policy paid for five host ADB round-trips and
    # 3.5 seconds of fixed sleeps on every single stage.
    reward_points=("1050 300" "860 610" "1280 700")
    for reward_point in "${reward_points[@]}"; do
        input_script+="input tap $(game_scale_x "${reward_point% *}") $(game_scale_y "${reward_point#* }"); sleep 0.65; "
    done
    "$ADB" -s "$SERIAL" shell "$input_script" >/dev/null
}

spend_gold_on_xp() {
    integer attempts="${1:-16}"
    integer attempt
    local xp_x xp_y input_script=""
    xp_x="$(game_scale_x 80)"
    xp_y="$(game_scale_y 1060)"
    # Disabled/insufficient-gold taps are ignored by TFT. One remote shell
    # drains every affordable four-gold XP purchase without 16 ADB connections
    # or arbitrary host sleeps and can never hit Reroll.
    for (( attempt = 1; attempt <= attempts; attempt += 1 )); do
        input_script+="input tap $xp_x $xp_y; "
    done
    "$ADB" -s "$SERIAL" shell "$input_script" >/dev/null
}

buy_best_shop_unit_and_close() {
    local stage="$1"
    local best_slot=0 best_cost=0 minimum_cost=2 slot cost input_script=""
    typeset -a shop_costs shop_xs
    # The first two shops are frequently all tier-1. Buying one card from each
    # removes that RNG dependency while later shops retain the tier-2 quality
    # floor, avoiding a low-tier swap if OCR undercounts an already full board.
    (( $(stage_number "$stage") <= 102 )) && minimum_cost=1
    if [[ "$CURRENT_BOARD_UNITS" == <-> && "$CURRENT_BOARD_CAPACITY" == <-> ]] \
            && (( CURRENT_BOARD_UNITS >= CURRENT_BOARD_CAPACITY )); then
        # Prefer tier-3+ upgrades only when the semantic counter proves the
        # board is full. If OCR temporarily omits the counter, retain the
        # bounded fallback: treating missing evidence as "full" repeatedly left
        # 1/4 and 2/3 boards empty and made late-stage runs non-reproducible.
        # Buying one best available card is bounded, uses no rerolls, and makes
        # the 1-8 semantic gate less dependent on early shop RNG.
        minimum_cost=3
    fi
    shop_costs=("${(@f)$(print -r -- "$CURRENT_SHOP_COSTS_JSON" | "$JQ" -r '.[]')}")
    shop_xs=(1055 1275 1490 1710)
    for (( slot = 1; slot <= ${#shop_xs}; slot += 1 )); do
        cost="${shop_costs[$slot]:-0}"
        if [[ "$cost" == <-> ]] && (( cost > best_cost )); then
            best_slot=$slot
            best_cost=$cost
        fi
    done
    (( best_cost >= minimum_cost )) || best_slot=0
    if (( best_slot > 0 )); then
        input_script+="input tap $(shop_card_x "${shop_xs[$best_slot]}") $(density_scale 260); sleep 0.25; "
    fi
    input_script+="input tap $(game_scale_x 1965) $(game_scale_y 1080); "
    "$ADB" -s "$SERIAL" shell "$input_script" >/dev/null
    CURRENT_SHOP_OPEN=0
    SHOP_HANDLED_STAGE[$stage]=1
    "$JQ" -cn \
        --arg utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg stage "$stage" \
        --argjson costs "$CURRENT_SHOP_COSTS_JSON" \
        --argjson minimum_cost "$minimum_cost" \
        --argjson board_units "$CURRENT_BOARD_UNITS" \
        --argjson board_capacity "$CURRENT_BOARD_CAPACITY" \
        --argjson selected_slot "$best_slot" \
        --argjson selected_cost "$best_cost" \
        '{utc:$utc,event:"shop_analyzed",stage:$stage,costs:$costs,
          minimum_cost:$minimum_cost,
          board_units:(if $board_units < 0 then null else $board_units end),
          board_capacity:(if $board_capacity < 0 then null else $board_capacity end),
          selected_slot:(if $selected_slot == 0 then null else $selected_slot end),
          selected_cost:(if $selected_slot == 0 then null else $selected_cost end)}' \
        >> "$RUN_DIR/planning-events.jsonl"
    if (( best_slot > 0 )); then
        (( BENCH_UNITS_AVAILABLE += 1 ))
        print "Trial action: bought shop slot $best_slot (tier $best_cost) for $stage and closed the shop."
    else
        print "Trial action: no eligible tier-$minimum_cost+ shop unit for $stage; closed the shop."
    fi
}

reinforce_board_once_if_needed() {
    local target_x
    typeset -a board_target_xs
    board_target_xs=(1500 1320 1140 960 780)
    LAST_BOARD_SWIPES=0
    if (( BENCH_UNITS_AVAILABLE <= 0 \
            || BOARD_PLACEMENTS_DONE >= ${#board_target_xs} )); then
        return 0
    fi
    if [[ "$CURRENT_BOARD_UNITS" == <-> && "$CURRENT_BOARD_CAPACITY" == <-> ]] \
            && (( CURRENT_BOARD_UNITS >= CURRENT_BOARD_CAPACITY )); then
        return 0
    fi
    # Exactly one first-bench -> free-hex action replaces seven blind drags on
    # every stage. A fresh 1440p screenshot locates the first bench center near
    # (415,1010), not the former (350,1000) point at the empty left margin.
    # Cycle across distinct back-row hexes so repeated reinforcements grow the
    # board instead of swapping through the same occupied destination.
    # Fill from the unoccupied far-right side toward the starter at the left;
    # the opposite order repeatedly swapped the starter instead of increasing
    # the field count.
    target_x="${board_target_xs[$(( BOARD_PLACEMENTS_DONE + 1 ))]}"
    swipe_game_reference 415 1010 "$target_x" 720 220
    (( BENCH_UNITS_AVAILABLE -= 1 ))
    (( BOARD_PLACEMENTS_DONE += 1 ))
    LAST_BOARD_SWIPES=1
    if [[ "$CURRENT_BOARD_UNITS" == <-> && "$CURRENT_BOARD_CAPACITY" == <-> ]]; then
        print "Trial action: filled one confirmed board vacancy ($CURRENT_BOARD_UNITS/$CURRENT_BOARD_CAPACITY)."
    else
        # Vision occasionally drops the small occupancy counter. One bounded
        # bench-to-back-hex swipe is still safe: an empty hex is filled, while
        # an unexpectedly occupied hex performs a reversible unit swap.
        print "Trial action: placed one bench unit while the board counter was temporarily unavailable."
    fi
}

equip_early_items_once() {
    LAST_ITEM_SWIPES=0
    (( ITEMS_EQUIPPED == 0 )) || return 0
    typeset -a item_sources item_targets
    local item_source item_target input_script=""
    integer item_index=1
    # These are 2048x1152 reference coordinates, just like every other board
    # gesture. A fresh 2560x1440 Trial screenshot places the item-tray centers
    # at x=60 and y=138+84n in this reference space, and the reliable left-back
    # champion near (700,720). The former (480,665) target landed on empty
    # board space above and left of that champion. Offer all four possible
    # drops to the same unit because one can be a non-equippable selection or
    # anvil; TFT itself rejects any component after the three-item maximum.
    # This stays within one ADB shell and adds no host-side sleep.
    item_sources=("60 138" "60 222" "60 306" "60 390")
    item_targets=("700 720" "700 720" "700 720" "700 720")
    for item_source in "${item_sources[@]}"; do
        item_target="${item_targets[$(( (item_index - 1) % ${#item_targets} + 1 ))]}"
        input_script+="input swipe $(game_scale_x "${item_source% *}") $(game_scale_y "${item_source#* }") $(game_scale_x "${item_target% *}") $(game_scale_y "${item_target#* }") 220; "
        (( item_index += 1 ))
    done
    "$ADB" -s "$SERIAL" shell "$input_script" >/dev/null
    ITEMS_EQUIPPED=1
    LAST_ITEM_SWIPES=4
    print "Trial action: completed the single four-drop carry batch for early survival."
}

handle_combat_shop() {
    local stage="$1"
    [[ "${SHOP_HANDLED_STAGE[$stage]:-0}" != "1" ]] || return 0
    if [[ "$CURRENT_SHOP_OPEN" == "1" ]]; then
        buy_best_shop_unit_and_close "$stage"
        return 0
    fi
    if [[ "${SHOP_OPEN_REQUESTED_STAGE[$stage]:-0}" != "1" ]]; then
        tap_game_reference 1965 1080
        SHOP_OPEN_REQUESTED_STAGE[$stage]=1
        print "Trial action: opened the $stage shop during combat for overlapped analysis."
    fi
}

prepare_stage_fast() {
    local stage="$1"
    local mode="${2:-normal}"
    integer started=$SECONDS

    # The semantic stage label appears roughly one second before surviving
    # units and the bench are restored after combat. Acting immediately could
    # drag from an empty transition frame and then start the next fight with an
    # empty board. Give stages after 1-1 one bounded compositor/gameplay tick.
    (( $(stage_number "$stage") > 101 )) && sleep 1

    # If combat ended before the overlapped shop pass completed, finish the
    # same single-card policy before XP. No rerolls and no five-card sweep.
    if [[ "$CURRENT_SHOP_OPEN" == "1" \
            && "${SHOP_HANDLED_STAGE[$stage]:-0}" != "1" ]]; then
        buy_best_shop_unit_and_close "$stage"
    fi
    collect_trial_rewards_fast
    spend_gold_on_xp 16
    reinforce_board_once_if_needed
    if (( $(stage_number "$stage") >= 102 )); then
        equip_early_items_once
    else
        LAST_ITEM_SWIPES=0
    fi
    # Start the benchmark as soon as the one-time item batch and the single
    # evidence-driven reinforcement (if any) are complete.
    tap_game_reference 1965 920
    integer elapsed=$(( SECONDS - started ))
    "$JQ" -cn \
        --arg utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg stage "$stage" \
        --arg mode "$mode" \
        --argjson trial_attempt "$TRIAL_ATTEMPTS_STARTED" \
        --argjson duration_seconds "$elapsed" \
        --argjson board_swipes "$LAST_BOARD_SWIPES" \
        --argjson item_swipes "$LAST_ITEM_SWIPES" \
        '{utc:$utc,event:"stage_prepared",stage:$stage,mode:$mode,trial_attempt:$trial_attempt,
          duration_seconds:$duration_seconds,rerolls:0,reward_waypoints:3,
          xp_attempts:16,board_swipes:$board_swipes,item_swipes:$item_swipes,fight_tapped:true}' \
        >> "$RUN_DIR/planning-events.jsonl"
    print "Trial action: $mode preparation for $stage completed in ${elapsed}s; reroll=0, board_swipes=$LAST_BOARD_SWIPES, item_swipes=$LAST_ITEM_SWIPES."
}

capture_privacy_safe_profile() {
    local stage="$1"
    local profile_dir="$RUN_DIR/profile-$stage"
    local game_pid host_qemu_pid remote_data simpleperf_event
    local simpleperf_status=127 host_sample_status=127
    local host_sampler_pid=""
    mkdir -p "$profile_dir"

    take_state_screenshot
    cp "$RUN_DIR/current.png" "$profile_dir/before.png"
    cp "$RUN_DIR/current.json" "$profile_dir/before.json"
    if [[ "$CURRENT_STATE" != battle || "$CURRENT_STAGE" != "$stage" \
            || "$CURRENT_PHASE" != combat ]]; then
        print "Privacy-safe profile skipped: semantic gate $stage/combat already closed."
        return 1
    fi

    game_pid="$(
        "$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null \
            | tr -d '\r' | awk '{ print $1 }'
    )"
    if [[ "$game_pid" != <-> ]]; then
        print "Privacy-safe profile skipped: the TFT PID was not found."
        return 1
    fi
    host_qemu_pid="$(
        pgrep -f "qemu-system-aarch64.*${AVD_NAME}" 2>/dev/null | head -n 1 || true
    )"
    remote_data="/data/local/tmp/tft-pbe-profile-${game_pid}.data"
    simpleperf_event="$({
        "$ADB" -s "$SERIAL" shell simpleperf list sw 2>/dev/null \
            | tr -d '\r' | awk '$1 == "cpu-clock" { print $1; exit }'
    } || true)"
    [[ -n "$simpleperf_event" ]] || simpleperf_event=task-clock

    if [[ "$host_qemu_pid" == <-> ]]; then
        /usr/bin/sample "$host_qemu_pid" 2 1 \
            -file "$profile_dir/host-qemu.sample.txt" \
            > "$profile_dir/host-sample.log" 2>&1 &
        host_sampler_pid=$!
    else
        print "host QEMU PID not found" > "$profile_dir/host-sample.log"
    fi

    set +e
    "$ADB" -s "$SERIAL" shell simpleperf record \
        -e "$simpleperf_event" -g --duration 2 -p "$game_pid" -o "$remote_data" \
        > "$profile_dir/simpleperf-record.log" 2>&1
    simpleperf_status=$?
    if [[ -n "$host_sampler_pid" ]]; then
        wait "$host_sampler_pid"
        host_sample_status=$?
    fi
    set -e

    # Freeze the post-sample semantic gate before generating the report. The
    # report can take longer than the bounded recording and must not make an
    # otherwise valid in-combat sample appear to cross a stage boundary.
    take_state_screenshot
    cp "$RUN_DIR/current.png" "$profile_dir/after.png"
    cp "$RUN_DIR/current.json" "$profile_dir/after.json"
    set +e
    if (( simpleperf_status == 0 )); then
        "$ADB" -s "$SERIAL" shell simpleperf report -i "$remote_data" \
            --sort comm,pid,tid,symbol \
            > "$profile_dir/simpleperf-report.txt" 2> "$profile_dir/simpleperf-report.stderr"
        simpleperf_status=$?
    fi
    "$ADB" -s "$SERIAL" shell rm -f "$remote_data" >/dev/null 2>&1
    set -e
    "$JQ" -n \
        --arg stage "$stage" \
        --arg game_pid "$game_pid" \
        --arg host_qemu_pid "${host_qemu_pid:-none}" \
        --arg simpleperf_event "$simpleperf_event" \
        --arg before_state "$("$JQ" -r '.state' "$profile_dir/before.json")" \
        --arg before_stage "$("$JQ" -r '.stage // ""' "$profile_dir/before.json")" \
        --arg before_phase "$("$JQ" -r '.phase // ""' "$profile_dir/before.json")" \
        --arg after_state "$("$JQ" -r '.state' "$profile_dir/after.json")" \
        --arg after_stage "$("$JQ" -r '.stage // ""' "$profile_dir/after.json")" \
        --arg after_phase "$("$JQ" -r '.phase // ""' "$profile_dir/after.json")" \
        --argjson simpleperf_status "$simpleperf_status" \
        --argjson host_sample_status "$host_sample_status" \
        '{
            schema_version: 1,
            stage: $stage,
            game_pid: $game_pid,
            host_qemu_pid: $host_qemu_pid,
            simpleperf_event: $simpleperf_event,
            simpleperf_status: $simpleperf_status,
            host_sample_status: $host_sample_status,
            semantic_gate: {
                before: {state: $before_state, stage: $before_stage, phase: $before_phase},
                after: {state: $after_state, stage: $after_stage, phase: $after_phase},
                valid: ($before_state == "battle" and $after_state == "battle"
                    and $before_stage == $stage and $after_stage == $stage
                    and $before_phase == "combat" and $after_phase == "combat")
            }
        }' > "$profile_dir/summary.json.next"
    mv -f "$profile_dir/summary.json.next" "$profile_dir/summary.json"
    PROFILE_CAPTURED=1
    print "Privacy-safe guest/host profile saved: $profile_dir"
}

while (( SECONDS - navigation_started < NAVIGATION_TIMEOUT )); do
    if ! kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
        wait "$LAUNCHER_PID" || true
        LAUNCHER_PID=""
        print "The launcher exited during the Trial. Log: $RUN_DIR/launcher.log"
        exit 1
    fi
    if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        print "The ADB device disappeared during the Trial. Log: $RUN_DIR/launcher.log"
        exit 1
    fi

    take_state_screenshot
    case "$CURRENT_STATE" in
        patch_available)
            UNKNOWN_SINCE=""
            # This exact two-marker modal is the only startup patch prompt the
            # autonomous runner accepts. The affirmative icon is centered in
            # the right half of the fixed-size dialog.
            if ! tap_recognized_state patch_available ACCEPT_PATCH \
                    110 86 display_center; then
                exit 3
            fi
            ;;
        patch_ready)
            UNKNOWN_SINCE=""
            if ! tap_recognized_state patch_ready START_PATCHING \
                    0 165 display_center; then
                exit 3
            fi
            ;;
        patching)
            # Patching is a recognized non-interactive state. Keep observing;
            # every click remains disabled until another exact state appears.
            UNKNOWN_SINCE=""
            ;;
        cosmetic_notice)
            UNKNOWN_SINCE=""
            # The exact default-cosmetics notice is informational and its
            # close glyph has a stable location inside the Trials panel.
            if ! tap_recognized_state cosmetic_notice CLOSE_COSMETIC_NOTICE \
                    1165 565; then
                exit 3
            fi
            ;;
        disconnected)
            UNKNOWN_SINCE=""
            if [[ "$CURRENT_EVIDENCE" == *"YOU DISCONNECTED"* \
                    && "$CURRENT_EVIDENCE" == *"RECONNECT"* ]]; then
                if ! tap_recognized_state disconnected RECONNECT_LIVE_TRIAL 1280 720; then
                    cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-disconnected.png"
                    exit 3
                fi
            else
                cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-disconnected.png"
                print "Fail-closed: unknown connection screen; reconnect is not attempted."
                exit 3
            fi
            ;;
        error)
            if [[ "$CURRENT_EVIDENCE" == *"declined ready check"* \
                    && "$CURRENT_EVIDENCE" == *"returned to the lobby"* ]]; then
                # Exact, harmless acknowledgement left behind by a timed-out
                # ready check. Generic Riot errors remain fail-closed.
                if ! tap_recognized_state ready_check_declined \
                        ACKNOWLEDGE_READY_CHECK 1280 773; then
                    exit 3
                fi
            else
                cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-error.png"
                print "Fail-closed: a generic error screen was detected; no automatic action is taken."
                exit 3
            fi
            ;;
        login_service_error)
            UNKNOWN_SINCE=""
            LOGIN_HELPER_ATTEMPTS=0
            LOGIN_HELPER_SUBMITTED=0
            ACTION_COUNT[login]=0
            ACTION_LAST[login]=0
            if ! tap_recognized_state login_service_error RETRY_LOGIN_SERVICE 1390 790; then
                exit 3
            fi
            ;;
        login)
            UNKNOWN_SINCE=""
            if [[ "$CURRENT_REASON" == "sign_in_splash" ]]; then
                tap_recognized_state login SIGN_IN 1280 820
            else
                top_activity="$(
                    "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
                        | tr -d '\r' \
                        | grep -m 1 'topResumedActivity=' || true
                )"
                if [[ "$top_activity" == *"$PACKAGE"* \
                        && "$top_activity" != *MobileFREWebViewActivity* \
                        && "$CURRENT_EVIDENCE" == *"SIGN IN"* ]]; then
                    # At higher physical resolutions OCR may miss the logo and
                    # leave only SIGN IN/Logging in. This is still the official
                    # TFT splash Activity, not a credential form; bounded taps are safe
                    # and disabled buttons simply ignore them.
                    tap_recognized_state login SIGN_IN 1280 820
                elif [[ "$top_activity" != *MobileFREWebViewActivity* ]]; then
                    cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-login.png"
                    print "Fail-closed: login state is neither a known splash nor the official Riot WebView."
                    exit 3
                elif (( LOGIN_HELPER_SUBMITTED == 0 && SECONDS - LOGIN_HELPER_LAST >= 5 )); then
                    if attempt_keychain_login; then
                        :
                    else
                        helper_status=$?
                        if (( helper_status == 2 || helper_status == 3 )); then
                            exit 3
                        fi
                    fi
                elif (( LOGIN_HELPER_SUBMITTED == 1 && SECONDS - LOGIN_HELPER_LAST >= 45 )); then
                    cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-login-timeout.png"
                    print "The Riot WebView did not close within 45 seconds after Sign In."
                    exit 3
                fi
            fi
            ;;
        lobby)
            UNKNOWN_SINCE=""
            if ! tap_recognized_state lobby PLAY 2220 1300; then
                exit 3
            fi
            ;;
        mode_select)
            UNKNOWN_SINCE=""
            if ! tap_recognized_state mode_select TOCKERS_TRIALS 1475 1000; then
                exit 3
            fi
            ;;
        trials_lobby)
            UNKNOWN_SINCE=""
            if ! tap_recognized_state trials_lobby START 2220 1300; then
                exit 3
            fi
            ;;
        trial_ended)
            UNKNOWN_SINCE=""
            if ! tap_recognized_state trial_ended ACKNOWLEDGE_ENDED_TRIAL 1280 890; then
                exit 3
            fi
            ;;
        settings)
            UNKNOWN_SINCE=""
            if [[ "$MEASUREMENTS_COMPLETE" != "1" && "$RESETTING_STALE_TRIAL" != "1" ]]; then
                cp "$RUN_DIR/current.png" "$RUN_DIR/unexpected-settings.png"
                print "Fail-closed: settings opened before all measurements completed."
                exit 3
            fi
            if ! tap_recognized_state settings \
                    SURRENDER -237 318 display_center; then
                exit 3
            fi
            ;;
        surrender_confirm)
            UNKNOWN_SINCE=""
            if [[ "$MEASUREMENTS_COMPLETE" != "1" && "$RESETTING_STALE_TRIAL" != "1" ]]; then
                cp "$RUN_DIR/current.png" "$RUN_DIR/unexpected-surrender-confirm.png"
                print "Fail-closed: surrender confirmation opened before all measurements completed."
                exit 3
            fi
            if ! tap_recognized_state surrender_confirm \
                    CONFIRM_SURRENDER 129 102 display_center; then
                exit 3
            fi
            ;;
        trial_results)
            UNKNOWN_SINCE=""
            if [[ "$RESETTING_STALE_TRIAL" == "1" ]] \
                    || { [[ "$FRESH_TRIAL_CONFIRMED" != "1" ]] && ! any_target_captured; }; then
                RESETTING_STALE_TRIAL=1
                # PLAY AGAIN is the official path from a completed Trial to a
                # fresh 1-1. Keep the reset flag until 1-1 itself is observed.
                if ! tap_recognized_state trial_results_reset PLAY_AGAIN 2200 1320; then
                    exit 3
                fi
                print "The stale Trial ended; starting a fresh Trial through PLAY AGAIN."
                sleep 2
                continue
            fi
            if [[ "$MEASUREMENTS_COMPLETE" != "1" ]]; then
                if all_targets_captured && minimum_trial_duration_reached; then
                    MEASUREMENTS_COMPLETE=1
                    print "The Trial ended normally after all stages and the minimum duration."
                elif (( TRIAL_ATTEMPTS_STARTED < MAX_TRIAL_ATTEMPTS )); then
                    cp "$RUN_DIR/current.png" \
                        "$RUN_DIR/premature-trial-results-attempt-${TRIAL_ATTEMPTS_STARTED}.png"
                    cp "$RUN_DIR/current.json" \
                        "$RUN_DIR/premature-trial-results-attempt-${TRIAL_ATTEMPTS_STARTED}.json"
                    # Keep valid stage captures from this candidate, but reset
                    # all gameplay state. PLAY AGAIN avoids another emulator
                    # boot, login, mode selection, and ready check when random
                    # Trial combat ends before the heavy target stage.
                    FRESH_TRIAL_CONFIRMED=0
                    RESETTING_STALE_TRIAL=1
                    TRIAL_STARTED_SECONDS=""
                    if ! tap_recognized_state trial_results_reset PLAY_AGAIN 2200 1320; then
                        exit 3
                    fi
                    print "Trial attempt $TRIAL_ATTEMPTS_STARTED ended early; replaying in the same emulator (${TRIAL_ATTEMPTS_STARTED}/$MAX_TRIAL_ATTEMPTS)."
                    continue
                else
                    cp "$RUN_DIR/current.png" "$RUN_DIR/unexpected-trial-results.png"
                    print "The Trial ended before all semantic stages or the minimum duration were measured after $TRIAL_ATTEMPTS_STARTED attempts."
                    exit 3
                fi
            fi
            BENCHMARK_SUCCEEDED=1
            cp "$RUN_DIR/current.png" "$RUN_DIR/trial-results.png"
            cp "$RUN_DIR/current.json" "$RUN_DIR/trial-results.json"
            print "All semantic stages were measured and the Trial ended through a confirmed results gate: ${(j:,:)TARGET_STAGES}."
            print "Autonomous Trial benchmark completed: $RUN_DIR"
            exit 0
            ;;
        match_found)
            UNKNOWN_SINCE=""
            # The old y=1030 point sat on the lower border at 1440p and scaled
            # just below the button at 1800p. Target the visual center.
            if ! tap_recognized_state match_found ACCEPT 1280 960; then
                exit 3
            fi
            ;;
        match_accepted)
            UNKNOWN_SINCE=""
            ;;
        battle)
            UNKNOWN_SINCE=""
            if [[ -n "$RETRY_CANDIDATE_STAGE" \
                    && "$CURRENT_STAGE" != "$RETRY_CANDIDATE_STAGE" ]]; then
                COMBAT_SEEN_STAGE[$RETRY_CANDIDATE_STAGE]=0
                print "Trial transition: $RETRY_CANDIDATE_STAGE completed; loss recovery is unnecessary."
                RETRY_CANDIDATE_STAGE=""
                RETRY_CANDIDATE_SINCE=0
            fi
            if [[ "$CURRENT_PHASE" == combat && -n "$CURRENT_STAGE" ]]; then
                COMBAT_SEEN_STAGE[$CURRENT_STAGE]=1
            fi
            if [[ "$CURRENT_STAGE" == "1-1" && "$FRESH_TRIAL_CONFIRMED" != "1" ]]; then
                FRESH_TRIAL_CONFIRMED=1
                RESETTING_STALE_TRIAL=0
                (( TRIAL_ATTEMPTS_STARTED += 1 ))
                TRIAL_STARTED_SECONDS="$SECONDS"
                PREPARED_STAGE=()
                COMBAT_SEEN_STAGE=()
                LOSS_RECOVERY_COUNT=()
                SHOP_HANDLED_STAGE=()
                SHOP_OPEN_REQUESTED_STAGE=()
                CAPTURE_ATTEMPT=()
                BENCH_UNITS_AVAILABLE=0
                LAST_BOARD_SWIPES=0
                LAST_ITEM_SWIPES=0
                ITEMS_EQUIPPED=0
                BOARD_PLACEMENTS_DONE=0
                RETRY_CANDIDATE_STAGE=""
                RETRY_CANDIDATE_SINCE=0
                if (( TRIAL_ATTEMPTS_STARTED == 1 )); then
                    CAPTURED_STAGE=()
                    PROFILE_CAPTURED=0
                fi
                ACTION_COUNT[settings]=0
                ACTION_LAST[settings]=0
                ACTION_COUNT[surrender_confirm]=0
                ACTION_LAST[surrender_confirm]=0
                ACTION_COUNT[trials_lobby]=0
                ACTION_LAST[trials_lobby]=0
                ACTION_COUNT[match_found]=0
                ACTION_LAST[match_found]=0
                ACTION_COUNT[trial_results_reset]=0
                ACTION_LAST[trial_results_reset]=0
                gameplay_action_key=""
                for gameplay_action_key in "${(@k)ACTION_COUNT}"; do
                    if [[ "$gameplay_action_key" == trial-choice-* \
                            || "$gameplay_action_key" == post-combat-reward-* \
                            || "$gameplay_action_key" == fight-* ]]; then
                        unset "ACTION_COUNT[$gameplay_action_key]"
                        unset "ACTION_LAST[$gameplay_action_key]"
                    fi
                done
                print "Fresh Trial attempt $TRIAL_ATTEMPTS_STARTED/$MAX_TRIAL_ATTEMPTS was confirmed by semantic gate 1-1."
            elif [[ "$FRESH_TRIAL_CONFIRMED" != "1" && -n "$CURRENT_STAGE" ]] \
                    && (( $(stage_number "$CURRENT_STAGE") > 101 )); then
                RESETTING_STALE_TRIAL=1
                print "Detected a stale Trial at $CURRENT_STAGE; ending it before starting a fresh 1-1."
            fi
            if [[ "$RESETTING_STALE_TRIAL" != "1" && -z "$TRIAL_STARTED_SECONDS" ]]; then
                TRIAL_STARTED_SECONDS="$SECONDS"
                print "The sustained timer started at the first confirmed battle gate."
            fi
            if [[ "$RESETTING_STALE_TRIAL" == "1" ]]; then
                if [[ "$CURRENT_SHOP_OPEN" == "1" ]]; then
                    tap_game_reference 1965 1080
                    sleep 2
                fi
                # Unit details, missions and other right-side panels cover the
                # gear at higher resolutions. Deselect on an empty board zone,
                # then make one bounded gear tap instead of toggling overlays
                # on every expensive screenshot iteration.
                tap_game_reference 300 350
                sleep 1
                if ! tap_recognized_state reset_open_settings \
                        OPEN_SETTINGS 270 45 display_right; then
                    exit 3
                fi
            elif [[ "$MEASUREMENTS_COMPLETE" != "1" ]] \
                    && all_targets_captured && minimum_trial_duration_reached; then
                MEASUREMENTS_COMPLETE=1
                print "All stages and the minimum Trial duration were confirmed."
            fi
            if [[ "$RESETTING_STALE_TRIAL" == "1" ]]; then
                :
            elif [[ "$MEASUREMENTS_COMPLETE" == "1" ]]; then
                # Do not leave a live Trial behind for the next cold candidate.
                # Close the shop if needed, then open the in-game gear menu.
                if [[ "$CURRENT_SHOP_OPEN" == "1" ]]; then
                    tap_game_reference 1965 1080
                    sleep 2
                fi
                tap_game_reference 300 350
                sleep 1
                if ! tap_recognized_state finish_open_settings \
                        OPEN_SETTINGS 270 45 display_right; then
                    exit 3
                fi
            elif is_target_stage "$CURRENT_STAGE" \
                    && [[ "${CAPTURED_STAGE[$CURRENT_STAGE]:-0}" != "1" \
                    && "$CURRENT_PHASE" == "$TARGET_PHASE" \
                    && "$CURRENT_SHOP_OPEN" != "1" ]]; then
                measurement_stage="$CURRENT_STAGE"
                COMBAT_SEEN_STAGE[$measurement_stage]=1
                print "Semantic gate confirmed: battle / $measurement_stage / $TARGET_PHASE."
                integer capture_attempt_number
                capture_attempt_number=$(( ${CAPTURE_ATTEMPT[$measurement_stage]:-0} + 1 ))
                CAPTURE_ATTEMPT[$measurement_stage]="$capture_attempt_number"
                STAGE_CAPTURE_LOG="$RUN_DIR/capture-${measurement_stage}.log"
                (( capture_attempt_number > 1 )) \
                    && STAGE_CAPTURE_LOG="$RUN_DIR/capture-${measurement_stage}-attempt-${capture_attempt_number}.log"
                stage_measurement_rounds="$MEASUREMENT_ROUNDS"
                # The tutorial 1-1 wave can finish within three seconds. Keep
                # its first-use sample inside one semantic gate; all benchmark
                # stages retain the normal multi-round window.
                [[ "$measurement_stage" == "1-1" ]] && stage_measurement_rounds=1
                if [[ -n "$PROFILE_STAGE" && "$measurement_stage" == "$PROFILE_STAGE" \
                        && "$PROFILE_CAPTURED" != "1" ]]; then
                    capture_privacy_safe_profile "$measurement_stage" || true
                fi
                if ! /usr/bin/env "${CANDIDATE_ENV[@]}" \
                        "TFT_DISPLAY_SIZE=$CANDIDATE_DISPLAY" \
                        "TFT_DISPLAY_DENSITY=$CANDIDATE_DENSITY" \
                        TFT_SCENE="tockers_stage${measurement_stage}" \
                        TFT_VARIANT="$VARIANT" \
                        TFT_EXPECTED_STAGE="$measurement_stage" \
                        TFT_EXPECTED_PHASE="$TARGET_PHASE" \
                        TFT_SEMANTIC_BEFORE_IMAGE="$RUN_DIR/current.png" \
                        TFT_MEASUREMENT_ROUNDS="$stage_measurement_rounds" \
                        TFT_MEASUREMENT_WINDOW_SECONDS="$MEASUREMENT_WINDOW_SECONDS" \
                        TFT_MEASUREMENT_ROOT="$MEASUREMENT_ROOT" \
                            "$CAPTURE" > "$STAGE_CAPTURE_LOG" 2>&1; then
                    print "Frame capture attempt $capture_attempt_number failed the semantic gate or exited with an error. Log: $STAGE_CAPTURE_LOG"
                    take_state_screenshot
                    if (( capture_attempt_number < MAX_CAPTURE_ATTEMPTS )) \
                            && [[ "$CURRENT_STATE" == battle \
                            && "$CURRENT_STAGE" == "$measurement_stage" \
                            && "$CURRENT_PHASE" == "$TARGET_PHASE" \
                            && "$CURRENT_SHOP_OPEN" != "1" ]]; then
                        print "Trial capture: retrying $measurement_stage inside the same confirmed combat ($capture_attempt_number/$MAX_CAPTURE_ATTEMPTS)."
                        continue
                    fi
                    exit 3
                fi
                measurement_summary="$(find "$MEASUREMENT_ROOT" -type f -name summary.txt -print | sort | tail -n 1)"
                measurement_summary_json="${measurement_summary%.txt}.json"
                if [[ -z "$measurement_summary" ]]; then
                    print "Capture completed without summary.txt. Log: $STAGE_CAPTURE_LOG"
                    exit 3
                fi
                cp "$measurement_summary" "$RUN_DIR/result-summary-${measurement_stage}.txt"
                if [[ -f "$measurement_summary_json" ]]; then
                    cp "$measurement_summary_json" "$RUN_DIR/result-summary-${measurement_stage}.json"
                    MEASUREMENT_SUMMARIES_JSON+=("$measurement_summary_json")
                fi
                cat "$RUN_DIR/result-summary-${measurement_stage}.txt"
                CAPTURED_STAGE[$measurement_stage]=1
                if all_targets_captured; then
                    if minimum_trial_duration_reached; then
                        MEASUREMENTS_COMPLETE=1
                        print "All semantic stages were measured; ending the Trial at the results gate."
                    else
                        print "All semantic stages were measured; continuing the sustained Trial to ${MINIMUM_TRIAL_SECONDS}s."
                    fi
                fi
                sleep 2
            elif [[ "$CURRENT_PHASE" == "combat" ]]; then
                # Frame capture wins the branch above. Once a target sample is
                # complete (or on non-target rounds), overlap the next shop
                # decision with combat instead of extending planning.
                handle_combat_shop "$CURRENT_STAGE"
            elif missed_stage="$(missed_target_stage "$CURRENT_STAGE")"; [[ -n "$missed_stage" ]]; then
                cp "$RUN_DIR/current.png" "$RUN_DIR/missed-target-stage-${missed_stage}.png"
                print "Target stage $missed_stage was missed; current stage is $CURRENT_STAGE."
                exit 3
            elif [[ "$CURRENT_PHASE" == planning \
                    && -n "$CURRENT_STAGE" \
                    && "${COMBAT_SEEN_STAGE[$CURRENT_STAGE]:-0}" == "1" ]]; then
                # Returning to planning on the same stage after a confirmed
                # combat can be a brief victory marker lag or a real retry.
                # Observe ordinary state-loop frames instead of blocking every
                # victory on sleep(3) plus an extra screenshot.
                recovery_stage="$CURRENT_STAGE"
                if [[ "$RETRY_CANDIDATE_STAGE" != "$recovery_stage" ]]; then
                    RETRY_CANDIDATE_STAGE="$recovery_stage"
                    RETRY_CANDIDATE_SINCE=$SECONDS
                    print "Trial transition: observing $recovery_stage without a blocking retry wait."
                elif (( SECONDS - RETRY_CANDIDATE_SINCE < 3 )); then
                    :
                elif [[ "$CURRENT_FIGHT_VISIBLE" != "1" ]]; then
                    COMBAT_SEEN_STAGE[$recovery_stage]=0
                    RETRY_CANDIDATE_STAGE=""
                    RETRY_CANDIDATE_SINCE=0
                    print "Trial transition: $recovery_stage completed; loss recovery is unnecessary."
                else
                    COMBAT_SEEN_STAGE[$recovery_stage]=0
                    RETRY_CANDIDATE_STAGE=""
                    RETRY_CANDIDATE_SINCE=0
                    integer recovery_number
                    recovery_number=$(( ${LOSS_RECOVERY_COUNT[$recovery_stage]:-0} + 1 ))
                    LOSS_RECOVERY_COUNT[$recovery_stage]="$recovery_number"
                    cp "$RUN_DIR/current.png" \
                        "$RUN_DIR/loss-${recovery_number}-before-${recovery_stage}.png"
                    if ! prepare_stage_fast "$recovery_stage" recovery; then
                        exit 3
                    fi
                    take_state_screenshot
                    cp "$RUN_DIR/current.png" \
                        "$RUN_DIR/loss-${recovery_number}-after-${recovery_stage}.png"
                    retry_action_key="fight-$recovery_stage"
                    ACTION_COUNT[$retry_action_key]=0
                    ACTION_LAST[$retry_action_key]=0
                    print "Trial recovery: loss at $recovery_stage; reinforcement #$recovery_number completed."
                fi
            elif [[ -n "$CURRENT_STAGE" \
                    && "$CURRENT_PHASE" == planning \
                    && ( "$CURRENT_FIGHT_VISIBLE" == "1" \
                        || "$CURRENT_SHOP_OPEN" == "1" ) \
                    && "${PREPARED_STAGE[$CURRENT_STAGE]:-0}" != "1" ]]; then
                cp "$RUN_DIR/current.png" "$RUN_DIR/before-planning-${CURRENT_STAGE}.png"
                if [[ "$CURRENT_STAGE" == "1-1" ]]; then
                    tap_game_reference 1280 120
                    sleep 1
                fi
                if ! prepare_stage_fast "$CURRENT_STAGE" normal; then
                    exit 3
                fi
                PREPARED_STAGE[$CURRENT_STAGE]=1
            elif [[ "$CURRENT_PHASE" == post_combat && -n "$CURRENT_STAGE" ]]; then
                # Completed Trial rounds can leave several question-mark orbs
                # on the arena. The gold lower-right action opens exactly one
                # CHOOSE ONE overlay at a time; the trial_choice branch closes
                # it, then this gated action repeats until the stage advances.
                if ! tap_recognized_state "post-combat-reward-$CURRENT_STAGE" \
                        OPEN_REWARD_CHOOSER 1965 1016 game; then
                    exit 3
                fi
            elif [[ "$CURRENT_FIGHT_VISIBLE" == "1" ]]; then
                if ! tap_recognized_state "fight-$CURRENT_STAGE" FIGHT 1965 920 game; then
                    exit 3
                fi
            elif [[ "$CURRENT_SHOP_OPEN" == "1" ]]; then
                # Recovery path when a delayed shop animation consumed the
                # first close tap.
                tap_game_reference 1965 1080
                sleep 2
            fi
            ;;
        trial_choice)
            # Reward and evolution choices replace the HUD during planning.
            # The classifier exposes this state only with the top stage marker
            # and CHOOSE ONE. Selecting the left card is deterministic and the
            # stage gate prevents this action on Riot/login dialogs.
            if [[ -z "$CURRENT_STAGE" ]]; then
                cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-trial-choice-without-stage.png"
                print "The Trial choice does not contain a confirmed stage marker."
                exit 3
            fi
            if [[ "$CURRENT_REASON" == "trial_option_choice" ]]; then
                if ! tap_recognized_state "trial-choice-$CURRENT_STAGE" \
                        TRIAL_OPTION_CHOICE 700 520 game; then
                    exit 3
                fi
            elif ! tap_recognized_state "trial-choice-$CURRENT_STAGE" \
                    TRIAL_REWARD_CHOICE 1200 150 game; then
                exit 3
            fi
            ;;
        unknown)
            if [[ -z "$UNKNOWN_SINCE" ]]; then
                UNKNOWN_SINCE="$SECONDS"
            elif (( SECONDS - UNKNOWN_SINCE >= UNKNOWN_TIMEOUT )); then
                cp "$RUN_DIR/current.png" "$RUN_DIR/unknown-timeout.png"
                print "An unknown screen persisted for $UNKNOWN_TIMEOUT seconds; no clicks are performed."
                exit 3
            fi
            unknown_top_activity="$(
                "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
                    | tr -d '\r' \
                    | grep -m 1 'topResumedActivity=' || true
            )"
            if [[ "$unknown_top_activity" == *MobileFREWebViewActivity* ]]; then
                if (( LOGIN_HELPER_SUBMITTED == 0 && SECONDS - LOGIN_HELPER_LAST >= 5 )); then
                    if attempt_keychain_login; then
                        :
                    else
                        helper_status=$?
                        if (( helper_status == 2 || helper_status == 3 )); then
                            exit 3
                        fi
                    fi
                elif (( LOGIN_HELPER_SUBMITTED == 1 && SECONDS - LOGIN_HELPER_LAST >= 45 )); then
                    cp "$RUN_DIR/current.png" "$RUN_DIR/rejected-login-timeout.png"
                    print "The Riot WebView did not close within 45 seconds after Sign In."
                    exit 3
                fi
            fi
            ;;
    esac
    sleep 1
done

cp "$RUN_DIR/current.png" "$RUN_DIR/navigation-timeout.png"
print "The Trial did not complete stages ${(j:,:)TARGET_STAGES} / $TARGET_PHASE within $NAVIGATION_TIMEOUT seconds."
exit 3
