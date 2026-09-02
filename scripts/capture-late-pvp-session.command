#!/bin/zsh
set -euo pipefail

unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly FRAME_CAPTURE="${TFT_LATE_PVP_FRAME_CAPTURE:-$PROJECT_DIR/scripts/capture-frame-pacing.command}"
readonly DEFAULT_CLASSIFIER="$PROJECT_DIR/runtime/tft-screen-classifier"
readonly CLASSIFIER="${TFT_SCREEN_CLASSIFIER_BINARY:-$DEFAULT_CLASSIFIER}"
readonly CLASSIFIER_SOURCE="$PROJECT_DIR/tools/tft-screen-classifier.swift"
readonly CLASSIFIER_BUILD="$PROJECT_DIR/scripts/build-tft-screen-classifier.command"
readonly THREAD_SNAPSHOT="$PROJECT_DIR/scripts/capture-android-thread-snapshot.command"
readonly THREAD_COMPARE="$PROJECT_DIR/scripts/compare-android-thread-snapshots.command"
readonly CANDIDATE_MANIFEST="${TFT_PERFORMANCE_CANDIDATES_MANIFEST:-$PROJECT_DIR/scripts/performance-candidates.json}"
readonly JQ="${TFT_JQ:-$(command -v jq 2>/dev/null || true)}"
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly GAME_ACTIVITY="$PACKAGE/com.epicgames.unreal.GameActivity"
readonly SESSION_ROOT="${TFT_LATE_PVP_ROOT:-$PROJECT_DIR/runtime/measurements/late-pvp}"
readonly MIN_STAGE="${TFT_LATE_PVP_MIN_STAGE:-4}"
readonly PVP_ROUNDS="${TFT_LATE_PVP_ROUNDS:-1,2,3,5,6}"
readonly POLL_SECONDS="${TFT_LATE_PVP_POLL_SECONDS:-4}"
readonly CAPTURE_ROUNDS="${TFT_LATE_PVP_CAPTURE_ROUNDS:-3}"
readonly CAPTURE_WINDOW_SECONDS="${TFT_LATE_PVP_WINDOW_SECONDS:-2}"
readonly MAX_CAPTURES="${TFT_LATE_PVP_MAX_CAPTURES:-8}"
readonly PROFILE_FIRST_CAPTURE="${TFT_LATE_PVP_PROFILE_FIRST_CAPTURE:-1}"
readonly PROFILE_SECONDS="${TFT_LATE_PVP_PROFILE_SECONDS:-2}"
typeset CAPTURE_VARIANT="${TFT_LATE_PVP_VARIANT:-performance_max}"
readonly RENDERER_HINT="${TFT_RENDERER:-angle-opengl}"
readonly GUEST_GL_DRIVER_HINT="${TFT_GUEST_GL_DRIVER:-angle}"
typeset PROFILE_PATH="${TFT_PROFILE_PATH:-$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini}"

typeset DURATION="${TFT_LATE_PVP_DURATION:-90m}"
typeset SELF_TEST=0
typeset PRINT_SELECTION=0
typeset PRINT_PRIORITY_QUEUE=0
typeset CANDIDATE_ID=""
typeset PINNED_PROFILE_SHA256=""

while (( $# > 0 )); do
    case "$1" in
        --duration)
            (( $# >= 2 )) || { print "--duration requires a value such as 90m"; exit 2; }
            DURATION="$2"
            shift 2
            ;;
        --self-test)
            SELF_TEST=1
            shift
            ;;
        --candidate-id)
            (( $# >= 2 )) || { print "--candidate-id requires a manifest candidate ID"; exit 2; }
            CANDIDATE_ID="$2"
            shift 2
            ;;
        --print-selection)
            PRINT_SELECTION=1
            shift
            ;;
        --print-priority-queue)
            PRINT_PRIORITY_QUEUE=1
            shift
            ;;
        -h|--help)
            print "Usage: ${0:t} [--duration 90m] [--candidate-id ID] [--print-selection] [--print-priority-queue] [--self-test]"
            print "Passively captures stages ${MIN_STAGE}+ rounds $PVP_ROUNDS while TFT is in combat."
            exit 0
            ;;
        *)
            print "Unknown argument: $1"
            exit 2
            ;;
    esac
done

if (( PRINT_PRIORITY_QUEUE == 1 )); then
    if [[ -n "$CANDIDATE_ID" || "$PRINT_SELECTION" == "1" ]]; then
        print "--print-priority-queue cannot be combined with candidate selection."
        exit 2
    fi
    if [[ ! -x "$JQ" || ! -f "$CANDIDATE_MANIFEST" ]]; then
        print "Priority queue selection requires jq and scripts/performance-candidates.json."
        exit 1
    fi
    typeset queue_profile_relative queue_profile_sha256
    while IFS=$'\t' read -r queue_profile_relative queue_profile_sha256; do
        if [[ ! -f "$PROJECT_DIR/$queue_profile_relative" ]] \
                || [[ "$(shasum -a 256 "$PROJECT_DIR/$queue_profile_relative" | awk '{ print $1 }')" \
                    != "$queue_profile_sha256" ]]; then
            print "Priority queue profile is missing or its pinned SHA-256 is stale: $queue_profile_relative"
            exit 1
        fi
    done < <("$JQ" -r '
        .latePvpPriorityQueue as $queue
        | ([{
              candidateId: $queue.controlCandidateId,
              profileSha256: $queue.controlProfileSha256
            }] + $queue.items)[] as $item
        | (.candidates[] | select(.id == $item.candidateId)) as $candidate
        | [$candidate.profile, $item.profileSha256] | @tsv
    ' "$CANDIDATE_MANIFEST")
    "$JQ" '
        .latePvpPriorityQueue as $queue
        | {
            control_candidate_id: $queue.controlCandidateId,
            control_profile_sha256: $queue.controlProfileSha256,
            minimum_independent_sessions_per_variant: $queue.minimumIndependentSessionsPerVariant,
            items: [$queue.items[] as $item
              | (.candidates[] | select(.id == $item.candidateId)) as $candidate
              | {
                  priority: $item.priority,
                  candidate_id: $item.candidateId,
                  variant: $candidate.variant,
                  profile: $candidate.profile,
                  profile_sha256: $item.profileSha256,
                  target: $item.target,
                  why: $item.why,
                  capacity_gate: (if $item.capacityGate then {
                      candidate_bytes: $item.capacityGate.candidateBytes,
                      largest_measured_synthetic_working_set_bytes:
                          $item.capacityGate.largestMeasuredSyntheticWorkingSetBytes,
                      candidate_to_largest_measured_ratio:
                          $item.capacityGate.candidateToLargestMeasuredRatio,
                      status: $item.capacityGate.status
                    } else null end),
                  correctness_gates: $item.correctnessGates
                }]
          }
    ' "$CANDIDATE_MANIFEST"
    exit 0
fi

if [[ -n "$CANDIDATE_ID" ]]; then
    if ! print -r -- "$CANDIDATE_ID" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
        print "--candidate-id must match [a-z0-9][a-z0-9-]*."
        exit 2
    fi
    if [[ ! -x "$JQ" || ! -f "$CANDIDATE_MANIFEST" ]]; then
        print "Candidate selection requires jq and scripts/performance-candidates.json."
        exit 1
    fi
    typeset candidate_record candidate_profile_relative
    candidate_record="$("$JQ" -r --arg id "$CANDIDATE_ID" '
        [.candidates[] | select(.id == $id)]
        | if length == 1
             and (.[0].profile | type) == "string"
             and (.[0].profile | length) > 0
          then [.[0].variant, .[0].profile] | @tsv
          else empty
          end
    ' "$CANDIDATE_MANIFEST")"
    if [[ -z "$candidate_record" ]]; then
        print "Candidate ID is missing, duplicated, or has no DeviceProfile: $CANDIDATE_ID"
        exit 2
    fi
    IFS=$'\t' read -r CAPTURE_VARIANT candidate_profile_relative \
        <<< "$candidate_record"
    PROFILE_PATH="$PROJECT_DIR/$candidate_profile_relative"
    if [[ ! -f "$PROFILE_PATH" ]]; then
        print "Candidate profile is missing: $PROFILE_PATH"
        exit 1
    fi
    PINNED_PROFILE_SHA256="$("$JQ" -r --arg id "$CANDIDATE_ID" '
        .latePvpPriorityQueue as $queue
        | ([{candidateId: $queue.controlCandidateId,
             profileSha256: $queue.controlProfileSha256}] + $queue.items)
        | map(select(.candidateId == $id))
        | if length == 1 then .[0].profileSha256 else "" end
      ' "$CANDIDATE_MANIFEST")"
    if [[ -n "$PINNED_PROFILE_SHA256" ]] \
            && [[ "$(shasum -a 256 "$PROFILE_PATH" | awk '{ print $1 }')" \
                != "$PINNED_PROFILE_SHA256" ]]; then
        print "The selected late-PvP profile does not match its pinned SHA-256: $CANDIDATE_ID"
        exit 1
    fi
elif (( PRINT_SELECTION == 1 )); then
    print "--print-selection requires --candidate-id."
    exit 2
fi

if (( PRINT_SELECTION == 1 )); then
    "$JQ" -n \
        --arg candidate_id "$CANDIDATE_ID" \
        --arg variant "$CAPTURE_VARIANT" \
        --arg profile_path "$PROFILE_PATH" \
        --arg profile_sha256 "$(shasum -a 256 "$PROFILE_PATH" | awk '{ print $1 }')" \
        --arg pinned_profile_sha256 "$PINNED_PROFILE_SHA256" \
        '{candidate_id: $candidate_id, variant: $variant, profile_path: $profile_path,
          profile_sha256: $profile_sha256,
          pinned_profile_sha256: (if $pinned_profile_sha256 == "" then null
                                  else $pinned_profile_sha256 end)}'
    exit 0
fi

duration_seconds() {
    local value="$1"
    if ! print -r -- "$value" | grep -Eq '^[1-9][0-9]*[hms]$'; then
        print "Duration must use a value such as 90m, 2h, or 600s."
        return 2
    fi
    local number="${value[1,-2]}"
    case "${value[-1]}" in
        h) print $(( number * 3600 )) ;;
        m) print $(( number * 60 )) ;;
        s) print "$number" ;;
    esac
}

is_late_pvp_stage() {
    local stage="$1"
    local stage_number round_number
    if ! print -r -- "$stage" | grep -Eq '^[1-9]-(1[0-9]|[1-9])$'; then
        return 1
    fi
    stage_number="${stage%-*}"
    round_number="${stage#*-}"
    (( stage_number >= MIN_STAGE )) || return 1
    [[ ",$PVP_ROUNDS," == *",$round_number,"* ]]
}

if (( SELF_TEST == 1 )); then
    is_late_pvp_stage 4-1
    is_late_pvp_stage 7-6
    ! is_late_pvp_stage 3-6
    ! is_late_pvp_stage 4-4
    ! is_late_pvp_stage 5-7
    ! is_late_pvp_stage malformed
    print "Late PvP session classifier: OK"
    exit 0
fi

readonly DURATION_SECONDS="$(duration_seconds "$DURATION")"
if (( DURATION_SECONDS < 60 )); then
    print "The late-PvP observer must run for at least 60 seconds."
    exit 2
fi
if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
if [[ "$MIN_STAGE" != <-> ]] || (( MIN_STAGE < 2 || MIN_STAGE > 9 )); then
    print "TFT_LATE_PVP_MIN_STAGE must be an integer from 2 through 9."
    exit 2
fi
if ! print -r -- "$PVP_ROUNDS" | grep -Eq '^[1-9](,[1-9])*$'; then
    print "TFT_LATE_PVP_ROUNDS must be a comma-separated list such as 1,2,3,5,6."
    exit 2
fi
if [[ "$POLL_SECONDS" != <-> ]] || (( POLL_SECONDS < 1 || POLL_SECONDS > 30 )); then
    print "TFT_LATE_PVP_POLL_SECONDS must be from 1 through 30."
    exit 2
fi
if [[ "$CAPTURE_ROUNDS" != <-> ]] || (( CAPTURE_ROUNDS < 1 || CAPTURE_ROUNDS > 10 )); then
    print "TFT_LATE_PVP_CAPTURE_ROUNDS must be from 1 through 10."
    exit 2
fi
if [[ "$CAPTURE_WINDOW_SECONDS" != <-> ]] \
        || (( CAPTURE_WINDOW_SECONDS < 1 || CAPTURE_WINDOW_SECONDS > 10 )); then
    print "TFT_LATE_PVP_WINDOW_SECONDS must be from 1 through 10."
    exit 2
fi
if [[ "$MAX_CAPTURES" != <-> ]] || (( MAX_CAPTURES < 1 || MAX_CAPTURES > 30 )); then
    print "TFT_LATE_PVP_MAX_CAPTURES must be from 1 through 30."
    exit 2
fi
if [[ "$PROFILE_FIRST_CAPTURE" != 0 && "$PROFILE_FIRST_CAPTURE" != 1 ]]; then
    print "TFT_LATE_PVP_PROFILE_FIRST_CAPTURE must be 0 or 1."
    exit 2
fi
if [[ "$PROFILE_SECONDS" != <-> ]] || (( PROFILE_SECONDS < 1 || PROFILE_SECONDS > 5 )); then
    print "TFT_LATE_PVP_PROFILE_SECONDS must be from 1 through 5."
    exit 2
fi
if ! print -r -- "$CAPTURE_VARIANT" | grep -Eq '^[a-z0-9][a-z0-9_-]*$'; then
    print "TFT_LATE_PVP_VARIANT must match [a-z0-9][a-z0-9_-]*."
    exit 2
fi
if [[ ! -x "$JQ" || ! -x "$FRAME_CAPTURE" || ! -x "$CLASSIFIER_BUILD" \
        || ! -x "$THREAD_SNAPSHOT" || ! -x "$THREAD_COMPARE" ]]; then
    print "The late-PvP observer is missing jq or a required project script."
    exit 1
fi
if [[ ! -f "$PROFILE_PATH" ]]; then
    print "TFT_PROFILE_PATH does not point to an existing profile: $PROFILE_PATH"
    exit 2
fi

ADB="$(tft_resolve_adb)"
readonly ADB
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null
if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The TFT AVD is not connected on $SERIAL. Start Performance Max first."
    exit 1
fi
readonly EXPECTED_PROFILE_SHA256="$(shasum -a 256 "$PROFILE_PATH" | awk '{ print $1 }')"
readonly ACTIVE_PROFILE_DESTINATION="/data/user/0/$PACKAGE/files/UnrealGame/TFT/TFT/Saved/Config/Android/DeviceProfiles.ini"
readonly ACTIVE_PROFILE_PID="$(
    "$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null \
        | tr -d '\r' | awk '{ print $1 }'
)"
if [[ "$ACTIVE_PROFILE_PID" != <-> ]]; then
    print "The TFT process is not running; active DeviceProfile cannot be attested."
    exit 1
fi
readonly ACTIVE_PROFILE_SHA256="$(
    "$ADB" -s "$SERIAL" shell sha256sum "$ACTIVE_PROFILE_DESTINATION" 2>/dev/null \
        | tr -d '\r' | awk '{ print $1 }'
)"
readonly ACTIVE_PROFILE_MOUNT_COUNT="$(
    "$ADB" -s "$SERIAL" shell cat "/proc/$ACTIVE_PROFILE_PID/mountinfo" 2>/dev/null \
        | tr -d '\r' \
        | awk -v target="$ACTIVE_PROFILE_DESTINATION" \
            '$5 == target { count++ } END { print count + 0 }'
)"
if [[ "$ACTIVE_PROFILE_SHA256" != "$EXPECTED_PROFILE_SHA256" \
        || "$ACTIVE_PROFILE_MOUNT_COUNT" != "1" ]]; then
    print "The selected DeviceProfile is not the single active TFT bind mount."
    print "Expected SHA-256: $EXPECTED_PROFILE_SHA256"
    print "Active SHA-256: ${ACTIVE_PROFILE_SHA256:-<unreadable>}; mounts=$ACTIVE_PROFILE_MOUNT_COUNT"
    exit 1
fi

active_profile_still_attested() {
    local current_pid current_sha256 current_mount_count
    current_pid="$(
        "$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null \
            | tr -d '\r' | awk '{ print $1 }'
    )"
    if [[ "$current_pid" == <-> ]]; then
        current_sha256="$(
            "$ADB" -s "$SERIAL" shell sha256sum "$ACTIVE_PROFILE_DESTINATION" \
                2>/dev/null | tr -d '\r' | awk '{ print $1 }'
        )"
        current_mount_count="$(
            "$ADB" -s "$SERIAL" shell cat "/proc/$current_pid/mountinfo" \
                2>/dev/null | tr -d '\r' \
                | awk -v target="$ACTIVE_PROFILE_DESTINATION" \
                    '$5 == target { count++ } END { print count + 0 }'
        )"
    else
        current_sha256=""
        current_mount_count=0
    fi
    if [[ "$current_pid" != "$ACTIVE_PROFILE_PID" \
            || "$current_sha256" != "$EXPECTED_PROFILE_SHA256" \
            || "$current_mount_count" != "1" ]]; then
        print -u2 "The active TFT process or DeviceProfile changed during the observer session."
        print -u2 "Expected pid=$ACTIVE_PROFILE_PID sha256=$EXPECTED_PROFILE_SHA256 mounts=1"
        print -u2 "Active pid=${current_pid:-<missing>} sha256=${current_sha256:-<unreadable>} mounts=$current_mount_count"
        return 1
    fi
}
if [[ "$CLASSIFIER" == "$DEFAULT_CLASSIFIER" \
        && ( ! -x "$CLASSIFIER" || "$CLASSIFIER_SOURCE" -nt "$CLASSIFIER" ) ]]; then
    TFT_SCREEN_CLASSIFIER_BINARY="$CLASSIFIER" "$CLASSIFIER_BUILD" >/dev/null
fi

readonly SESSION_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
readonly SESSION_DIR="$SESSION_ROOT/$SESSION_STAMP"
readonly CAPTURE_ROOT="$SESSION_DIR/captures"
readonly EVENTS="$SESSION_DIR/events.jsonl"
readonly CURRENT_IMAGE="$SESSION_DIR/current.png"
readonly CURRENT_CLASSIFICATION="$SESSION_DIR/current.json"
readonly START_EPOCH="$(date +%s)"
readonly DEADLINE_EPOCH=$(( START_EPOCH + DURATION_SECONDS ))
mkdir -p "$CAPTURE_ROOT"

typeset SESSION_STATUS=running
typeset LAST_OBSERVED=""
typeset FINALIZED=0
integer CAPTURE_COUNT=0
integer ATTEMPT_COUNT=0
integer PROFILE_CAPTURED=0
typeset -A ATTEMPTED_STAGES

"$JQ" -n \
    --arg utc "$SESSION_STAMP" \
    --arg serial "$SERIAL" \
    --arg variant "$CAPTURE_VARIANT" \
    --arg candidate_id "$CANDIDATE_ID" \
    --arg renderer "$RENDERER_HINT" \
    --arg guest_gl "$GUEST_GL_DRIVER_HINT" \
    --arg profile "$PROFILE_PATH" \
    --arg profile_sha256 "$EXPECTED_PROFILE_SHA256" \
    --arg active_profile_sha256 "$ACTIVE_PROFILE_SHA256" \
    --arg active_profile_destination "$ACTIVE_PROFILE_DESTINATION" \
    --argjson active_profile_mount_count "$ACTIVE_PROFILE_MOUNT_COUNT" \
    --argjson active_profile_pid "$ACTIVE_PROFILE_PID" \
    --arg rounds "$PVP_ROUNDS" \
    --argjson min_stage "$MIN_STAGE" \
    --argjson duration_seconds "$DURATION_SECONDS" \
    --argjson capture_rounds "$CAPTURE_ROUNDS" \
    --argjson window_seconds "$CAPTURE_WINDOW_SECONDS" \
    --argjson profile_first_capture "$PROFILE_FIRST_CAPTURE" \
    --argjson profile_seconds "$PROFILE_SECONDS" \
    '{
        schema_version: 1,
        utc: $utc,
        serial: $serial,
        mode: "passive_late_pvp",
        interaction: "none",
        pvp_round_heuristic: {minimum_stage: $min_stage, included_rounds: ($rounds | split(","))},
        capture: {candidate_id: (if $candidate_id == "" then null else $candidate_id end),
            variant: $variant, renderer_hint: $renderer, guest_gl_driver_hint: $guest_gl,
            profile_path: $profile, profile_sha256: $profile_sha256,
            active_profile_attestation: {
                process_pid: $active_profile_pid,
                destination: $active_profile_destination,
                mount_count: $active_profile_mount_count,
                sha256: $active_profile_sha256,
                passed: true
            },
            rounds: $capture_rounds, window_seconds: $window_seconds},
        profiling: {first_accepted_capture: ($profile_first_capture == 1),
            duration_seconds: $profile_seconds, timing: "after_pacing_window",
            scheduler_snapshots: "immediately before and after simpleperf"},
        duration_seconds: $duration_seconds
    }' > "$SESSION_DIR/manifest.json"

record_event() {
    local event="$1"
    local detail="${2:-}"
    "$JQ" -nc \
        --arg utc "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg event "$event" \
        --arg detail "$detail" \
        '{utc: $utc, event: $event, detail: $detail}' >> "$EVENTS"
}

finalize_session() {
    local trapped_exit_code=$?
    local exit_code="${1:-$trapped_exit_code}"
    (( FINALIZED == 0 )) || return
    FINALIZED=1
    trap - EXIT HUP INT TERM
    if [[ "$SESSION_STATUS" == running ]]; then
        if (( exit_code == 0 )); then
            SESSION_STATUS=deadline
        else
            SESSION_STATUS=interrupted
        fi
    fi
    typeset -a summaries profile_summaries
    integer profile_attempted_count=0
    integer profile_accepted_count=0
    integer raw_callgraph_profile_count=0
    summaries=()
    typeset accepted_marker accepted_summary
    for accepted_marker in "$CAPTURE_ROOT"/*/.late-pvp-accepted(N); do
        accepted_summary="${accepted_marker:h}/summary.json"
        [[ -f "$accepted_summary" ]] && summaries+=("$accepted_summary")
    done
    profile_summaries=("$CAPTURE_ROOT"/*/profile/summary.json(N))
    profile_attempted_count=${#profile_summaries}
    typeset profile_summary_path raw_profile_path declared_raw_sha actual_raw_sha
    for profile_summary_path in "${profile_summaries[@]}"; do
        if "$JQ" -e '
                .accepted == true
                and .simpleperf_data.pull_status == 0
                and .simpleperf_data.size_bytes > 0
                and .simpleperf_data.path == "simpleperf.data"
                and (.simpleperf_data.sha256 | test("^[0-9a-f]{64}$"))
              ' "$profile_summary_path" >/dev/null 2>&1; then
            raw_profile_path="${profile_summary_path:h}/simpleperf.data"
            declared_raw_sha="$("$JQ" -r '.simpleperf_data.sha256' \
                "$profile_summary_path")"
            actual_raw_sha=""
            if [[ -s "$raw_profile_path" ]]; then
                actual_raw_sha="$(shasum -a 256 "$raw_profile_path" | awk '{ print $1 }')"
            fi
            if [[ "$actual_raw_sha" == "$declared_raw_sha" ]]; then
                (( profile_accepted_count += 1 ))
                (( raw_callgraph_profile_count += 1 ))
            fi
        fi
    done
    if (( ${#summaries} > 0 )); then
        "$JQ" -s \
            --arg status "$SESSION_STATUS" \
            --argjson attempted "$ATTEMPT_COUNT" \
            --argjson accepted "$CAPTURE_COUNT" \
            --argjson profile_attempted "$profile_attempted_count" \
            --argjson profile_accepted "$profile_accepted_count" \
            --argjson raw_callgraph_profiles "$raw_callgraph_profile_count" \
            '{
                schema_version: 1,
                status: $status,
                attempted_captures: $attempted,
                accepted_captures: $accepted,
                profiling: {
                    attempted_profiles: $profile_attempted,
                    accepted_profiles: $profile_accepted,
                    raw_callgraph_profiles: $raw_callgraph_profiles,
                    raw_callgraph_integrity: "reverified_at_session_finalize",
                    promotion_gate: false
                },
                stages: map(.semantic_gate.stage_before),
                aggregate: {
                    mean_fps: (map(.pacing.fps) | add / length),
                    minimum_fps: (map(.pacing.fps) | min),
                    worst_p95_ms: (map(.pacing.p95_ms) | max),
                    worst_p99_ms: (map(.pacing.p99_ms) | max),
                    frames_over_50_ms: (map(.pacing.frames_over_ms["50"]) | add)
                },
                captures: .
            }' "${summaries[@]}" > "$SESSION_DIR/summary.json"
    else
        "$JQ" -n \
            --arg status "$SESSION_STATUS" \
            --argjson attempted "$ATTEMPT_COUNT" \
            --argjson profile_attempted "$profile_attempted_count" \
            --argjson profile_accepted "$profile_accepted_count" \
            --argjson raw_callgraph_profiles "$raw_callgraph_profile_count" \
            '{schema_version: 1, status: $status, attempted_captures: $attempted,
              accepted_captures: 0,
              profiling: {
                  attempted_profiles: $profile_attempted,
                  accepted_profiles: $profile_accepted,
                  raw_callgraph_profiles: $raw_callgraph_profiles,
                  raw_callgraph_integrity: "reverified_at_session_finalize",
                  promotion_gate: false
              },
              stages: [], aggregate: null, captures: []}' \
            > "$SESSION_DIR/summary.json"
    fi
    record_event session_complete "status=$SESSION_STATUS accepted=$CAPTURE_COUNT attempted=$ATTEMPT_COUNT"
    print "Late-PvP session: $SESSION_STATUS; accepted=$CAPTURE_COUNT attempted=$ATTEMPT_COUNT"
    print "Artifacts: $SESSION_DIR"
    return "$exit_code"
}
trap finalize_session EXIT
trap 'SESSION_STATUS=interrupted; exit 130' HUP INT TERM

game_is_foreground() {
    "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
        | tr -d '\r' \
        | grep -F 'topResumedActivity=' \
        | grep -Fq "$GAME_ACTIVITY"
}

observe_screen() {
    game_is_foreground || return 1
    "$ADB" -s "$SERIAL" exec-out screencap -p > "$CURRENT_IMAGE.next" || return 1
    mv -f "$CURRENT_IMAGE.next" "$CURRENT_IMAGE"
    "$CLASSIFIER" "$CURRENT_IMAGE" > "$CURRENT_CLASSIFICATION.next" \
        2> "$SESSION_DIR/classifier.stderr" || return 1
    mv -f "$CURRENT_CLASSIFICATION.next" "$CURRENT_CLASSIFICATION"
}

capture_late_profile() {
    local stage="$1"
    local capture_dir="$2"
    local profile_dir="$capture_dir/profile"
    local game_pid remote_data simpleperf_event
    local before_state before_stage before_phase after_state after_stage after_phase
    local simpleperf_record_status=127 simpleperf_flat_report_status=127
    local simpleperf_children_report_status=127 simpleperf_data_pull_status=127
    local simpleperf_data_sha256=""
    local simpleperf_data_size_bytes=0
    local thread_before_status=127 thread_after_status=127 thread_compare_status=127
    local profile_attestation_after_status=127

    observe_screen || {
        record_event profile_skipped "stage=$stage reason=before_screen_unavailable"
        return 1
    }
    before_state="$("$JQ" -r '.state // "unknown"' "$CURRENT_CLASSIFICATION")"
    before_stage="$("$JQ" -r '.stage // ""' "$CURRENT_CLASSIFICATION")"
    before_phase="$("$JQ" -r '.phase // ""' "$CURRENT_CLASSIFICATION")"
    if [[ "$before_state" != battle || "$before_stage" != "$stage" \
            || "$before_phase" != combat ]]; then
        record_event profile_skipped \
            "stage=$stage reason=semantic_gate_closed state=$before_state observed_stage=${before_stage:-none} phase=${before_phase:-none}"
        return 1
    fi

    game_pid="$(
        "$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null \
            | tr -d '\r' | awk '{ print $1 }'
    )"
    if [[ "$game_pid" != <-> ]]; then
        record_event profile_skipped "stage=$stage reason=game_pid_unavailable"
        return 1
    fi

    mkdir -p "$profile_dir"
    cp "$CURRENT_IMAGE" "$profile_dir/before.png"
    cp "$CURRENT_CLASSIFICATION" "$profile_dir/before.json"
    remote_data="/data/local/tmp/mactician-late-pvp-${game_pid}.data"
    simpleperf_event="$({
        "$ADB" -s "$SERIAL" shell simpleperf list sw 2>/dev/null \
            | tr -d '\r' | awk '$1 == "cpu-clock" { print $1; exit }'
    } || true)"
    [[ -n "$simpleperf_event" ]] || simpleperf_event=task-clock

    record_event profile_start "stage=$stage duration_seconds=$PROFILE_SECONDS"
    set +e
    TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT" TFT_SERIAL="$SERIAL" \
        "$THREAD_SNAPSHOT" "$game_pid" "$profile_dir/thread-scheduler-before.json" \
        > "$profile_dir/thread-scheduler-before.log" 2>&1
    thread_before_status=$?
    "$ADB" -s "$SERIAL" shell simpleperf record \
        -e "$simpleperf_event" -g --duration "$PROFILE_SECONDS" \
        -p "$game_pid" -o "$remote_data" \
        > "$profile_dir/simpleperf-record.log" 2>&1
    simpleperf_record_status=$?
    TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT" TFT_SERIAL="$SERIAL" \
        "$THREAD_SNAPSHOT" "$game_pid" "$profile_dir/thread-scheduler-after.json" \
        > "$profile_dir/thread-scheduler-after.log" 2>&1
    thread_after_status=$?
    if (( thread_before_status == 0 && thread_after_status == 0 )); then
        "$THREAD_COMPARE" \
            "$profile_dir/thread-scheduler-before.json" \
            "$profile_dir/thread-scheduler-after.json" \
            "$profile_dir/thread-scheduler-comparison.json" \
            > "$profile_dir/thread-scheduler-comparison.log" 2>&1
        thread_compare_status=$?
    fi
    if active_profile_still_attested; then
        profile_attestation_after_status=0
    else
        profile_attestation_after_status=1
    fi
    set -e
    PROFILE_CAPTURED=1

    # Freeze the post-profile semantic gate before generating the report. The
    # report itself can take longer than the bounded sampling window.
    if observe_screen; then
        cp "$CURRENT_IMAGE" "$profile_dir/after.png"
        cp "$CURRENT_CLASSIFICATION" "$profile_dir/after.json"
        after_state="$("$JQ" -r '.state // "unknown"' "$CURRENT_CLASSIFICATION")"
        after_stage="$("$JQ" -r '.stage // ""' "$CURRENT_CLASSIFICATION")"
        after_phase="$("$JQ" -r '.phase // ""' "$CURRENT_CLASSIFICATION")"
    else
        after_state=unknown
        after_stage=""
        after_phase=""
    fi

    set +e
    if (( simpleperf_record_status == 0 )); then
        "$ADB" -s "$SERIAL" shell simpleperf report -i "$remote_data" \
            --sort comm,pid,tid,symbol \
            > "$profile_dir/simpleperf-report.txt" \
            2> "$profile_dir/simpleperf-report.stderr"
        simpleperf_flat_report_status=$?
        "$ADB" -s "$SERIAL" shell simpleperf report -i "$remote_data" \
            --children --sort comm,pid,tid,dso,symbol,vaddr_in_file \
            > "$profile_dir/simpleperf-children-report.txt" \
            2> "$profile_dir/simpleperf-children-report.stderr"
        simpleperf_children_report_status=$?
        "$ADB" -s "$SERIAL" pull "$remote_data" "$profile_dir/simpleperf.data" \
            > "$profile_dir/simpleperf-pull.log" 2>&1
        simpleperf_data_pull_status=$?
        if (( simpleperf_data_pull_status == 0 )); then
            simpleperf_data_size_bytes="$(
                wc -c < "$profile_dir/simpleperf.data" 2>/dev/null | tr -d ' '
            )"
            [[ "$simpleperf_data_size_bytes" == <-> ]] \
                || simpleperf_data_size_bytes=0
            if (( simpleperf_data_size_bytes > 0 )); then
                simpleperf_data_sha256="$(
                    shasum -a 256 "$profile_dir/simpleperf.data" | awk '{ print $1 }'
                )"
            else
                rm -f "$profile_dir/simpleperf.data"
            fi
        else
            rm -f "$profile_dir/simpleperf.data"
        fi
    fi
    "$ADB" -s "$SERIAL" shell rm -f "$remote_data" >/dev/null 2>&1
    set -e

    "$JQ" -n \
        --arg stage "$stage" \
        --arg game_pid "$game_pid" \
        --arg simpleperf_event "$simpleperf_event" \
        --arg before_state "$before_state" \
        --arg before_stage "$before_stage" \
        --arg before_phase "$before_phase" \
        --arg after_state "$after_state" \
        --arg after_stage "$after_stage" \
        --arg after_phase "$after_phase" \
        --arg simpleperf_data_sha256 "$simpleperf_data_sha256" \
        --argjson duration_seconds "$PROFILE_SECONDS" \
        --argjson simpleperf_record_status "$simpleperf_record_status" \
        --argjson simpleperf_flat_report_status "$simpleperf_flat_report_status" \
        --argjson simpleperf_children_report_status "$simpleperf_children_report_status" \
        --argjson simpleperf_data_pull_status "$simpleperf_data_pull_status" \
        --argjson simpleperf_data_size_bytes "$simpleperf_data_size_bytes" \
        --argjson profile_attestation_after_status "$profile_attestation_after_status" \
        --argjson thread_before_status "$thread_before_status" \
        --argjson thread_after_status "$thread_after_status" \
        --argjson thread_compare_status "$thread_compare_status" \
        '{
            schema_version: 1,
            stage: $stage,
            game_pid: $game_pid,
            duration_seconds: $duration_seconds,
            simpleperf_event: $simpleperf_event,
            simpleperf_status: $simpleperf_flat_report_status,
            simpleperf: {
                record_status: $simpleperf_record_status,
                flat_report: {
                    path: "simpleperf-report.txt",
                    status: $simpleperf_flat_report_status,
                    attribution: "exclusive sampled leaves"
                },
                caller_inclusive_report: {
                    path: "simpleperf-children-report.txt",
                    status: $simpleperf_children_report_status,
                    attribution: "children overhead accumulated from recorded call chains with file-relative addresses",
                    promotion_gate: false
                }
            },
            simpleperf_data: {
                path: "simpleperf.data",
                pull_status: $simpleperf_data_pull_status,
                size_bytes: $simpleperf_data_size_bytes,
                sha256: $simpleperf_data_sha256,
                purpose: "retain call chains for caller-inclusive offline attribution"
            },
            privacy: "symbols_and_raw_perf_no_game_log",
            timing: "after_pacing_window",
            active_profile_attestation: {
                after_record_status: $profile_attestation_after_status,
                passed: ($profile_attestation_after_status == 0)
            },
            thread_scheduler: {
                before_status: $thread_before_status,
                after_status: $thread_after_status,
                comparison_status: $thread_compare_status,
                available: ($thread_compare_status == 0),
                comparison: "thread-scheduler-comparison.json",
                privacy: "procfs scheduler counters and thread names only"
            },
            semantic_gate: {
                before: {state: $before_state, stage: $before_stage, phase: $before_phase},
                after: {state: $after_state, stage: $after_stage, phase: $after_phase},
                valid: ($before_state == "battle" and $after_state == "battle"
                    and $before_stage == $stage and $after_stage == $stage
                    and $before_phase == "combat" and $after_phase == "combat")
            },
            accepted: ($simpleperf_record_status == 0
                and $simpleperf_flat_report_status == 0
                and $simpleperf_data_pull_status == 0
                and $simpleperf_data_size_bytes > 0
                and $profile_attestation_after_status == 0
                and ($simpleperf_data_sha256 | test("^[0-9a-f]{64}$"))
                and $before_state == "battle"
                and $after_state == "battle" and $before_stage == $stage
                and $after_stage == $stage and $before_phase == "combat"
                and $after_phase == "combat")
        }' > "$profile_dir/summary.json.next"
    mv -f "$profile_dir/summary.json.next" "$profile_dir/summary.json"

    if "$JQ" -e '.accepted == true' "$profile_dir/summary.json" >/dev/null; then
        record_event profile_accepted "stage=$stage dir=$profile_dir"
        print "Accepted $stage callgraph-capable guest profile: $profile_dir"
        return 0
    fi
    record_event profile_rejected \
        "stage=$stage record_status=$simpleperf_record_status flat_report_status=$simpleperf_flat_report_status children_report_status=$simpleperf_children_report_status data_pull_status=$simpleperf_data_pull_status profile_attestation_after_status=$profile_attestation_after_status state_after=$after_state stage_after=${after_stage:-none} phase_after=${after_phase:-none}"
    print "Rejected $stage profile because recording failed or the combat gate changed."
    return 1
}

capture_stage() {
    local stage="$1"
    local scene="late-pvp-stage-$stage"
    local capture_log="$SESSION_DIR/capture-${stage}.log"
    local capture_dir=""
    local capture_status=0
    if ! active_profile_still_attested; then
        SESSION_STATUS=profile_attestation_failed
        record_event profile_attestation_failed "stage=$stage"
        return 1
    fi
    (( ATTEMPT_COUNT += 1 ))
    ATTEMPTED_STAGES[$stage]=1
    record_event capture_start "stage=$stage"

    set +e
    TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT" \
    TFT_SERIAL="$SERIAL" \
    TFT_SCENE="$scene" \
    TFT_VARIANT="$CAPTURE_VARIANT" \
    TFT_MEASUREMENT_ROOT="$CAPTURE_ROOT" \
    TFT_MEASUREMENT_ROUNDS="$CAPTURE_ROUNDS" \
    TFT_MEASUREMENT_WINDOW_SECONDS="$CAPTURE_WINDOW_SECONDS" \
    TFT_EXPECTED_STAGE="$stage" \
    TFT_EXPECTED_PHASE=combat \
    TFT_SEMANTIC_BEFORE_IMAGE="$CURRENT_IMAGE" \
    TFT_RENDERER="$RENDERER_HINT" \
    TFT_GUEST_GL_DRIVER="$GUEST_GL_DRIVER_HINT" \
    TFT_PROFILE_PATH="$PROFILE_PATH" \
        "$FRAME_CAPTURE" > "$capture_log" 2>&1
    capture_status=$?
    set -e

    capture_dir="$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d \
        -name "*__${scene}__${CAPTURE_VARIANT}" -print 2>/dev/null | sort | tail -n 1)"
    if (( capture_status == 0 )) && [[ -n "$capture_dir" && -f "$capture_dir/summary.json" ]]; then
        if ! active_profile_still_attested; then
            SESSION_STATUS=profile_attestation_failed
            record_event profile_attestation_failed \
                "stage=$stage timing=after_pacing_window"
            return 1
        fi
        : > "$capture_dir/.late-pvp-accepted"
        (( CAPTURE_COUNT += 1 ))
        record_event capture_accepted "stage=$stage dir=$capture_dir"
        local fps p95 p99
        fps="$("$JQ" -r '.pacing.fps' "$capture_dir/summary.json")"
        p95="$("$JQ" -r '.pacing.p95_ms' "$capture_dir/summary.json")"
        p99="$("$JQ" -r '.pacing.p99_ms' "$capture_dir/summary.json")"
        print "Accepted $stage: ${fps} FPS, p95=${p95} ms, p99=${p99} ms"
        if (( PROFILE_FIRST_CAPTURE == 1 && PROFILE_CAPTURED == 0 )); then
            capture_late_profile "$stage" "$capture_dir" || true
        fi
    else
        record_event capture_rejected "stage=$stage exit_status=$capture_status dir=${capture_dir:-none}"
        print "Rejected $stage capture because the semantic window changed; continuing."
    fi
}

record_event session_start "deadline_epoch=$DEADLINE_EPOCH"
print "Passive late-PvP observer started; it never sends input to the game."
print "Target: stages ${MIN_STAGE}+ rounds $PVP_ROUNDS, up to $MAX_CAPTURES captures."
print "Artifacts: $SESSION_DIR"

while (( $(date +%s) < DEADLINE_EPOCH )); do
    if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        observation="device_disconnected"
    elif ! observe_screen; then
        observation="game_not_foreground"
    else
        state="$("$JQ" -r '.state // "unknown"' "$CURRENT_CLASSIFICATION")"
        stage="$("$JQ" -r '.stage // ""' "$CURRENT_CLASSIFICATION")"
        phase="$("$JQ" -r '.phase // ""' "$CURRENT_CLASSIFICATION")"
        observation="${state}:${stage:-none}:${phase:-none}"
        if [[ "$state" == battle && "$phase" == combat ]] \
                && is_late_pvp_stage "$stage" \
                && [[ -z "${ATTEMPTED_STAGES[$stage]:-}" ]]; then
            print "Heavy PvP heuristic matched $stage; capturing an input-free pacing window."
            if ! capture_stage "$stage"; then
                if [[ "$SESSION_STATUS" == profile_attestation_failed ]]; then
                    finalize_session 1 || true
                    exit 1
                fi
            fi
            if (( CAPTURE_COUNT >= MAX_CAPTURES )); then
                SESSION_STATUS=max_captures
                break
            fi
        fi
    fi
    if [[ "$observation" != "$LAST_OBSERVED" ]]; then
        record_event observation "$observation"
        LAST_OBSERVED="$observation"
    fi
    sleep "$POLL_SECONDS"
done

if [[ "$SESSION_STATUS" == running ]]; then
    SESSION_STATUS=deadline
fi
