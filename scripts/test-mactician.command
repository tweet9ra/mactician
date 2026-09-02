#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h:h}"
readonly LAUNCHER_DIR="$PROJECT_DIR/launcher"
readonly SPARKLE_ROOT="$("$PROJECT_DIR/scripts/prepare-sparkle.command")"
readonly TEST_BINARY="$(mktemp -t mactician-tests)"
readonly LIFECYCLE_ROOT="$(mktemp -d -t mactician-lifecycle)"
readonly HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    arm64|x86_64) ;;
    *)
        print -u2 "Unsupported unit-test host architecture: $HOST_ARCH"
        exit 2
        ;;
esac
readonly TEST_TARGET="$HOST_ARCH-apple-macosx12.0"
cleanup() {
    local exit_code=$?
    rm -f "$TEST_BINARY"
    rm -rf "$LIFECYCLE_ROOT"
    return "$exit_code"
}
trap cleanup EXIT

jq -e '
    .schemaVersion == 1
    and (.components | length) == 3
    and (.game.apks | length) == 4
    and (
        .components[]
        | select(.id == "system-image")
        | .version == "android-36-google_apis_playstore-arm64-v8a-r07"
            and .url == "https://dl.google.com/android/repository/sys-img/google_apis_playstore/arm64-v8a-36_r07.zip"
            and .size == 1886527965
            and .sha256 == "ddb0feff5c23db9f42ceabd28f6542e8ffec639abf818bf6831a2658e6cf7905"
            and .installPath == "sdk/system-images/android-36/google_apis_playstore/arm64-v8a"
    )
' \
    "$LAUNCHER_DIR/Resources/release-manifest.json" >/dev/null
plutil -lint "$LAUNCHER_DIR/Info.plist" >/dev/null
plutil -lint "$LAUNCHER_DIR/Resources/EmulatorHost-Info.plist" >/dev/null
plutil -lint "$LAUNCHER_DIR/Resources/QEMU-Hypervisor.entitlements" >/dev/null
plutil -lint "$LAUNCHER_DIR/Resources/en.lproj/Localizable.strings" >/dev/null
plutil -lint "$LAUNCHER_DIR/Resources/ru.lproj/Localizable.strings" >/dev/null
typeset -a launcher_localizations
launcher_localizations=("$LAUNCHER_DIR"/Resources/*.lproj(N:t))
if (( ${#launcher_localizations} != 2 )) \
        || [[ "$launcher_localizations[1]" != "en.lproj" ]] \
        || [[ "$launcher_localizations[2]" != "ru.lproj" ]]; then
    print -u2 "Mactician must ship the English and Russian localization resources."
    exit 1
fi
typeset syntax_script
for syntax_script in \
        "$LAUNCHER_DIR/Resources/launcher-runtime.command" \
        "$LAUNCHER_DIR/Resources/emulator-host.command" \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        "$PROJECT_DIR/run-tft-angle-opengl.command" \
        "$PROJECT_DIR/run-tft-google-play.command" \
        "$PROJECT_DIR/scripts/run-asg-experiment.command" \
        "$PROJECT_DIR/scripts/run-autonomous-trial-benchmark.command" \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        "$PROJECT_DIR/scripts/capture-android-thread-snapshot.command" \
        "$PROJECT_DIR/scripts/compare-android-thread-snapshots.command" \
        "$PROJECT_DIR/scripts/run-performance-campaign.command" \
        "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        "$PROJECT_DIR/scripts/run-android-gles-buffer-stress.command" \
        "$PROJECT_DIR/scripts/run-android-gles-draw-stress.command" \
        "$PROJECT_DIR/scripts/run-android-gles-ubo-stress.command" \
        "$PROJECT_DIR/scripts/build-android-gles-buffer-stress-app.command" \
        "$PROJECT_DIR/scripts/build-android-gles-draw-stress-app.command" \
        "$PROJECT_DIR/scripts/build-android-gles-ubo-stress-app.command" \
        "$PROJECT_DIR/scripts/summarize-android-gles-ubo-campaign.command" \
        "$PROJECT_DIR/scripts/build-unreal-cvar-query-overlay.command" \
        "$PROJECT_DIR/scripts/extract-unreal-cvars.command" \
        "$PROJECT_DIR/scripts/summarize-simpleperf-report.command" \
        "$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
        "$PROJECT_DIR/scripts/audit-unreal-profile-startup.command" \
        "$PROJECT_DIR/scripts/read-unreal-cvar-storage.command" \
        "$PROJECT_DIR/scripts/run-host-angle-capability-probe.command" \
        "$PROJECT_DIR/scripts/summarize-android-ui-transport.command" \
        "$PROJECT_DIR/scripts/audit-native-gles-coverage.command" \
        "$PROJECT_DIR/scripts/build-android-egl-capability-probe.command" \
        "$PROJECT_DIR/scripts/watch-root-pso.command" \
        "$PROJECT_DIR/scripts/update-tft-performance-mode.command" \
        "$PROJECT_DIR/scripts/android-environment.sh" \
        "$PROJECT_DIR/scripts/prepare-sparkle.command" \
        "$PROJECT_DIR/scripts/publish-mactician-update.command" \
        "$PROJECT_DIR/scripts/publish-game-update.command" \
        "$PROJECT_DIR/scripts/build-mactician.command" \
        "$PROJECT_DIR/scripts/integration-test-mactician.command"; do
    zsh -o NO_BG_NICE -n "$syntax_script"
done

readonly PERFORMANCE_MODE_FIXTURE="$LIFECYCLE_ROOT/GameUserSettings.ini"
readonly PERFORMANCE_MODE_ENABLED="$LIFECYCLE_ROOT/GameUserSettings.enabled.ini"
readonly PERFORMANCE_MODE_DISABLED="$LIFECYCLE_ROOT/GameUserSettings.disabled.ini"
cat > "$PERFORMANCE_MODE_FIXTURE" <<'PERFORMANCE_MODE_EOF'
[/Script/TFTSettings.TFTUserSettings]
FrameRateLimit=60.000000
GraphicsSettings=(bBatterySaverMode=False,bPerformanceMode=False,PreferredFrameRateLimit=60.000000,QualitySettingPreset=0)

[ScalabilityGroups]
sg.ResolutionQuality=67
PERFORMANCE_MODE_EOF
"$PROJECT_DIR/scripts/update-tft-performance-mode.command" \
    1 "$PERFORMANCE_MODE_FIXTURE" > "$PERFORMANCE_MODE_ENABLED"
"$PROJECT_DIR/scripts/update-tft-performance-mode.command" \
    0 "$PERFORMANCE_MODE_ENABLED" > "$PERFORMANCE_MODE_DISABLED"
if ! grep -Fqx \
        'GraphicsSettings=(bBatterySaverMode=False,bPerformanceMode=True,PreferredFrameRateLimit=60.000000,QualitySettingPreset=0)' \
        "$PERFORMANCE_MODE_ENABLED" \
        || ! cmp -s "$PERFORMANCE_MODE_FIXTURE" "$PERFORMANCE_MODE_DISABLED"; then
    print -u2 "TFT Performance Mode settings transform regressed."
    exit 1
fi

readonly UNREAL_CVAR_STORAGE_FIXTURE="$PROJECT_DIR/scripts/test-fixtures/unreal-cvar-storage/fake-adb.command"
readonly UNREAL_CVAR_STORAGE_RESULT="$LIFECYCLE_ROOT/unreal-cvar-storage.json"
TFT_ADB="$UNREAL_CVAR_STORAGE_FIXTURE" \
    "$PROJECT_DIR/scripts/read-unreal-cvar-storage.command" \
    > "$UNREAL_CVAR_STORAGE_RESULT"
if ! jq -e '
    .schema_version == 1
    and .source.process_id == 4242
    and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
    and .source.load_bias == "0x1000000000"
    and (.values | length) == 9
    and ([.values[] | select(.cvar == "OpenGL.UBOPoolSize")][0].value_u32 == 16777216)
    and ([.values[] | select(.cvar == "OpenGL.UBODirectWrite")][0].value_u32 == 0)
    and ([.values[] | select(.cvar == "OpenGL.UseMapBuffer")][0].value_u32 == 1)
' "$UNREAL_CVAR_STORAGE_RESULT" >/dev/null; then
    print -u2 "Unreal live CVar storage audit contract regressed."
    jq . "$UNREAL_CVAR_STORAGE_RESULT" >&2
    exit 1
fi
readonly SIMPLEPERF_FIXTURE="$PROJECT_DIR/scripts/test-fixtures/simpleperf/report.txt"
readonly SIMPLEPERF_SUMMARY="$LIFECYCLE_ROOT/simpleperf-summary.json"
"$PROJECT_DIR/scripts/summarize-simpleperf-report.command" \
    "$SIMPLEPERF_FIXTURE" "$SIMPLEPERF_SUMMARY"
if ! jq -e '
    .schema_version == 1
    and .source.event == "cpu-clock"
    and .source.samples == 1000
    and .source.event_count == 250000000
    and .source.exclusive_rows == 7
    and .reported_overhead_sum_percent == 25.5
    and .top_threads[0] == {name: "RHIThread", overhead_percent: 18.5}
    and .top_threads[1] == {name: "Foreground Work", overhead_percent: 6}
    and (.symbol_categories
        | map({key: .name, value: .overhead_percent})
        | from_entries)
        == {
            virtio_gpu_transport: 18,
            scheduler_synchronization: 4,
            memory_allocation_copy: 2,
            unreal_stripped: 1,
            angle_vulkan: 0.5
        }
' "$SIMPLEPERF_SUMMARY" >/dev/null; then
    print -u2 "simpleperf summary evidence contract regressed."
    jq . "$SIMPLEPERF_SUMMARY" >&2
    exit 1
fi

readonly UNREAL_STARTUP_FIXTURE="$PROJECT_DIR/scripts/test-fixtures/unreal-startup"
readonly UNREAL_STARTUP_AUDIT="$LIFECYCLE_ROOT/unreal-startup-audit.json"
"$PROJECT_DIR/scripts/audit-unreal-profile-startup.command" \
    "$UNREAL_STARTUP_FIXTURE/base.ini" \
    "$UNREAL_STARTUP_FIXTURE/candidate.ini" \
    "$UNREAL_STARTUP_FIXTURE/TFT.log" \
    "$UNREAL_STARTUP_AUDIT"
if ! jq -e '
    .schema_version == 1
    and .source.startup_log_embedded == false
    and .result == {
        delta_count: 2,
        startup_attested_count: 2,
        protected_override_count: 2,
        all_deltas_startup_attested: true
    }
    and ([.deltas[].key] | sort)
        == ["a.Budget.BudgetMs", "r.Upscale.Quality"]
    and all(.deltas[]; .startup_attested == true)
' "$UNREAL_STARTUP_AUDIT" >/dev/null; then
    print -u2 "Unreal startup profile audit contract regressed."
    jq . "$UNREAL_STARTUP_AUDIT" >&2
    exit 1
fi
for syntax_script in "$PROJECT_DIR"/scripts/test-fixtures/late-pvp/*.command; do
    zsh -o NO_BG_NICE -n "$syntax_script"
done
for syntax_script in "$PROJECT_DIR"/scripts/test-fixtures/gles-buffer-stress/*.command; do
    zsh -o NO_BG_NICE -n "$syntax_script"
done
for syntax_script in "$PROJECT_DIR"/scripts/test-fixtures/gles-draw-stress/*.command; do
    zsh -o NO_BG_NICE -n "$syntax_script"
done

if rg -n '[А-Яа-яЁё]' \
        "$LAUNCHER_DIR/Resources/launcher-runtime.command" \
        "$LAUNCHER_DIR/Resources/emulator-host.command" \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        "$PROJECT_DIR/run-tft-angle-opengl.command" \
        "$PROJECT_DIR/scripts/run-asg-experiment.command" \
        "$PROJECT_DIR/scripts/watch-root-pso.command"; then
    print -u2 "Bundled launcher logs must be in English."
    exit 1
fi

readonly GLES_FIXTURE_DIR="$PROJECT_DIR/scripts/test-fixtures/gles-buffer-stress"
readonly GLES_TEST_ROOT="$LIFECYCLE_ROOT/gles-buffer-stress"
readonly GLES_TEST_APK="$GLES_TEST_ROOT/probe.apk"
mkdir -p "$GLES_TEST_ROOT"
: > "$GLES_TEST_APK"
if ! env \
        TFT_ADB="$GLES_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_GLES_ADB_STATE="$GLES_TEST_ROOT/adb-state.tsv" \
        TFT_GLES_STRESS_PROBE="$GLES_TEST_APK" \
        TFT_GLES_STRESS_ROOT="$GLES_TEST_ROOT/results" \
        TFT_GLES_STRESS_EXPECTED_GRAPHICS_PROFILE=osft \
        TFT_GLES_STRESS_EXPECTED_ANGLE_ENABLED='exposeNonConformantExtensionsAndVersions:exposeES32ForTesting' \
        TFT_GLES_STRESS_EXPECTED_ANGLE_DISABLED=preferSubmitAtFBOBoundary \
        "$PROJECT_DIR/scripts/run-android-gles-buffer-stress.command" \
            fixture-control 3 10 16384 5 2 1 \
        > "$GLES_TEST_ROOT/probe.log"; then
    print -u2 "Android GLES buffer-stress fixture failed."
    cat "$GLES_TEST_ROOT/probe.log" >&2
    exit 1
fi
typeset -a gles_fixture_summaries
gles_fixture_summaries=("$GLES_TEST_ROOT"/results/*/summary.json(N))
if (( ${#gles_fixture_summaries} != 1 )) \
        || ! jq -e '
            .schema_version == 1
            and .graphics_profile == "osft"
            and .transport == "virtio-gpu-asg"
            and .workload.rounds == 3
            and .workload.warmup_rounds == 1
            and .workload.measured_rounds == 2
            and .attestation.guest_angle_mapped == true
            and .attestation.ranchu_vulkan_mapped == true
            and .result.gl_error_rounds == 0
        ' "$gles_fixture_summaries[1]" >/dev/null; then
    print -u2 "Android GLES buffer-stress evidence contract regressed."
    cat "$GLES_TEST_ROOT/probe.log" >&2
    exit 1
fi

readonly GLES_DRAW_FIXTURE_DIR="$PROJECT_DIR/scripts/test-fixtures/gles-draw-stress"
readonly GLES_DRAW_TEST_ROOT="$LIFECYCLE_ROOT/gles-draw-stress"
readonly GLES_DRAW_TEST_APK="$GLES_DRAW_TEST_ROOT/probe.apk"
mkdir -p "$GLES_DRAW_TEST_ROOT"
: > "$GLES_DRAW_TEST_APK"
if ! env \
        TFT_ADB="$GLES_DRAW_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_GLES_DRAW_ADB_STATE="$GLES_DRAW_TEST_ROOT/adb-state.tsv" \
        TFT_GLES_DRAW_PROBE="$GLES_DRAW_TEST_APK" \
        TFT_GLES_DRAW_ROOT="$GLES_DRAW_TEST_ROOT/results" \
        TFT_GLES_DRAW_EXPECTED_GRAPHICS_PROFILE=osft \
        TFT_GLES_DRAW_EXPECTED_ANGLE_ENABLED='exposeNonConformantExtensionsAndVersions:exposeES32ForTesting' \
        TFT_GLES_DRAW_EXPECTED_ANGLE_DISABLED=preferSubmitAtFBOBoundary \
        "$PROJECT_DIR/scripts/run-android-gles-draw-stress.command" \
            fixture-control 3 2 4 1 \
        > "$GLES_DRAW_TEST_ROOT/probe.log"; then
    print -u2 "Android GLES draw-stress fixture failed."
    cat "$GLES_DRAW_TEST_ROOT/probe.log" >&2
    exit 1
fi
typeset -a gles_draw_fixture_summaries
gles_draw_fixture_summaries=("$GLES_DRAW_TEST_ROOT"/results/*/summary.json(N))
if (( ${#gles_draw_fixture_summaries} != 1 )) \
        || ! jq -e '
            .schema_version == 1
            and .graphics_profile == "osft"
            and .transport == "virtio-gpu-asg"
            and .workload.rounds == 3
            and .workload.warmup_rounds == 1
            and .workload.measured_rounds == 2
            and .workload.frames == 2
            and .workload.draws_per_frame == 4
            and .workload.total_draw_calls_per_round == 10
            and .attestation.guest_angle_mapped == true
            and .attestation.ranchu_vulkan_mapped == true
            and .result.gl_error_rounds == 0
        ' "$gles_draw_fixture_summaries[1]" >/dev/null; then
    print -u2 "Android GLES draw-stress evidence contract regressed."
    cat "$GLES_DRAW_TEST_ROOT/probe.log" >&2
    exit 1
fi

readonly GLES_UBO_FIXTURE_DIR="$PROJECT_DIR/scripts/test-fixtures/gles-ubo-stress"
readonly GLES_UBO_TEST_ROOT="$LIFECYCLE_ROOT/gles-ubo-stress"
readonly GLES_UBO_TEST_APK="$GLES_UBO_TEST_ROOT/probe.apk"
mkdir -p "$GLES_UBO_TEST_ROOT"
: > "$GLES_UBO_TEST_APK"
if ! env \
        TFT_ADB="$GLES_UBO_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_GLES_UBO_ADB_STATE="$GLES_UBO_TEST_ROOT/adb-state.tsv" \
        TFT_GLES_UBO_PROBE="$GLES_UBO_TEST_APK" \
        TFT_GLES_UBO_ROOT="$GLES_UBO_TEST_ROOT/results" \
        TFT_GLES_UBO_EXPECTED_GRAPHICS_PROFILE=osft \
        TFT_GLES_UBO_EXPECTED_ANGLE_ENABLED='exposeNonConformantExtensionsAndVersions:exposeES32ForTesting' \
        TFT_GLES_UBO_EXPECTED_ANGLE_DISABLED=preferSubmitAtFBOBoundary \
        "$PROJECT_DIR/scripts/run-android-gles-ubo-stress.command" \
            fixture-pool pooled_map_once 3 2 4 1 \
        > "$GLES_UBO_TEST_ROOT/probe.log"; then
    print -u2 "Android GLES UBO-stress fixture failed."
    cat "$GLES_UBO_TEST_ROOT/probe.log" >&2
    exit 1
fi
typeset -a gles_ubo_fixture_summaries
gles_ubo_fixture_summaries=("$GLES_UBO_TEST_ROOT"/results/*/summary.json(N))
if (( ${#gles_ubo_fixture_summaries} != 1 )) \
        || ! jq -e '
            .schema_version == 1
            and .mode == "pooled_map_once"
            and .graphics_profile == "osft"
            and .transport == "virtio-gpu-asg"
            and .workload.rounds == 3
            and .workload.warmup_rounds == 1
            and .workload.measured_rounds == 2
            and .workload.frames == 2
            and .workload.draws_per_frame == 4
            and .workload.total_draw_calls_per_round == 8
            and .attestation.ubo_alignment == 256
            and .attestation.guest_angle_mapped == true
            and .attestation.ranchu_vulkan_mapped == true
            and .result.gl_error_rounds == 0
        ' "$gles_ubo_fixture_summaries[1]" >/dev/null; then
    print -u2 "Android GLES UBO-stress evidence contract regressed."
    cat "$GLES_UBO_TEST_ROOT/probe.log" >&2
    exit 1
fi
xcrun clang \
    -x objective-c \
    -target arm64-apple-macosx12.0 \
    -fsyntax-only \
    "$LAUNCHER_DIR/EmulatorHost/main.c"
"$PROJECT_DIR/scripts/build-tft-screen-classifier.command" >/dev/null
"$PROJECT_DIR/runtime/tft-screen-classifier" --self-test >/dev/null
"$PROJECT_DIR/scripts/capture-late-pvp-session.command" --self-test >/dev/null
readonly LATE_PVP_CANDIDATE_SELECTION="$LIFECYCLE_ROOT/late-pvp-candidate-selection.json"
"$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
    --candidate-id performance-max-rhi-command-list-screen \
    --print-selection > "$LATE_PVP_CANDIDATE_SELECTION"
if ! jq -e '
        .candidate_id == "performance-max-rhi-command-list-screen"
        and .variant == "performance_max_rhi_command_list_screen"
        and (.profile_path | endswith("performance-max-rhi-command-list.ini"))
        and .profile_sha256 == "7a82dd3a105beea7a50e96b91677b07c9b6bf9e5d207ed0ed20a9976965aac74"
        and .pinned_profile_sha256 == .profile_sha256
    ' "$LATE_PVP_CANDIDATE_SELECTION" >/dev/null \
        || "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
            --candidate-id missing-candidate --print-selection \
            > "$LIFECYCLE_ROOT/late-pvp-missing-candidate.out" 2>&1; then
    print -u2 "Late-PvP candidate manifest resolution regressed."
    exit 1
fi
readonly LATE_PVP_STALE_PIN_MANIFEST="$LIFECYCLE_ROOT/late-pvp-stale-pin-manifest.json"
jq '.latePvpPriorityQueue.items[1].profileSha256
      = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$PROJECT_DIR/scripts/performance-candidates.json" > "$LATE_PVP_STALE_PIN_MANIFEST"
if TFT_PERFORMANCE_CANDIDATES_MANIFEST="$LATE_PVP_STALE_PIN_MANIFEST" \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        --candidate-id performance-max-rhi-command-list-screen --print-selection \
        > "$LIFECYCLE_ROOT/late-pvp-stale-pin.out" 2>&1 \
        || ! grep -Fq 'does not match its pinned SHA-256' \
            "$LIFECYCLE_ROOT/late-pvp-stale-pin.out"; then
    print -u2 "Late-PvP candidate selection accepted a stale pinned profile hash."
    exit 1
fi

readonly LATE_PVP_PRIORITY_QUEUE="$LIFECYCLE_ROOT/late-pvp-priority-queue.json"
"$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
    --print-priority-queue > "$LATE_PVP_PRIORITY_QUEUE"
if ! jq -e '
        .control_candidate_id == "performance-max"
        and .minimum_independent_sessions_per_variant == 2
        and ([.items[].priority] == [1, 2, 3, 4, 5, 6, 7])
        and .items[0].capacity_gate.candidate_bytes == 16777216
        and .items[0].capacity_gate.largest_measured_synthetic_working_set_bytes == 32768
        and .items[0].capacity_gate.candidate_to_largest_measured_ratio == 512
        and .items[0].capacity_gate.status
            == "require_late_pvp_efficacy_before_4m_8m_16m_sizing_ladder"
        and all(.items[1:][]; .capacity_gate == null)
        and .items[2].candidate_id == "performance-max-animation-budget-1ms-screen"
        and .items[2].profile_sha256 == "5691ec40a9a96b3ee0c238e9db2d70bb3e769ba30fad6f085ee0346adf934fc3"
        and ([.items[].candidate_id] | length == (unique | length))
        and all(.items[];
          (.profile | type == "string")
          and (.profile_sha256 | test("^[0-9a-f]{64}$"))
          and (.correctness_gates | length) >= 2)
    ' "$LATE_PVP_PRIORITY_QUEUE" >/dev/null; then
    print -u2 "Late-PvP priority queue resolution regressed."
    exit 1
fi
typeset priority_profile priority_sha256
while IFS=$'\t' read -r priority_profile priority_sha256; do
    if [[ "$(shasum -a 256 "$PROJECT_DIR/$priority_profile" | awk '{ print $1 }')" \
            != "$priority_sha256" ]]; then
        print -u2 "A late-PvP priority profile hash is stale: $priority_profile"
        exit 1
    fi
done < <(jq -r '.items[] | [.profile, .profile_sha256] | @tsv' \
    "$LATE_PVP_PRIORITY_QUEUE")

readonly THREAD_SNAPSHOT_FIXTURE="$PROJECT_DIR/scripts/test-fixtures/thread-snapshot"
readonly THREAD_SNAPSHOT_BEFORE="$LIFECYCLE_ROOT/thread-snapshot-before.json"
readonly THREAD_SNAPSHOT_AFTER="$LIFECYCLE_ROOT/thread-snapshot-after.json"
readonly THREAD_SNAPSHOT_COMPARISON="$LIFECYCLE_ROOT/thread-snapshot-comparison.json"
TFT_THREAD_SNAPSHOT_TSV="$THREAD_SNAPSHOT_FIXTURE/before.tsv" \
TFT_THREAD_SNAPSHOT_CAPTURED_EPOCH_MS=1000 \
    "$PROJECT_DIR/scripts/capture-android-thread-snapshot.command" \
    999 "$THREAD_SNAPSHOT_BEFORE"
TFT_THREAD_SNAPSHOT_TSV="$THREAD_SNAPSHOT_FIXTURE/after.tsv" \
TFT_THREAD_SNAPSHOT_CAPTURED_EPOCH_MS=3000 \
    "$PROJECT_DIR/scripts/capture-android-thread-snapshot.command" \
    999 "$THREAD_SNAPSHOT_AFTER"
"$PROJECT_DIR/scripts/compare-android-thread-snapshots.command" \
    "$THREAD_SNAPSHOT_BEFORE" "$THREAD_SNAPSHOT_AFTER" \
    "$THREAD_SNAPSHOT_COMPARISON"
if ! jq -e '
    .pid == 999
    and .window.elapsed_ms == 2000
    and .coverage == {before_threads: 3, after_threads: 4, matched_nonnegative_threads: 3}
    and .totals.delta_cpu_ms == 700
    and .totals.delta_runtime_ms == 540
    and .totals.delta_runqueue_wait_ms == 140
    and .threads[0].name == "RHIThread"
    and .threads[0].delta_cpu_ms == 400
    and .threads[0].runqueue_wait_percent == 25
    and ([.roles[] | select(.role == "GameThread")][0].delta_cpu_ms == 250)
    and ([.roles[] | select(.role == "AudioMixer")][0].delta_cpu_ms == 50)
    and all(.roles[]; .active_thread_count == .thread_count)
  ' "$THREAD_SNAPSHOT_COMPARISON" >/dev/null; then
    print -u2 "The Android thread scheduler snapshot comparison is invalid."
    exit 1
fi

readonly LATE_PVP_FIXTURE_DIR="$PROJECT_DIR/scripts/test-fixtures/late-pvp"
readonly LATE_PVP_TEST_ROOT="$LIFECYCLE_ROOT/late-pvp"
readonly LATE_PVP_ADB_LOG="$LATE_PVP_TEST_ROOT/adb.log"
readonly LATE_PVP_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini"
readonly LATE_PVP_PROFILE_SHA256="$(shasum -a 256 "$LATE_PVP_PROFILE" | awk '{ print $1 }')"
mkdir -p "$LATE_PVP_TEST_ROOT"
: > "$LATE_PVP_ADB_LOG"
if ! env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_TEST_ROOT/results" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        TFT_LATE_PVP_PROFILE_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/observer.log"; then
    print -u2 "Late-PvP observer fixture failed."
    cat "$LATE_PVP_TEST_ROOT/observer.log" >&2
    exit 1
fi
typeset -a late_pvp_sessions late_pvp_profiles
late_pvp_sessions=("$LATE_PVP_TEST_ROOT"/results/*(N/))
if (( ${#late_pvp_sessions} != 1 )); then
    print -u2 "Late-PvP observer did not produce one fixture session."
    exit 1
fi
late_pvp_profiles=("$late_pvp_sessions[1]"/captures/*/profile/summary.json(N))
if (( ${#late_pvp_profiles} != 1 )) \
        || ! jq -e '
            .simpleperf_status == 0
            and .simpleperf.record_status == 0
            and .simpleperf.flat_report.status == 0
            and .simpleperf.flat_report.attribution == "exclusive sampled leaves"
            and .simpleperf.caller_inclusive_report.status == 0
            and .simpleperf.caller_inclusive_report.attribution
                == "children overhead accumulated from recorded call chains with file-relative addresses"
            and .simpleperf.caller_inclusive_report.promotion_gate == false
            and .simpleperf_data.pull_status == 0
            and .simpleperf_data.size_bytes > 0
            and (.simpleperf_data.sha256 | test("^[0-9a-f]{64}$"))
            and .simpleperf_data.purpose == "retain call chains for caller-inclusive offline attribution"
            and .timing == "after_pacing_window"
            and .privacy == "symbols_and_raw_perf_no_game_log"
            and .active_profile_attestation.after_record_status == 0
            and .active_profile_attestation.passed == true
            and .thread_scheduler.available == true
            and .thread_scheduler.comparison_status == 0
            and .semantic_gate.valid == true
            and .accepted == true
        ' "$late_pvp_profiles[1]" >/dev/null \
        || [[ ! -s "${late_pvp_profiles[1]:h}/simpleperf-children-report.txt" ]] \
        || [[ "$(shasum -a 256 "${late_pvp_profiles[1]:h}/simpleperf.data" | awk '{ print $1 }')" \
            != "$(jq -r '.simpleperf_data.sha256' "$late_pvp_profiles[1]")" ]] \
        || ! jq -e '
            .status == "max_captures"
            and .accepted_captures == 1
            and .profiling.attempted_profiles == 1
            and .profiling.accepted_profiles == 1
            and .profiling.raw_callgraph_profiles == 1
            and .profiling.raw_callgraph_integrity == "reverified_at_session_finalize"
            and .profiling.promotion_gate == false
            and .aggregate.mean_fps == 24.5
            and .aggregate.frames_over_50_ms == 3
        ' "$late_pvp_sessions[1]/summary.json" >/dev/null \
        || ! jq -e --arg profile_sha256 "$LATE_PVP_PROFILE_SHA256" '
            .capture.profile_sha256 == $profile_sha256
            and .capture.active_profile_attestation.passed == true
            and .capture.active_profile_attestation.process_pid == 4242
            and .capture.active_profile_attestation.mount_count == 1
            and .capture.active_profile_attestation.sha256 == $profile_sha256
        ' "$late_pvp_sessions[1]/manifest.json" >/dev/null \
        || ! jq -e '
            .captures[0].device.version_name == "18.1.5300314"
            and .captures[0].graphics.active_apk_sha256
                == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ' "$late_pvp_sessions[1]/summary.json" >/dev/null \
        || ! awk '
            $0 == "frame-capture" { frame = NR }
            /simpleperf record/ { record = NR }
            /simpleperf report/ { report = NR }
            /simpleperf report.*--children.*vaddr_in_file/ { children = NR }
            /rm -f .*mactician-late-pvp/ { cleanup = NR }
            END { exit !(frame > 0 && frame < record && record < report && report <= children && children < cleanup) }
        ' "$LATE_PVP_ADB_LOG"; then
    print -u2 "Late-PvP pacing/profile ordering or acceptance regressed."
    cat "$LATE_PVP_TEST_ROOT/observer.log" >&2
    cat "$LATE_PVP_ADB_LOG" >&2
    exit 1
fi

# The children report is a convenient derived view, not the source recording.
# A version-specific report failure must remain visible without discarding a
# successfully pulled and hash-attested raw callgraph.
readonly LATE_PVP_CHILDREN_FAILURE_ROOT="$LATE_PVP_TEST_ROOT/children-failure-results"
readonly LATE_PVP_CHILDREN_FAILURE_ADB_LOG="$LATE_PVP_TEST_ROOT/children-failure-adb.log"
: > "$LATE_PVP_CHILDREN_FAILURE_ADB_LOG"
if ! env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_CHILDREN_FAILURE_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_FAKE_SIMPLEPERF_CHILDREN_REPORT_FAIL=1 \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_CHILDREN_FAILURE_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        TFT_LATE_PVP_PROFILE_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/children-failure.log"; then
    print -u2 "Late-PvP children-report failure discarded valid raw evidence."
    cat "$LATE_PVP_TEST_ROOT/children-failure.log" >&2
    exit 1
fi
typeset -a late_pvp_children_failure_profiles
late_pvp_children_failure_profiles=(
    "$LATE_PVP_CHILDREN_FAILURE_ROOT"/*/captures/*/profile/summary.json(N)
)
if (( ${#late_pvp_children_failure_profiles} != 1 )) \
        || ! jq -e '
            .simpleperf.record_status == 0
            and .simpleperf.flat_report.status == 0
            and .simpleperf.caller_inclusive_report.status == 74
            and .simpleperf_data.pull_status == 0
            and (.simpleperf_data.sha256 | test("^[0-9a-f]{64}$"))
            and .accepted == true
        ' "$late_pvp_children_failure_profiles[1]" >/dev/null \
        || [[ "$(shasum -a 256 "${late_pvp_children_failure_profiles[1]:h}/simpleperf.data" \
                | awk '{ print $1 }')" \
            != "$(jq -r '.simpleperf_data.sha256' \
                "$late_pvp_children_failure_profiles[1]")" ]]; then
    print -u2 "Late-PvP raw evidence did not survive a derived children-report failure."
    cat "$LATE_PVP_TEST_ROOT/children-failure.log" >&2
    cat "$LATE_PVP_CHILDREN_FAILURE_ADB_LOG" >&2
    exit 1
fi

# A flat report without the corresponding raw perf.data cannot support later
# caller-inclusive attribution. The pacing sample may remain usable, but the
# profile must fail closed and the guest temporary file must still be removed.
readonly LATE_PVP_PULL_FAILURE_ROOT="$LATE_PVP_TEST_ROOT/pull-failure-results"
readonly LATE_PVP_PULL_FAILURE_ADB_LOG="$LATE_PVP_TEST_ROOT/pull-failure-adb.log"
: > "$LATE_PVP_PULL_FAILURE_ADB_LOG"
if ! env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_PULL_FAILURE_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_FAKE_SIMPLEPERF_PULL_FAIL=1 \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_PULL_FAILURE_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        TFT_LATE_PVP_PROFILE_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/pull-failure.log"; then
    print -u2 "Late-PvP pull-failure fixture did not preserve its pacing capture."
    cat "$LATE_PVP_TEST_ROOT/pull-failure.log" >&2
    exit 1
fi
typeset -a late_pvp_pull_failure_profiles
typeset -a late_pvp_pull_failure_sessions
late_pvp_pull_failure_profiles=(
    "$LATE_PVP_PULL_FAILURE_ROOT"/*/captures/*/profile/summary.json(N)
)
late_pvp_pull_failure_sessions=("$LATE_PVP_PULL_FAILURE_ROOT"/*(N/))
if (( ${#late_pvp_pull_failure_profiles} != 1 \
        || ${#late_pvp_pull_failure_sessions} != 1 )) \
        || ! jq -e '
            .simpleperf_status == 0
            and .simpleperf.record_status == 0
            and .simpleperf.flat_report.status == 0
            and .simpleperf.caller_inclusive_report.status == 0
            and .simpleperf_data.pull_status == 73
            and .simpleperf_data.size_bytes == 0
            and .simpleperf_data.sha256 == ""
            and .accepted == false
        ' "$late_pvp_pull_failure_profiles[1]" >/dev/null \
        || ! jq -e '
            .accepted_captures == 1
            and .profiling.attempted_profiles == 1
            and .profiling.accepted_profiles == 0
            and .profiling.raw_callgraph_profiles == 0
            and .profiling.promotion_gate == false
        ' "$late_pvp_pull_failure_sessions[1]/summary.json" >/dev/null \
        || [[ -e "${late_pvp_pull_failure_profiles[1]:h}/simpleperf.data" ]] \
        || ! grep -Fq 'rm -f /data/local/tmp/mactician-late-pvp-4242.data' \
            "$LATE_PVP_PULL_FAILURE_ADB_LOG"; then
    print -u2 "Late-PvP profile did not fail closed after raw callgraph pull failure."
    cat "$LATE_PVP_TEST_ROOT/pull-failure.log" >&2
    cat "$LATE_PVP_PULL_FAILURE_ADB_LOG" >&2
    exit 1
fi

readonly LATE_PVP_EMPTY_PULL_ROOT="$LATE_PVP_TEST_ROOT/empty-pull-results"
readonly LATE_PVP_EMPTY_PULL_ADB_LOG="$LATE_PVP_TEST_ROOT/empty-pull-adb.log"
: > "$LATE_PVP_EMPTY_PULL_ADB_LOG"
if ! env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_EMPTY_PULL_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_FAKE_SIMPLEPERF_PULL_EMPTY=1 \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_EMPTY_PULL_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        TFT_LATE_PVP_PROFILE_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/empty-pull.log"; then
    print -u2 "Late-PvP empty-pull fixture discarded its valid pacing capture."
    exit 1
fi
typeset -a late_pvp_empty_pull_profiles
late_pvp_empty_pull_profiles=("$LATE_PVP_EMPTY_PULL_ROOT"/*/captures/*/profile/summary.json(N))
if (( ${#late_pvp_empty_pull_profiles} != 1 )) \
        || ! jq -e '
            .simpleperf_data.pull_status == 0
            and .simpleperf_data.size_bytes == 0
            and .simpleperf_data.sha256 == ""
            and .accepted == false
        ' "$late_pvp_empty_pull_profiles[1]" >/dev/null \
        || [[ -e "${late_pvp_empty_pull_profiles[1]:h}/simpleperf.data" ]]; then
    print -u2 "Late-PvP profile accepted an empty raw callgraph."
    cat "$LATE_PVP_TEST_ROOT/empty-pull.log" >&2
    cat "$LATE_PVP_EMPTY_PULL_ADB_LOG" >&2
    exit 1
fi

# A profile change after simpleperf sampling makes attribution ambiguous even
# when the raw file and the surrounding screen gate are valid.
readonly LATE_PVP_PROFILE_BRACKET_FAILURE_ROOT="$LATE_PVP_TEST_ROOT/profile-bracket-failure-results"
readonly LATE_PVP_PROFILE_BRACKET_FAILURE_ADB_LOG="$LATE_PVP_TEST_ROOT/profile-bracket-failure-adb.log"
: > "$LATE_PVP_PROFILE_BRACKET_FAILURE_ADB_LOG"
if ! env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_PROFILE_BRACKET_FAILURE_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256_AFTER_FIRST="0000000000000000000000000000000000000000000000000000000000000000" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256_AFTER_COUNT=3 \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_PROFILE_BRACKET_FAILURE_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        TFT_LATE_PVP_PROFILE_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/profile-bracket-failure.log" 2>&1; then
    print -u2 "Late-PvP profile-bracket fixture discarded its valid pacing capture."
    exit 1
fi
typeset -a late_pvp_profile_bracket_failure_profiles
typeset -a late_pvp_profile_bracket_failure_sessions
late_pvp_profile_bracket_failure_profiles=(
    "$LATE_PVP_PROFILE_BRACKET_FAILURE_ROOT"/*/captures/*/profile/summary.json(N)
)
late_pvp_profile_bracket_failure_sessions=("$LATE_PVP_PROFILE_BRACKET_FAILURE_ROOT"/*(N/))
if (( ${#late_pvp_profile_bracket_failure_profiles} != 1 \
        || ${#late_pvp_profile_bracket_failure_sessions} != 1 )) \
        || ! jq -e '
            .simpleperf.record_status == 0
            and .simpleperf_data.pull_status == 0
            and (.simpleperf_data.sha256 | test("^[0-9a-f]{64}$"))
            and .active_profile_attestation.after_record_status == 1
            and .active_profile_attestation.passed == false
            and .accepted == false
        ' "$late_pvp_profile_bracket_failure_profiles[1]" >/dev/null \
        || ! jq -e '
            .accepted_captures == 1
            and .profiling.attempted_profiles == 1
            and .profiling.accepted_profiles == 0
            and .profiling.raw_callgraph_profiles == 0
        ' "$late_pvp_profile_bracket_failure_sessions[1]/summary.json" >/dev/null; then
    print -u2 "Late-PvP profile accepted raw evidence across a profile change."
    cat "$LATE_PVP_TEST_ROOT/profile-bracket-failure.log" >&2
    cat "$LATE_PVP_PROFILE_BRACKET_FAILURE_ADB_LOG" >&2
    exit 1
fi

readonly LATE_PVP_MISMATCH_ROOT="$LATE_PVP_TEST_ROOT/profile-mismatch-results"
if env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_MISMATCH_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/profile-mismatch.log" 2>&1; then
    print -u2 "Late-PvP observer accepted a mismatched active DeviceProfile."
    exit 1
fi
if ! grep -Fq 'The selected DeviceProfile is not the single active TFT bind mount.' \
        "$LATE_PVP_TEST_ROOT/profile-mismatch.log" \
        || [[ -e "$LATE_PVP_MISMATCH_ROOT" ]]; then
    print -u2 "Late-PvP profile mismatch did not fail closed before creating a session."
    cat "$LATE_PVP_TEST_ROOT/profile-mismatch.log" >&2
    exit 1
fi

readonly LATE_PVP_RUNTIME_MISMATCH_ROOT="$LATE_PVP_TEST_ROOT/runtime-profile-mismatch-results"
readonly LATE_PVP_RUNTIME_MISMATCH_ADB_LOG="$LATE_PVP_TEST_ROOT/runtime-profile-mismatch-adb.log"
: > "$LATE_PVP_RUNTIME_MISMATCH_ADB_LOG"
if env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_RUNTIME_MISMATCH_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256_AFTER_FIRST="0000000000000000000000000000000000000000000000000000000000000000" \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_RUNTIME_MISMATCH_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/runtime-profile-mismatch.log" 2>&1; then
    print -u2 "Late-PvP observer continued after its active profile changed."
    exit 1
fi
typeset -a late_pvp_runtime_mismatch_sessions
late_pvp_runtime_mismatch_sessions=("$LATE_PVP_RUNTIME_MISMATCH_ROOT"/*(N/))
if (( ${#late_pvp_runtime_mismatch_sessions} != 1 )) \
        || ! jq -e '
            .status == "profile_attestation_failed"
            and .attempted_captures == 0
            and .accepted_captures == 0
        ' "$late_pvp_runtime_mismatch_sessions[1]/summary.json" >/dev/null \
        || grep -Fq 'frame-capture' "$LATE_PVP_RUNTIME_MISMATCH_ADB_LOG"; then
    print -u2 "Late-PvP runtime profile change did not stop before pacing capture."
    cat "$LATE_PVP_TEST_ROOT/runtime-profile-mismatch.log" >&2
    exit 1
fi

readonly LATE_PVP_POST_WINDOW_MISMATCH_ROOT="$LATE_PVP_TEST_ROOT/post-window-profile-mismatch-results"
readonly LATE_PVP_POST_WINDOW_MISMATCH_ADB_LOG="$LATE_PVP_TEST_ROOT/post-window-profile-mismatch-adb.log"
: > "$LATE_PVP_POST_WINDOW_MISMATCH_ADB_LOG"
if env \
        TFT_ADB="$LATE_PVP_FIXTURE_DIR/fake-adb.command" \
        TFT_FAKE_ADB_LOG="$LATE_PVP_POST_WINDOW_MISMATCH_ADB_LOG" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256="$LATE_PVP_PROFILE_SHA256" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256_AFTER_FIRST="0000000000000000000000000000000000000000000000000000000000000000" \
        TFT_FAKE_ACTIVE_PROFILE_SHA256_AFTER_COUNT=2 \
        TFT_SCREEN_CLASSIFIER_BINARY="$LATE_PVP_FIXTURE_DIR/fake-classifier.command" \
        TFT_LATE_PVP_FRAME_CAPTURE="$LATE_PVP_FIXTURE_DIR/fake-frame-capture.command" \
        TFT_LATE_PVP_ROOT="$LATE_PVP_POST_WINDOW_MISMATCH_ROOT" \
        TFT_LATE_PVP_DURATION=60s \
        TFT_LATE_PVP_MAX_CAPTURES=1 \
        TFT_LATE_PVP_POLL_SECONDS=1 \
        "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        > "$LATE_PVP_TEST_ROOT/post-window-profile-mismatch.log" 2>&1; then
    print -u2 "Late-PvP observer accepted a pacing window after its profile changed."
    exit 1
fi
typeset -a late_pvp_post_window_mismatch_sessions
late_pvp_post_window_mismatch_sessions=("$LATE_PVP_POST_WINDOW_MISMATCH_ROOT"/*(N/))
if (( ${#late_pvp_post_window_mismatch_sessions} != 1 )) \
        || ! jq -e '
            .status == "profile_attestation_failed"
            and .attempted_captures == 1
            and .accepted_captures == 0
            and .captures == []
            and .aggregate == null
        ' "$late_pvp_post_window_mismatch_sessions[1]/summary.json" >/dev/null \
        || ! grep -Fq 'frame-capture' "$LATE_PVP_POST_WINDOW_MISMATCH_ADB_LOG" \
        || grep -Fq 'simpleperf record' "$LATE_PVP_POST_WINDOW_MISMATCH_ADB_LOG" \
        || find "$LATE_PVP_POST_WINDOW_MISMATCH_ROOT" -name .late-pvp-accepted \
            -print -quit | grep -q .; then
    print -u2 "Late-PvP post-window profile change entered the accepted aggregate."
    cat "$LATE_PVP_TEST_ROOT/post-window-profile-mismatch.log" >&2
    cat "$LATE_PVP_POST_WINDOW_MISMATCH_ADB_LOG" >&2
    exit 1
fi

readonly LATE_PVP_SUMMARY_FIXTURE="$PROJECT_DIR/scripts/test-fixtures/late-pvp-summary"
readonly LATE_PVP_COMPARISON="$LIFECYCLE_ROOT/late-pvp-comparison.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_SUMMARY_FIXTURE" control candidate "$LATE_PVP_COMPARISON" \
    >/dev/null
if ! jq -e '
    .schema_version == 1
    and .workload == "passive_late_player_combat"
    and .comparison.matching == "exact_stage_round_host_graphics_game_version_and_apk"
    and .input.scanned_sessions == 5
    and .input.control_sessions_with_any_valid_capture == 2
    and .input.candidate_sessions_with_any_valid_capture == 3
    and .aggregate.common_strata == 2
    and .aggregate.control_captures == 2
    and .aggregate.candidate_captures == 2
    and .aggregate.control_sessions == 2
    and .aggregate.candidate_sessions == 2
    and .aggregate.control_profile_sha256 == ["1111111111111111111111111111111111111111111111111111111111111111"]
    and .aggregate.candidate_profile_sha256 == ["2222222222222222222222222222222222222222222222222222222222222222"]
    and .aggregate.control.mean_fps == 18
    and .aggregate.candidate.mean_fps == 20
    and ((.aggregate.delta.fps_percent - 11.111111111111116) | fabs < 0.000001)
    and .aggregate.control.mean_p95_ms == 55
    and .aggregate.candidate.mean_p95_ms == 53
    and .decision.late_pvp_screen_passed == true
    and .decision.control_profile_consistency_gate == true
    and .decision.candidate_profile_consistency_gate == true
    and .decision.distinct_profile_gate == true
    and .decision.visual_fidelity_gate == "not_measured"
    and .decision.promotion_eligible == false
    and all(.common_strata[];
        .conditions.game_version == "18.1.5300314"
        and .conditions.active_apk_sha256
            == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    and ([.common_strata[].conditions.stage] | sort) == ["4-1", "5-1"]
' "$LATE_PVP_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP matched-session comparison contract regressed."
    jq . "$LATE_PVP_COMPARISON" >&2
    exit 1
fi

# Reusing one variant label for two different profile binaries must invalidate
# an otherwise favorable comparison instead of silently averaging experiments.
readonly LATE_PVP_MIXED_PROFILE_FIXTURE="$LIFECYCLE_ROOT/late-pvp-mixed-profile"
readonly LATE_PVP_MIXED_PROFILE_COMPARISON="$LIFECYCLE_ROOT/late-pvp-mixed-profile-comparison.json"
cp -R "$LATE_PVP_SUMMARY_FIXTURE" "$LATE_PVP_MIXED_PROFILE_FIXTURE"
jq '
    .captures[0].semantic_gate.stage_before = "4-1"
    | .captures[0].semantic_gate.stage_after = "4-1"
    | .captures[0].graphics.profile_sha256 = "3333333333333333333333333333333333333333333333333333333333333333"
' "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/summary.json" \
    > "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/summary.json.next"
mv "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/summary.json.next" \
    "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/summary.json"
jq '
    .capture.profile_sha256 = "3333333333333333333333333333333333333333333333333333333333333333"
    | .capture.active_profile_attestation.sha256 = .capture.profile_sha256
' "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/manifest.json" \
    > "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/manifest.json.next"
mv "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/manifest.json.next" \
    "$LATE_PVP_MIXED_PROFILE_FIXTURE/candidate-unmatched/manifest.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_MIXED_PROFILE_FIXTURE" control candidate \
    "$LATE_PVP_MIXED_PROFILE_COMPARISON" >/dev/null
if ! jq -e '
    .aggregate.candidate_profile_sha256
        == ["2222222222222222222222222222222222222222222222222222222222222222",
            "3333333333333333333333333333333333333333333333333333333333333333"]
    and .decision.candidate_profile_consistency_gate == false
    and .decision.late_pvp_screen_passed == false
    and .decision.promotion_eligible == false
' "$LATE_PVP_MIXED_PROFILE_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP mixed-profile evidence was not rejected."
    jq . "$LATE_PVP_MIXED_PROFILE_COMPARISON" >&2
    exit 1
fi

# Identical labels and host conditions must not pool measurements across a
# Riot update. The active base APK is part of every exact-match stratum.
readonly LATE_PVP_MIXED_APK_FIXTURE="$LIFECYCLE_ROOT/late-pvp-mixed-apk"
readonly LATE_PVP_MIXED_APK_COMPARISON="$LIFECYCLE_ROOT/late-pvp-mixed-apk-comparison.json"
cp -R "$LATE_PVP_SUMMARY_FIXTURE" "$LATE_PVP_MIXED_APK_FIXTURE"
jq '
    .captures[0].device.version_name = "18.1.5300999"
    | .captures[0].graphics.active_apk_sha256
        = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
' "$LATE_PVP_MIXED_APK_FIXTURE/candidate-b/summary.json" \
    > "$LATE_PVP_MIXED_APK_FIXTURE/candidate-b/summary.json.next"
mv "$LATE_PVP_MIXED_APK_FIXTURE/candidate-b/summary.json.next" \
    "$LATE_PVP_MIXED_APK_FIXTURE/candidate-b/summary.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_MIXED_APK_FIXTURE" control candidate \
    "$LATE_PVP_MIXED_APK_COMPARISON" >/dev/null
if ! jq -e '
    .input.invalid_session_files == 0
    and .aggregate.common_strata == 1
    and .aggregate.control_captures == 1
    and .aggregate.candidate_captures == 1
    and .decision.common_strata_gate == false
    and .decision.late_pvp_screen_passed == false
    and .decision.promotion_eligible == false
' "$LATE_PVP_MIXED_APK_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP summarizer pooled measurements from different game APKs."
    jq . "$LATE_PVP_MIXED_APK_COMPARISON" >&2
    exit 1
fi

readonly LATE_PVP_MALFORMED_TYPE_FIXTURE="$LIFECYCLE_ROOT/late-pvp-malformed-type"
readonly LATE_PVP_MALFORMED_TYPE_COMPARISON="$LIFECYCLE_ROOT/late-pvp-malformed-type-comparison.json"
cp -R "$LATE_PVP_SUMMARY_FIXTURE" "$LATE_PVP_MALFORMED_TYPE_FIXTURE"
jq '.captures[0].device.version_name = 5300314' \
    "$LATE_PVP_MALFORMED_TYPE_FIXTURE/candidate-unmatched/summary.json" \
    > "$LATE_PVP_MALFORMED_TYPE_FIXTURE/candidate-unmatched/summary.json.next"
mv "$LATE_PVP_MALFORMED_TYPE_FIXTURE/candidate-unmatched/summary.json.next" \
    "$LATE_PVP_MALFORMED_TYPE_FIXTURE/candidate-unmatched/summary.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_MALFORMED_TYPE_FIXTURE" control candidate \
    "$LATE_PVP_MALFORMED_TYPE_COMPARISON" >/dev/null
if ! jq -e '
    .input.invalid_session_files == 0
    and .input.candidate_sessions_with_any_valid_capture == 2
    and .aggregate.common_strata == 2
    and .decision.late_pvp_screen_passed == true
    and .decision.promotion_eligible == false
' "$LATE_PVP_MALFORMED_TYPE_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP summarizer did not safely exclude a malformed string field."
    jq . "$LATE_PVP_MALFORMED_TYPE_COMPARISON" >&2
    exit 1
fi

readonly LATE_PVP_UNATTESTED_FIXTURE="$LIFECYCLE_ROOT/late-pvp-unattested"
readonly LATE_PVP_UNATTESTED_COMPARISON="$LIFECYCLE_ROOT/late-pvp-unattested-comparison.json"
cp -R "$LATE_PVP_SUMMARY_FIXTURE" "$LATE_PVP_UNATTESTED_FIXTURE"
jq '.capture.active_profile_attestation.passed = false' \
    "$LATE_PVP_UNATTESTED_FIXTURE/candidate-a/manifest.json" \
    > "$LATE_PVP_UNATTESTED_FIXTURE/candidate-a/manifest.json.next"
mv "$LATE_PVP_UNATTESTED_FIXTURE/candidate-a/manifest.json.next" \
    "$LATE_PVP_UNATTESTED_FIXTURE/candidate-a/manifest.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_UNATTESTED_FIXTURE" control candidate \
    "$LATE_PVP_UNATTESTED_COMPARISON" >/dev/null
if ! jq -e '
    .input.scanned_sessions == 5
    and .input.invalid_session_files == 1
    and .aggregate.common_strata == 1
    and .decision.common_strata_gate == false
    and .decision.late_pvp_screen_passed == false
    and .decision.promotion_eligible == false
' "$LATE_PVP_UNATTESTED_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP summarizer accepted an unattested session."
    jq . "$LATE_PVP_UNATTESTED_COMPARISON" >&2
    exit 1
fi

readonly LATE_PVP_MALFORMED_ATTESTATION_FIXTURE="$LIFECYCLE_ROOT/late-pvp-malformed-attestation"
readonly LATE_PVP_MALFORMED_ATTESTATION_COMPARISON="$LIFECYCLE_ROOT/late-pvp-malformed-attestation-comparison.json"
cp -R "$LATE_PVP_SUMMARY_FIXTURE" "$LATE_PVP_MALFORMED_ATTESTATION_FIXTURE"
jq '.capture.active_profile_attestation.process_pid = "4242"' \
    "$LATE_PVP_MALFORMED_ATTESTATION_FIXTURE/candidate-a/manifest.json" \
    > "$LATE_PVP_MALFORMED_ATTESTATION_FIXTURE/candidate-a/manifest.json.next"
mv "$LATE_PVP_MALFORMED_ATTESTATION_FIXTURE/candidate-a/manifest.json.next" \
    "$LATE_PVP_MALFORMED_ATTESTATION_FIXTURE/candidate-a/manifest.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_MALFORMED_ATTESTATION_FIXTURE" control candidate \
    "$LATE_PVP_MALFORMED_ATTESTATION_COMPARISON" >/dev/null
if ! jq -e '
    .input.scanned_sessions == 5
    and .input.invalid_session_files == 1
    and .aggregate.common_strata == 1
    and .decision.common_strata_gate == false
    and .decision.late_pvp_screen_passed == false
    and .decision.promotion_eligible == false
' "$LATE_PVP_MALFORMED_ATTESTATION_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP summarizer accepted a malformed profile attestation."
    jq . "$LATE_PVP_MALFORMED_ATTESTATION_COMPARISON" >&2
    exit 1
fi

readonly LATE_PVP_UNSTABLE_HOST_FIXTURE="$LIFECYCLE_ROOT/late-pvp-unstable-host"
readonly LATE_PVP_UNSTABLE_HOST_COMPARISON="$LIFECYCLE_ROOT/late-pvp-unstable-host-comparison.json"
cp -R "$LATE_PVP_SUMMARY_FIXTURE" "$LATE_PVP_UNSTABLE_HOST_FIXTURE"
jq '.captures[0].host.stable = false' \
    "$LATE_PVP_UNSTABLE_HOST_FIXTURE/candidate-a/summary.json" \
    > "$LATE_PVP_UNSTABLE_HOST_FIXTURE/candidate-a/summary.json.next"
mv "$LATE_PVP_UNSTABLE_HOST_FIXTURE/candidate-a/summary.json.next" \
    "$LATE_PVP_UNSTABLE_HOST_FIXTURE/candidate-a/summary.json"
"$PROJECT_DIR/scripts/summarize-late-pvp-sessions.command" \
    "$LATE_PVP_UNSTABLE_HOST_FIXTURE" control candidate \
    "$LATE_PVP_UNSTABLE_HOST_COMPARISON" >/dev/null
if ! jq -e '
    .input.invalid_session_files == 0
    and .aggregate.common_strata == 1
    and .decision.common_strata_gate == false
    and .decision.late_pvp_screen_passed == false
' "$LATE_PVP_UNSTABLE_HOST_COMPARISON" >/dev/null; then
    print -u2 "Late-PvP summarizer accepted a host-condition transition."
    jq . "$LATE_PVP_UNSTABLE_HOST_COMPARISON" >&2
    exit 1
fi

if ! grep -Fq -- '--options runtime' "$PROJECT_DIR/scripts/build-mactician.command" \
        || ! grep -Fq 'notarytool submit' "$PROJECT_DIR/scripts/build-mactician.command" \
        || ! grep -Fq 'stapler staple "$DMG"' "$PROJECT_DIR/scripts/build-mactician.command" \
        || ! grep -Fq 'stapler staple "$APP"' "$PROJECT_DIR/scripts/build-mactician.command" \
        || ! grep -Fq 'Sparkle.framework' "$PROJECT_DIR/scripts/build-mactician.command"; then
    print -u2 "Public release signing and notarization workflow is incomplete."
    exit 1
fi

if [[ ! -x "$PROJECT_DIR/scripts/build-mactician-release.command" ]] \
        || ! grep -Fq 'mactician-notary' "$PROJECT_DIR/scripts/build-mactician-release.command" \
        || ! grep -Fq 'Developer ID Application:' "$PROJECT_DIR/scripts/build-mactician-release.command"; then
    print -u2 "One-command public release wrapper is incomplete."
    exit 1
fi

if ! grep -Fq 'MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS' \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'MVK_CONFIG_USE_MTLHEAP' \
            "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE' \
            "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'MVK_CONFIG_LOG_LEVEL' \
            "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT' \
            "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'MVK_CONFIG_PERFORMANCE_TRACKING' \
            "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! rg -Uq 'for environment_name in \\\n+[[:space:]]+ANGLE_FEATURE_OVERRIDES_ENABLED \\\n+[[:space:]]+ANGLE_FEATURE_OVERRIDES_DISABLED \\\n+[[:space:]]+MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS' \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! rg -Uq 'MVK_CONFIG_FAST_MATH_ENABLED \\\n+[[:space:]]+MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS \\\n+[[:space:]]+MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE; do' \
        "$PROJECT_DIR/run-tft-root-affinity.command"; then
    print -u2 "The Game Mode app wrapper must preserve experimental ANGLE and MoltenVK settings."
    exit 1
fi

if ! jq -e '
        def safe_relative_path:
          type == "string"
          and test("^[A-Za-z0-9._/-]+$")
          and (startswith("/") | not)
          and (contains("..") | not);
        .schemaVersion == 1
        and (.candidates | type == "array" and length > 0)
        and ([.candidates[].id] | length == (unique | length))
        and ([.candidates[].variant] | length == (unique | length))
        and (.latePvpPriorityQueue.minimumIndependentSessionsPerVariant >= 2)
        and (.latePvpPriorityQueue.controlProfileSha256 | test("^[0-9a-f]{64}$"))
        and ([.latePvpPriorityQueue.items[].priority] == [1, 2, 3, 4, 5, 6, 7])
        and ([.latePvpPriorityQueue.items[].candidateId]
          | length == (unique | length))
        and (.latePvpPriorityQueue.items[0].capacityGate.candidateBytes == 16777216)
        and (.latePvpPriorityQueue.items[0].capacityGate.largestMeasuredSyntheticWorkingSetBytes == 32768)
        and (.latePvpPriorityQueue.items[0].capacityGate.candidateToLargestMeasuredRatio == 512)
        and (.latePvpPriorityQueue.items[0].capacityGate.status
          == "require_late_pvp_efficacy_before_4m_8m_16m_sizing_ladder")
        and all(.latePvpPriorityQueue.items[];
          .profileSha256 | test("^[0-9a-f]{64}$"))
        and (([.latePvpPriorityQueue.items[].candidateId]
          - [.candidates[].id]) | length == 0)
        and all(.candidates[];
          (.id | type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
          and (.launcher | safe_relative_path)
          and ((.profile // "placeholder") | safe_relative_path)
          and (.variant | type == "string" and test("^[a-z0-9][a-z0-9_-]*$"))
          and (.display | type == "string"
            and test("^(2560x1440|2880x1620|3200x1800|3840x2160)$"))
          and (.density | type == "number" and floor == . and . >= 120 and . <= 640)
          and (.stages | type == "array" and length > 0
            and all(.[]; type == "string" and test("^[1-9]-(1[0-9]|[1-9])$")))
          and ((.profileStage // "1-1")
            | type == "string" and test("^[1-9]-(1[0-9]|[1-9])$"))
          and ((.minimumTrialSeconds // 0)
            | type == "number" and floor == . and . >= 0 and . <= 3600)
          and ((.env // {}) | type == "object"
            and all(to_entries[];
              (.key | test("^[A-Z][A-Z0-9_]*$"))
              and (.value | type == "string"
                and test("^[-A-Za-z0-9_./:]+$")))))
    ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null; then
    print -u2 "The performance candidate manifest contract is invalid."
    exit 1
fi
typeset candidate_launcher candidate_profile
while IFS=$'\t' read -r candidate_launcher candidate_profile; do
    if [[ ! -x "$PROJECT_DIR/$candidate_launcher" \
            || ( -n "$candidate_profile" && ! -f "$PROJECT_DIR/$candidate_profile" ) ]]; then
        print -u2 "A performance candidate references a missing launcher or profile: $candidate_launcher ${candidate_profile:-<none>}"
        exit 1
    fi
done < <(jq -r '.candidates[] | [.launcher, (.profile // "")] | @tsv' \
    "$PROJECT_DIR/scripts/performance-candidates.json")

readonly PERFORMANCE_MAX_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini"
readonly PERFORMANCE_MAX_UBO_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-ubo-direct-write.ini"
readonly PERFORMANCE_MAX_UBO_POOL_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-ubo-pool-16m.ini"
readonly PERFORMANCE_MAX_EMITTER_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-emitter-0125.ini"
readonly PERFORMANCE_MAX_PARALLEL_MESH_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-parallel-dynamic-mesh.ini"
readonly PERFORMANCE_MAX_GPU_SCENE_PARALLEL_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-gpu-scene-parallel-512.ini"
readonly PERFORMANCE_MAX_RHI_COMMAND_LIST_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-rhi-command-list.ini"
readonly PERFORMANCE_MAX_FX_BUDGET_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-fx-budget-2ms.ini"
readonly PERFORMANCE_MAX_FX_EARLY_SCHEDULE_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-fx-early-schedule.ini"
readonly PERFORMANCE_MAX_SCALABILITY_PINS_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-scalability-pins.ini"
readonly PERFORMANCE_MAX_ANIMATION_BUDGET_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-animation-budget-1ms.ini"
readonly PERFORMANCE_MAX_ACTOR_POOL_WARMING_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-actor-pool-warming.ini"
readonly PERFORMANCE_MAX_FX_ASYNC_TICK_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-fx-async-tick.ini"
readonly PERFORMANCE_MAX_NIAGARA_ALL_BATCHES_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-niagara-all-batches-async.ini"
readonly PERFORMANCE_MAX_NIAGARA_BATCH_SIZE_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-niagara-batch-size-8.ini"
readonly PERFORMANCE_MAX_DRAG_TICKLESS_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-drag-tickless.ini"
if ! diff -u "$PERFORMANCE_MAX_PROFILE" \
        <(grep -v '^CVars=OpenGL[.]UBODirectWrite=1$' "$PERFORMANCE_MAX_UBO_PROFILE") \
        >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=OpenGL[.]UBOPoolSize=16777216$' \
                "$PERFORMANCE_MAX_UBO_POOL_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(sed 's/^CVars=r[.]EmitterSpawnRateScale=0[.]125$/CVars=r.EmitterSpawnRateScale=0.5/' \
                "$PERFORMANCE_MAX_EMITTER_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=r[.]Visibility[.]DynamicMeshElements[.]Parallel=1$' \
                "$PERFORMANCE_MAX_PARALLEL_MESH_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=r[.]GPUScene[.]ParallelUpdate=512$' \
                "$PERFORMANCE_MAX_GPU_SCENE_PARALLEL_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(sed 's/^CVars=r[.]RHICmdBypass=0$/CVars=r.RHICmdBypass=1/' \
                "$PERFORMANCE_MAX_RHI_COMMAND_LIST_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v -E '^CVars=fx[.](Budget[.](Enabled|GameThread|GameThreadConcurrent|RenderThread)|Niagara[.](UseGlobalFXBudget|Scalability[.]GlobalBudgetCulling))=' \
                "$PERFORMANCE_MAX_FX_BUDGET_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=FX[.]EarlyScheduleAsync=1$' \
                "$PERFORMANCE_MAX_FX_EARLY_SCHEDULE_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v -E '^CVars=(a[.]Budget[.]BudgetMs|r[.]MotionBlur[.]HalfResGather|r[.]Upscale[.]Quality|r[.]Streaming[.]MaxNumTexturesToStreamPerFrame|r[.]TranslucencyLightingVolume[.]Dim|r[.]SSS[.](Scale|SampleSet|Quality|HalfRes)|r[.]SSGI[.]Quality|foliage[.]DensityScale|grass[.]DensityScale|r[.]HairStrands[.]Visibility[.]MSAA[.]SamplePerPixel|r[.]AnisotropicMaterials)=' \
                "$PERFORMANCE_MAX_SCALABILITY_PINS_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=a[.]Budget[.]BudgetMs=1[.]0$' \
                "$PERFORMANCE_MAX_ANIMATION_BUDGET_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=tft[.]ActorPoolWarmingEnabled=1$' \
                "$PERFORMANCE_MAX_ACTOR_POOL_WARMING_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=FX[.]AllowAsyncTick=1$' \
                "$PERFORMANCE_MAX_FX_ASYNC_TICK_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=fx[.]Niagara[.]SystemSimulation[.]TickBatchMode=0$' \
                "$PERFORMANCE_MAX_NIAGARA_ALL_BATCHES_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=fx[.]Niagara[.]SystemSimulation[.]TickBatchSize=8$' \
                "$PERFORMANCE_MAX_NIAGARA_BATCH_SIZE_PROFILE") \
            >/dev/null \
        || ! diff -u "$PERFORMANCE_MAX_PROFILE" \
            <(grep -v '^CVars=tft[.]EnableDragSubsystemTicklessMode=1$' \
                "$PERFORMANCE_MAX_DRAG_TICKLESS_PROFILE") \
            >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-ubo-direct-write-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-ubo-direct-write.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-ubo-pool-16m-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-ubo-pool-16m.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-emitter-0125-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-emitter-0125.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-parallel-dynamic-mesh-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-parallel-dynamic-mesh.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-gpu-scene-parallel-512-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-gpu-scene-parallel-512.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-rhi-command-list-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-rhi-command-list.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-fx-budget-2ms-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-fx-budget-2ms.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-fx-early-schedule-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-fx-early-schedule.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-scalability-pins-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-scalability-pins.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-animation-budget-1ms-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-animation-budget-1ms.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-actor-pool-warming-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-actor-pool-warming.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-fx-async-tick-screen")]
                | length == 0
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-niagara-all-batches-async-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-niagara-all-batches-async.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-niagara-batch-size-8-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-niagara-batch-size-8.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null \
        || ! jq -e '
            [.candidates[]
              | select(.id == "performance-max-drag-tickless-screen")
              | select(.launcher == "run-tft-fast-quality.command")
              | select(.profile | endswith("performance-max-drag-tickless.ini"))]
                | length == 1
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null; then
    print -u2 "Performance Max one-factor profile isolation is incomplete."
    exit 1
fi

readonly FPS_EXPERIMENT_OUTCOME="$PROJECT_DIR/artifacts/fps-experiment-outcome-20260815.json"
if ! jq -e \
        --slurpfile candidates "$PROJECT_DIR/scripts/performance-candidates.json" \
        --slurpfile proxy "$PROJECT_DIR/artifacts/simpleperf-stage1-8-transport-audit-20260815.json" \
        --slurpfile ubo "$PROJECT_DIR/artifacts/android-gles-ubo-stress-screen-20260815.json" \
        --slurpfile density "$PROJECT_DIR/artifacts/android-gles-ubo-density-screen-20260815.json" \
        --slurpfile cross "$PROJECT_DIR/artifacts/android-gles-ubo-transport-crosscheck-20260815.json" \
        --slurpfile startup "$PROJECT_DIR/artifacts/unreal-startup-cvar-audit-20260815.json" \
        --slurpfile draw "$PROJECT_DIR/artifacts/android-gles-draw-stress-screen-20260815.json" \
        --slurpfile scheduler "$PROJECT_DIR/artifacts/thread-scheduler-login-validation-20260815.json" '
        .schema_version == 1
        and .kind == "mactician_fps_experiment_outcome"
        and .late_pvp_measurement.authenticated_real_game_sessions == 0
        and .late_pvp_measurement.new_tft_late_pvp_promotions == 0
        and (.retained_product_changes
            | map(select(.change == "selectable Maximum FPS launcher preset"
                         and (.profile_sha256 | test("^[0-9a-f]{64}$"))))
            | length) == 1
        and .measured_findings.stage_1_8_heavy_proxy.rhi_thread_sample_share_percent
            == $proxy[0].runs[0].guest_cpu_share_percent.RHIThread
        and .measured_findings.stage_1_8_heavy_proxy.transport_symbol_sample_share_percent
            == $proxy[0].runs[0].guest_cpu_share_percent.virtio_gpu_transport
        and .measured_findings.stage_1_8_heavy_proxy.control_fps
            == $proxy[0].runs[0].pacing.fps
        and .measured_findings.synthetic_pooled_ubo_map_once.winning_brackets
            == $cross[0].decision.total_winning_pooled_map_once_brackets
        and .measured_findings.synthetic_pooled_ubo_map_once.total_brackets
            == $cross[0].decision.total_winning_pooled_map_once_brackets
        and .measured_findings.synthetic_pooled_ubo_map_once.asg_256_draw_mean_delta_percent
            == ($ubo[0].strategy_summary[] | select(.mode == "pooled_map_once")
                | {median_time_per_draw: .mean_median_delta_percent,
                   p95_time_per_draw: .mean_p95_delta_percent})
        and .measured_findings.synthetic_pooled_ubo_map_once.asg_512_draw_mean_delta_percent
            == ($density[0].campaigns[] | select(.name == "density-512")
                | {median_time_per_draw: .mean_delta.median_percent,
                   p95_time_per_draw: .mean_delta.p95_percent})
        and .measured_findings.synthetic_pooled_ubo_map_once.asg_1024_draw_mean_delta_percent
            == ($density[0].campaigns[] | select(.name == "density-1024-bounded")
                | {median_time_per_draw: .mean_delta.median_percent,
                   p95_time_per_draw: .mean_delta.p95_percent})
        and .measured_findings.synthetic_pooled_ubo_map_once.pipe_512_draw_mean_delta_percent
            == {median_time_per_draw: $cross[0].pipe_campaign.mean_delta.median_percent,
                p95_time_per_draw: $cross[0].pipe_campaign.mean_delta.p95_percent}
        and .measured_findings.synthetic_pooled_ubo_map_once.gl_error_rounds == 0
        and .measured_findings.resolution_sensitivity_boundary.stage_1_5_fps_2560x1440 == 31.3
        and .measured_findings.resolution_sensitivity_boundary.stage_1_5_fps_1600x900 == 30.5
        and .measured_findings.resolution_sensitivity_boundary.source_pixel_multiplier == 2.56
        and (.measured_findings.resolution_sensitivity_boundary.lower_resolution_fps_delta_percent
            - ((30.5 / 31.3 - 1) * 100) | fabs) < 0.000001
        and .measured_findings.resolution_sensitivity_boundary.decision
            == "do_not_reduce_below_67_percent_as_a_presumed_late_fight_fix"
        and (.retained_product_changes[]
            | select(.change == "explicitly request four remote OpenGL program compiler services")
            | .runtime_startup_transition)
            == $startup[0].observations.performance_max_transitions["Android.OpenGL.NumRemoteProgramCompileServices"]
        and ([.rejected_or_not_promoted[]
              | select(.candidate == "preferCPUForBufferSubData")][0]
              .draw_stress_mean_delta_percent)
            == ($draw[0].comparisons[]
                | select(.candidate == "preferCPUForBufferSubData")
                | {median: .mean_median_time_change_percent,
                   p95: .mean_p95_time_change_percent})
        and ([.rejected_or_not_promoted[]
              | select(.candidate == "disable-useVkEventForBufferBarrier")][0]
              .draw_stress_mean_delta_percent)
            == ($draw[0].comparisons[]
                | select(.candidate == "disable-useVkEventForBufferBarrier")
                | {median: .mean_median_time_change_percent,
                   p95: .mean_p95_time_change_percent})
        and $scheduler[0].decisions.critical_thread_priority_boost
            == "reject_noop_already_nice_minus_10"
        and .next_authenticated_late_pvp_queue
            == ($candidates[0].latePvpPriorityQueue.items | map(.candidateId))
        and .late_pvp_evidence_pipeline.failed_raw_pull_rejects_only_profile_and_removes_partial_file
            == true
        and .safety.stock_rollback_verified == true
        and .safety.emulator_processes_after_shutdown == 0
        and .safety.adb_devices_after_shutdown == 0
        and .safety.avd_lock_present_after_shutdown == false
        and .safety.live_process_recheck.dedicated_adb_5038_processes == 0
        and .safety.live_process_recheck.tft_emulator_processes == 0
        and .safety.live_process_recheck.avd_locks_or_profile_transaction_markers == 0
        and .verification.mactician_fixture_and_unit_tests == "pass"
        and .verification.swift_typecheck == "pass"
        and .verification.repository_validation == "pass_1.0.4_build_40"
        and .verification.go_tests == "not_applicable_no_go_mod_or_go_work_in_repository"
    ' "$FPS_EXPERIMENT_OUTCOME" >/dev/null; then
    print -u2 "The consolidated FPS experiment outcome contract is inconsistent."
    exit 1
fi
typeset fps_outcome_source
while IFS= read -r fps_outcome_source; do
    if [[ ! -f "$PROJECT_DIR/$fps_outcome_source" ]]; then
        print -u2 "FPS experiment outcome references a missing source: $fps_outcome_source"
        exit 1
    fi
done < <(jq -r '
    .retained_product_changes[]?.source // empty,
    .rejected_or_not_promoted[]?.source // empty,
    .measured_findings.stage_1_8_heavy_proxy.source,
    .measured_findings.synthetic_pooled_ubo_map_once.sources[],
    .measured_findings.resolution_sensitivity_boundary.source,
    .safety.source
  ' "$FPS_EXPERIMENT_OUTCOME")

readonly TFT_RUNTIME_BOOLEAN_AUDIT="$PROJECT_DIR/artifacts/tft-runtime-boolean-default-audit-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and ([.observations[]
              | select((.cvar == "tft.ChronoDelayedStart"
                        or .cvar == "tft.FrameAlignmentCompensation"
                        or .cvar == "tft.Movement.PreserveTransformWhenBlendEmpty"
                        or .cvar == "tft.Movement.ReconstructReplicatedMoveOnce")
                       and .default == true)] | length) == 4
        and .decisions.chrono_delayed_start == "reject_noop_already_enabled"
        and .decisions.frame_alignment_compensation == "reject_noop_already_enabled"
        and .decisions.replicated_movement_optimizations == "reject_noops_already_enabled"
        and ([.observations[]
              | select((.cvar == "tft.Audio.PlayOnlyOneArenaAtATime"
                        or .cvar == "tft.Audio.RestrictNumberOfAmbientSounds")
                       and .default == false)] | length) == 2
        and (.decisions.audio_arena_and_ambient_limits
             | startswith("do_not_queue_without_late_pvp_audiomixer_attribution"))
    ' "$TFT_RUNTIME_BOOLEAN_AUDIT" >/dev/null; then
    print -u2 "The Riot runtime optimization default audit is incomplete."
    exit 1
fi

readonly THREADING_AUDIT="$PROJECT_DIR/artifacts/unreal-late-pvp-threading-audit-20260815.json"
readonly PARTICLE_COLD_SCREEN="$PROJECT_DIR/artifacts/particle-scheduling-cold-screen-20260815.json"
readonly NIAGARA_BATCH_RUNTIME="$PROJECT_DIR/artifacts/unreal-niagara-batch-size-8-runtime-audit-20260815.json"
readonly FX_EARLY_STARTUP="$PROJECT_DIR/artifacts/unreal-startup-profile-audit-fx-early-schedule-20260815.json"
readonly NIAGARA_BATCH_STARTUP="$PROJECT_DIR/artifacts/unreal-startup-profile-audit-niagara-batch-size-8-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and ([.observations.audio[]
              | select(.cvar == "AudioThread.EnableBatchProcessing"
                       and .compiled_value_u32 == 1)] | length) == 1
        and ([.observations.audio[]
              | select(.cvar == "AudioThread.BatchAsyncBatchSize"
                       and .compiled_value_u32 == 128)] | length) == 1
        and ([.observations.animation[]
              | select((.cvar == "a.ParallelAnimEvaluation"
                        or .cvar == "a.ParallelAnimUpdate"
                        or .cvar == "a.ParallelAnimInterpolation"
                        or .cvar == "a.ParallelBlendPhysics")
                       and .compiled_value_u32 == 1)] | length) == 4
        and ([.observations.niagara_and_particles[]
              | select(.cvar == "FX.EarlyScheduleAsync"
                       and .compiled_value_u32 == 0)] | length) == 1
        and ([.observations.niagara_and_particles[]
              | select(.cvar == "fx.Niagara.SystemSimulation.TickBatchSize"
                       and .compiled_value_u32 == 4)] | length) == 1
        and (.decisions.boundary | startswith("Neither queued candidate is promoted"))
    ' "$THREADING_AUDIT" >/dev/null \
        || ! jq -e '
            .schema_version == 1
            and (.runs | length) == 2
            and all(.runs[];
              .boot_ms > 0
              and .memory_kib.swap == 0
              and .crash_buffer_empty == true
              and .tombstone_file_count == 12
              and .fresh_tombstone == false)
            and ([.runs[]
                  | select(.candidate == "FX.EarlyScheduleAsync=1"
                           and .startup_transition == "0 -> 1")] | length) == 1
            and ([.runs[]
                  | select(.candidate == "fx.Niagara.SystemSimulation.TickBatchSize=8"
                           and .startup_transition == "4 -> 8"
                           and .live_value_u32 == 8
                           and .adjacent_live_invariants.AllowASync == 1
                           and .adjacent_live_invariants.TickBatchMode == 1
                           and .adjacent_live_invariants.ConcurrentGPUTickInit == 1
                           and .adjacent_live_invariants.BatchGPUTickSubmit == 1)]
                | length) == 1
            and .decision.promotion == "none"
        ' "$PARTICLE_COLD_SCREEN" >/dev/null \
        || ! jq -e '
            .schema_version == 1
            and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
            and ([.values[]
                  | select(.cvar == "fx.Niagara.SystemSimulation.TickBatchSize"
                           and .value_u32 == 8)] | length) == 1
            and ([.values[]
                  | select((.cvar == "fx.Niagara.SystemSimulation.AllowASync"
                            or .cvar == "fx.Niagara.SystemSimulation.TickBatchMode"
                            or .cvar == "fx.Niagara.SystemSimulation.ConcurrentGPUTickInit"
                            or .cvar == "fx.Niagara.SystemSimulation.BatchGPUTickSubmit")
                           and .value_u32 == 1)] | length) == 4
        ' "$NIAGARA_BATCH_RUNTIME" >/dev/null \
        || ! jq -e '
            .result.delta_count == 1
            and .result.startup_attested_count == 1
            and .result.all_deltas_startup_attested == true
            and .deltas[0].key == "FX.EarlyScheduleAsync"
            and .deltas[0].candidate_value == "1"
        ' "$FX_EARLY_STARTUP" >/dev/null \
        || ! jq -e '
            .result.delta_count == 1
            and .result.startup_attested_count == 1
            and .result.all_deltas_startup_attested == true
            and .deltas[0].key == "fx.Niagara.SystemSimulation.TickBatchSize"
            and .deltas[0].candidate_value == "8"
        ' "$NIAGARA_BATCH_STARTUP" >/dev/null \
        || [[ "$(shasum -a 256 "$PERFORMANCE_MAX_FX_EARLY_SCHEDULE_PROFILE" | awk '{ print $1 }')" \
            != "$(jq -r '.runs[] | select(.candidate == "FX.EarlyScheduleAsync=1") | .profile_sha256' "$PARTICLE_COLD_SCREEN")" ]] \
        || [[ "$(shasum -a 256 "$PERFORMANCE_MAX_NIAGARA_BATCH_SIZE_PROFILE" | awk '{ print $1 }')" \
            != "$(jq -r '.runs[] | select(.candidate == "fx.Niagara.SystemSimulation.TickBatchSize=8") | .profile_sha256' "$PARTICLE_COLD_SCREEN")" ]]; then
    print -u2 "The particle-scheduling static, startup, or cold-screen evidence is incomplete."
    exit 1
fi

readonly PARALLEL_DYNAMIC_MESH_COLD_SCREEN="$PROJECT_DIR/artifacts/unreal-parallel-dynamic-mesh-cold-screen-20260815.json"
readonly PARALLEL_DYNAMIC_MESH_STARTUP="$PROJECT_DIR/artifacts/unreal-startup-profile-audit-parallel-dynamic-mesh-20260815.json"
if ! jq -e '
        .schema_version == 1
        and (.runs | length) == 2
        and all(.runs[];
          (.memory_samples_kib | length) == 3
          and all(.memory_samples_kib[]; .swap == 0)
          and .crash_buffer_empty == true
          and .tombstone_file_count == 12
          and .fresh_tombstone == false)
        and .decision.status == "queued_unpromoted"
        and .decision.promotion == "none"
    ' "$PARALLEL_DYNAMIC_MESH_COLD_SCREEN" >/dev/null \
        || ! jq -e '
            .result.delta_count == 1
            and .result.startup_attested_count == 1
            and .result.all_deltas_startup_attested == true
            and .deltas[0].key == "r.Visibility.DynamicMeshElements.Parallel"
            and .deltas[0].candidate_value == "1"
        ' "$PARALLEL_DYNAMIC_MESH_STARTUP" >/dev/null \
        || [[ "$(shasum -a 256 "$PERFORMANCE_MAX_PARALLEL_MESH_PROFILE" | awk '{ print $1 }')" \
            != "$(jq -r '.client.candidate_profile_sha256' "$PARALLEL_DYNAMIC_MESH_COLD_SCREEN")" ]]; then
    print -u2 "The parallel dynamic-mesh startup or cold-screen evidence is incomplete."
    exit 1
fi

readonly GPU_SCENE_PARALLEL_COLD_SCREEN="$PROJECT_DIR/artifacts/unreal-gpu-scene-parallel-cold-screen-20260815.json"
readonly GPU_SCENE_PARALLEL_STARTUP="$PROJECT_DIR/artifacts/unreal-startup-profile-audit-gpu-scene-parallel-512-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .client.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and ([.static_support.observations[]
              | select(.cvar == "r.GPUScene.ParallelUpdate"
                       and .compiled_value_u32 == 2048)] | length) == 1
        and ([.static_support.observations[]
              | select(.cvar == "r.GPUScene.MaxPooledUploadBufferSize"
                       and .compiled_value_u32 == 256000)] | length) == 1
        and ([.static_support.observations[]
              | select(.cvar == "r.GPUScene.UseGrowOnlyAllocationPolicy"
                       and .compiled_value_u32 == 0)] | length) == 1
        and ([.static_support.observations[]
              | select(.cvar == "r.GPUScene.Lights.AsyncSetup"
                       and .compiled_value_u32 == 1)] | length) == 1
        and ([.static_support.observations[]
              | select(.cvar == "r.GPUScene.InstanceDataTileSizeLog2"
                       and .compiled_value_i32 == -1)] | length) == 1
        and ([.static_support.observations[]
              | select((.cvar == "fx.Niagara.ParallelGDME"
                        or .cvar == "r.Visibility.TaskSchedule"
                        or .cvar == "r.ParallelTranslucency")
                       and .compiled_value_u32 == 1)] | length) == 3
        and ([.static_support.observations[]
              | select((.cvar == "r.Visibility.FrustumCull.NumPrimitivesPerTask"
                        or .cvar == "r.Visibility.Relevance.NumPrimitivesPerPacket")
                       and .compiled_value_u32 == 0
                       and (.decision | contains("automatic sizing")))] | length) == 2
        and (.runs | length) == 2
        and all(.runs[];
          (.memory_samples_kib | length) == 3
          and all(.memory_samples_kib[]; .swap == 0)
          and .crash_buffer_empty == true
          and .tombstone_file_count == 12
          and .fresh_tombstone == false)
        and (.comparison.candidate_vs_control_mean_pss_percent | fabs) < 0.1
        and (.comparison.candidate_vs_control_mean_rss_percent | fabs) < 0.1
        and .decision.status == "queued_unpromoted"
        and .decision.promotion == "none"
    ' "$GPU_SCENE_PARALLEL_COLD_SCREEN" >/dev/null \
        || ! jq -e '
            .result.delta_count == 1
            and .result.startup_attested_count == 1
            and .result.all_deltas_startup_attested == true
            and .deltas[0].key == "r.GPUScene.ParallelUpdate"
            and .deltas[0].candidate_value == "512"
        ' "$GPU_SCENE_PARALLEL_STARTUP" >/dev/null \
        || [[ "$(shasum -a 256 "$PERFORMANCE_MAX_GPU_SCENE_PARALLEL_PROFILE" | awk '{ print $1 }')" \
            != "$(jq -r '.client.candidate_profile_sha256' "$GPU_SCENE_PARALLEL_COLD_SCREEN")" ]]; then
    print -u2 "The GPU Scene parallel startup, static, or cold-screen evidence is incomplete."
    exit 1
fi

readonly RHI_COMMAND_LIST_COLD_SCREEN="$PROJECT_DIR/artifacts/unreal-rhi-command-list-cold-screen-20260815.json"
readonly RHI_COMMAND_LIST_STARTUP="$PROJECT_DIR/artifacts/unreal-startup-profile-audit-rhi-command-list-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .client.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and ([.static_support.observations[]
              | select(.cvar == "r.RHICmdBypass" and .compiled_value_u32 == 0)]
            | length) == 1
        and ([.static_support.observations[]
              | select((.cvar == "r.OpenGL.AllowRHIThread"
                        or .cvar == "r.RHICmd.ParallelTranslate.Enable"
                        or .cvar == "r.MeshDrawCommands.UseCachedCommands")
                       and .compiled_value_u32 == 1)] | length) == 3
        and ([.static_support.observations[]
              | select(.cvar == "r.RHICmd.ParallelTranslate.MaxCommandsPerTranslate"
                       and .compiled_value_u32 == 256)] | length) == 1
        and ([.static_support.observations[]
              | select(.cvar == "r.RHICmdMinDrawsPerParallelCmdList"
                       and .compiled_value_u32 == 64)] | length) == 1
        and (.runs | length) == 2
        and all(.runs[];
          (.memory_samples_kib | length) == 3
          and all(.memory_samples_kib[]; .swap == 0)
          and .crash_buffer_empty == true
          and .tombstone_file_count == 12
          and .fresh_tombstone == false)
        and .comparison.candidate_vs_control_mean_pss_percent < 0
        and .comparison.candidate_vs_control_mean_rss_percent < 0
        and .decision.status == "queued_unpromoted"
        and .decision.promotion == "none"
    ' "$RHI_COMMAND_LIST_COLD_SCREEN" >/dev/null \
        || ! jq -e '
            .result.delta_count == 1
            and .result.startup_attested_count == 1
            and .result.all_deltas_startup_attested == true
            and .deltas[0].key == "r.RHICmdBypass"
            and .deltas[0].base_value == "1"
            and .deltas[0].candidate_value == "0"
        ' "$RHI_COMMAND_LIST_STARTUP" >/dev/null \
        || [[ "$(shasum -a 256 "$PERFORMANCE_MAX_RHI_COMMAND_LIST_PROFILE" | awk '{ print $1 }')" \
            != "$(jq -r '.client.candidate_profile_sha256' "$RHI_COMMAND_LIST_COLD_SCREEN")" ]]; then
    print -u2 "The RHI command-list static or cold-screen evidence is incomplete."
    exit 1
fi

if ! grep -Fq 'osft-no-fence-contexts' "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq -- '-VirtioGpuFenceContexts' \
            "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! jq -e '
            [.candidates[].id] as $ids
            | ($ids | index("performance-max-no-fence-contexts-screen")) != null
              and ($ids | index("performance-max-no-virtual-queue-screen")) == null
              and ($ids | index("performance-max-no-queue-submit-with-commands-screen")) == null
              and ($ids | index("performance-max-argument-buffers-off-screen")) == null
              and ($ids | index("performance-max-single-queue-semaphores-screen")) == null
        ' "$PROJECT_DIR/scripts/performance-candidates.json" >/dev/null; then
    print -u2 "The rejected/no-op performance candidate isolation is incomplete."
    exit 1
fi

if ! grep -Fq 'readonly HOST_GPU="${TFT_HOST_GPU:-host}"' \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq -- '-gpu "$HOST_GPU"' \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'TFT_HOST_GPU must be either host or swangle.' \
        "$PROJECT_DIR/run-tft-root-affinity.command" \
        || ! grep -Fq 'host ANGLE -> Vulkan -> SwiftShader CPU' \
        "$PROJECT_DIR/run-tft-root-affinity.command"; then
    print -u2 "The bounded host swangle GLES control is incomplete."
    exit 1
fi

if ! jq -e '
        .schemaVersion == 1
        and (.runs | length) == 10
        and (.aggregates | length) == 5
        and ([.runs[].label] | unique | length) == 10
        and ([.runs[].summarySha256] | unique | length) == 10
        and all(.runs[]; .summarySha256 | test("^[0-9a-f]{64}$"))
        and ([.runs[].graphicsProfile] | unique | length) == 5
        and (.invariants.display == "2560x1440")
        and (.invariants.displayDensityDpi == 320)
        and (.invariants.transport == "virtio-gpu-asg")
        and (.invariants.hwuiRenderer == "skiavk")
        and (.invariants.roundsPerRun == 12)
        and (.invariants.warmupRoundsDiscarded == 3)
        and ([.aggregates[] | select(.graphicsProfile == "osft")][0].warmRounds == 36)
        and ([.aggregates[] | select(.decision == "keep")] | length) == 1
        and (. as $document
          | all($document.aggregates[];
              . as $aggregate
              | [$document.runs[]
                  | select(.graphicsProfile == $aggregate.graphicsProfile)] as $runs
              | ($runs | length) == $aggregate.validRuns
                and (($runs | length) * 9) == $aggregate.warmRounds
                and (((($runs | map(.warmMeanElapsedMs) | add) / ($runs | length))
                  - $aggregate.warmMeanElapsedMs) | fabs) < 0.000001
                and ($runs | map(.warmMaxP95Ms) | max) == $aggregate.warmMaxP95Ms
                and ($runs | map(.warmMaxP99Ms) | max) == $aggregate.warmMaxP99Ms
                and ($runs | map(.warmTotalJankyFrames) | add)
                  == $aggregate.warmTotalJankyFrames))
    ' "$PROJECT_DIR/artifacts/android-ui-transport-attested-20260811.json" \
        >/dev/null; then
    print -u2 "The attested Android UI transport result artifact is incomplete."
    exit 1
fi
typeset source_summary source_label source_utc source_expected_sha source_actual_sha
for source_summary in \
        "$PROJECT_DIR"/runtime/measurements/android-ui-transport/*/summary.json(N); do
    source_label="$(jq -r '.label // ""' "$source_summary")"
    source_utc="$(jq -r '.utc // ""' "$source_summary")"
    source_expected_sha="$(
        jq -r \
            --arg target_label "$source_label" \
            --arg target_utc "$source_utc" \
            '.runs[]
              | select(.label == $target_label and .utc == $target_utc)
              | .summarySha256' \
            "$PROJECT_DIR/artifacts/android-ui-transport-attested-20260811.json"
    )"
    [[ -n "$source_expected_sha" ]] || continue
    source_actual_sha="$(shasum -a 256 "$source_summary" | awk '{ print $1 }')"
    if [[ "$source_actual_sha" != "$source_expected_sha" ]]; then
        print -u2 "An attested Android UI source summary no longer matches its recorded SHA: $source_label"
        exit 1
    fi
done

if ! jq -e '
        .schema_version == 1
        and (.probe.apk_sha256 | test("^[0-9a-f]{64}$"))
        and (.probe.manifest_sha256 | test("^[0-9a-f]{64}$"))
        and (.probe.activity_source_sha256 | test("^[0-9a-f]{64}$"))
        and .workload.rounds == 20
        and .workload.discarded_warmup_rounds == 7
        and .workload.measured_rounds == 13
        and .workload.updates_per_round == 100000
        and .workload.bytes_per_update == 16384
        and (.runs | length) == 9
        and ([.runs[].utc] | length == (unique | length))
        and all(.runs[]; .gl_error_rounds == 0)
        and ([.runs[] | select(.candidate == "control")] | length) == 3
        and ([.comparisons[] | select(.decision == "rejected_slower")] | length) == 1
        and ([.comparisons[] | select(.decision == "neutral_not_promoted")] | length) == 1
        and ([.comparisons[] | select(.decision == "rejected_slower_and_tail_worse")] | length) == 1
        and .excluded_pilot.apk_sha256 == "22a920f5f36d645392ac8f75087aa11d55f3bfba0f363188ca5dee0a755a93e6"
    ' "$PROJECT_DIR/artifacts/android-gles-buffer-stress-screen-20260815.json" >/dev/null \
        || ! grep -Fq 'GLES31.glMemoryBarrier(GLES31.GL_BUFFER_UPDATE_BARRIER_BIT)' \
            "$PROJECT_DIR/artifacts/android-gles-buffer-stress-app/src/dev/sergeinaumov/mactician/glesprobe/StressActivity.java" \
        || ! grep -Fq 'GLES30.glBufferSubData' \
            "$PROJECT_DIR/artifacts/android-gles-buffer-stress-app/src/dev/sergeinaumov/mactician/glesprobe/StressActivity.java" \
        || ! grep -Fq 'guest_angle_mapped' \
            "$PROJECT_DIR/scripts/run-android-gles-buffer-stress.command" \
        || ! grep -Fq 'ranchu_vulkan_mapped' \
            "$PROJECT_DIR/scripts/run-android-gles-buffer-stress.command"; then
    print -u2 "The attested Android GLES buffer-stress artifact is incomplete."
    exit 1
fi

readonly GLES_BUFFER_MANIFEST="$PROJECT_DIR/artifacts/android-gles-buffer-stress-app/AndroidManifest.xml"
readonly GLES_BUFFER_ACTIVITY="$PROJECT_DIR/artifacts/android-gles-buffer-stress-app/src/dev/sergeinaumov/mactician/glesprobe/StressActivity.java"
if [[ "$(shasum -a 256 "$GLES_BUFFER_MANIFEST" | awk '{ print $1 }')" \
            != "$(jq -r '.probe.manifest_sha256' "$PROJECT_DIR/artifacts/android-gles-buffer-stress-screen-20260815.json")" ]] \
        || [[ "$(shasum -a 256 "$GLES_BUFFER_ACTIVITY" | awk '{ print $1 }')" \
            != "$(jq -r '.probe.activity_source_sha256' "$PROJECT_DIR/artifacts/android-gles-buffer-stress-screen-20260815.json")" ]]; then
    print -u2 "The buffer-stress source no longer matches its curated evidence hashes."
    exit 1
fi

readonly GLES_DRAW_ARTIFACT="$PROJECT_DIR/artifacts/android-gles-draw-stress-screen-20260815.json"
readonly GLES_DRAW_MANIFEST="$PROJECT_DIR/artifacts/android-gles-draw-stress-app/AndroidManifest.xml"
readonly GLES_DRAW_ACTIVITY="$PROJECT_DIR/artifacts/android-gles-draw-stress-app/src/dev/sergeinaumov/mactician/glesdraw/DrawStressActivity.java"
if ! jq -e '
        .schema_version == 1
        and .workload.rounds == 20
        and .workload.discarded_warmup_rounds == 7
        and .workload.measured_rounds == 13
        and .workload.total_draw_calls_per_round == 30840
        and (.runs | length) == 11
        and ([.runs[].utc] | length == (unique | length))
        and all(.runs[]; .gl_error_rounds == 0 and .rollback_verified == true)
        and ([.runs[] | select(.candidate == "control")] | length) == 3
        and (.comparisons | length) == 4
        and (.promotion_policy.promoted_candidates | length) == 0
        and .campaign.successful_runs == 11
        and .campaign.failed_runs == 0
        and .campaign.queue_completed == true
        and (. as $document
          | ($document.runs[] | select(.utc == "20260815T002249Z").median_ns_per_draw) as $c0
          | ($document.runs[] | select(.utc == "20260815T002750Z").median_ns_per_draw) as $c1
          | ($document.runs[] | select(.utc == "20260815T003252Z").median_ns_per_draw) as $c2
          | (($c0 + $c1) / 2) as $block0
          | (($c1 + $c2) / 2) as $block1
          | ((($block0 - $document.control_blocks[0].mean_control_median_ns_per_draw) | fabs) < 0.000001
            and (($block1 - $document.control_blocks[1].mean_control_median_ns_per_draw) | fabs) < 0.000001)
        )
        and ([.comparisons[] | select(.decision == "rejected_slower")] | length) == 1
        and ([.comparisons[] | select(.decision == "rejected_tail_regression")] | length) == 1
        and ([.comparisons[] | select(.decision | startswith("neutral_"))] | length) == 2
    ' "$GLES_DRAW_ARTIFACT" >/dev/null \
        || [[ "$(shasum -a 256 "$GLES_DRAW_MANIFEST" | awk '{ print $1 }')" \
            != "$(jq -r '.probe.manifest_sha256' "$GLES_DRAW_ARTIFACT")" ]] \
        || [[ "$(shasum -a 256 "$GLES_DRAW_ACTIVITY" | awk '{ print $1 }')" \
            != "$(jq -r '.probe.activity_source_sha256' "$GLES_DRAW_ARTIFACT")" ]] \
        || ! grep -Fq 'GLES31.GL_TEXTURE_FETCH_BARRIER_BIT' "$GLES_DRAW_ACTIVITY" \
        || ! grep -Fq 'GLES30.glBufferSubData' "$GLES_DRAW_ACTIVITY" \
        || ! grep -Fq 'TFT_GLES_DRAW_EXPECTED_GRAPHICS_PROFILE is required' \
            "$PROJECT_DIR/scripts/run-android-gles-draw-stress.command"; then
    print -u2 "The attested Android GLES draw-stress artifact is incomplete."
    exit 1
fi

readonly GLES_UBO_MANIFEST="$PROJECT_DIR/artifacts/android-gles-ubo-stress-app/AndroidManifest.xml"
readonly GLES_UBO_ACTIVITY="$PROJECT_DIR/artifacts/android-gles-ubo-stress-app/src/dev/sergeinaumov/mactician/glesubo/UboStressActivity.java"
readonly GLES_UBO_ARTIFACT="$PROJECT_DIR/artifacts/android-gles-ubo-stress-screen-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "android_gles_ubo_strategy_campaign"
        and .workload.rounds == 20
        and .workload.warmup_rounds == 7
        and .workload.measured_rounds == 13
        and .workload.total_draw_calls_per_round == 30720
        and .campaign.successful_runs == 13
        and .campaign.control_runs == 7
        and .campaign.candidate_runs == 6
        and .campaign.failed_runs == 0
        and (.runs | length) == 13
        and ([.runs[].utc] | length == (unique | length))
        and all(.runs[]; .gl_error_rounds == 0)
        and (.comparisons | length) == 6
        and ([.comparisons[] | select(.candidate_mode == "pooled_map_once"
                                      and .decision == "synthetic_faster")] | length) == 2
        and ([.comparisons[] | select(.candidate_mode == "pooled_subdata"
                                      and .decision == "synthetic_slower")] | length) == 2
        and ([.strategy_summary[] | select(.mode == "pooled_map_once")][0]
             | .mean_median_delta_percent < -30 and .mean_p95_delta_percent < -25)
        and ([.strategy_summary[] | select(.mode == "pooled_subdata")][0]
             | .mean_median_delta_percent > 1000 and .mean_p95_delta_percent > 1000)
    ' "$GLES_UBO_ARTIFACT" >/dev/null \
        || [[ "$(shasum -a 256 "$GLES_UBO_MANIFEST" | awk '{ print $1 }')" \
            != "$(jq -r '.probe.manifest_sha256' "$GLES_UBO_ARTIFACT")" ]] \
        || [[ "$(shasum -a 256 "$GLES_UBO_ACTIVITY" | awk '{ print $1 }')" \
            != "$(jq -r '.probe.activity_source_sha256' "$GLES_UBO_ARTIFACT")" ]] \
        || ! grep -Fq 'GLES30.glMapBufferRange' "$GLES_UBO_ACTIVITY" \
        || ! grep -Fq 'GLES30.glBindBufferRange' "$GLES_UBO_ACTIVITY" \
        || ! grep -Fq 'GLES30.glBufferSubData' "$GLES_UBO_ACTIVITY" \
        || ! grep -Fq 'GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT' "$GLES_UBO_ACTIVITY" \
        || ! grep -Fq 'TFT_GLES_UBO_EXPECTED_GRAPHICS_PROFILE is required' \
            "$PROJECT_DIR/scripts/run-android-gles-ubo-stress.command" \
        || ! grep -Fq 'campaign must alternate hash-identical control/candidate runs' \
            "$PROJECT_DIR/scripts/summarize-android-gles-ubo-campaign.command" \
        || ! grep -Fq 'package="dev.sergeinaumov.mactician.glesubo"' "$GLES_UBO_MANIFEST"; then
    print -u2 "The Android GLES UBO-stress probe is incomplete."
    exit 1
fi

readonly GLES_UBO_DENSITY_ARTIFACT="$PROJECT_DIR/artifacts/android-gles-ubo-density-screen-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "android_gles_ubo_density_screen"
        and (.probe.apk_sha256 | test("^[0-9a-f]{64}$"))
        and (.probe.manifest_sha256 | test("^[0-9a-f]{64}$"))
        and (.probe.activity_source_sha256 | test("^[0-9a-f]{64}$"))
        and (.campaigns | length) == 2
        and ([.campaigns[].workload.draws_per_frame] == [512, 1024])
        and all(.campaigns[];
            .campaign.successful_runs == 5
            and .campaign.control_runs == 3
            and .campaign.candidate_runs == 2
            and .campaign.failed_runs == 0
            and .campaign.alternating_bracket_design == true
            and .campaign.gl_error_rounds == 0
            and (.runs | length) == 5
            and (.bracket_deltas | length) == 2
            and all(.bracket_deltas[];
                .decision == "synthetic_faster"
                and .median_percent < -40
                and .p95_percent < -40)
            and .mean_delta.median_percent < -40
            and .mean_delta.p95_percent < -40)
        and (.excluded_attempts | length) == 1
        and .excluded_attempts[0].result == "no_summary_excluded"
        and .decision.status == "prioritize_existing_ubo_pool_candidate_unpromoted"
        and .decision.promotion == "none"
    ' "$GLES_UBO_DENSITY_ARTIFACT" >/dev/null \
        || [[ "$(jq -r '.probe.apk_sha256' "$GLES_UBO_DENSITY_ARTIFACT")" \
            != "$(jq -r '.probe.apk_sha256' "$GLES_UBO_ARTIFACT")" ]] \
        || [[ "$(jq -r '.probe.manifest_sha256' "$GLES_UBO_DENSITY_ARTIFACT")" \
            != "$(jq -r '.probe.manifest_sha256' "$GLES_UBO_ARTIFACT")" ]] \
        || [[ "$(jq -r '.probe.activity_source_sha256' "$GLES_UBO_DENSITY_ARTIFACT")" \
            != "$(jq -r '.probe.activity_source_sha256' "$GLES_UBO_ARTIFACT")" ]]; then
    print -u2 "The Android GLES UBO density screen is incomplete."
    exit 1
fi

readonly GLES_UBO_TRANSPORT_CROSSCHECK="$PROJECT_DIR/artifacts/android-gles-ubo-transport-crosscheck-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "android_gles_ubo_transport_crosscheck"
        and .shared_workload.draws_per_frame == 512
        and .shared_workload.total_draw_calls_per_round == 61440
        and .shared_runtime.graphics_profile == "osft"
        and .pipe_campaign.transport == "pipe"
        and .pipe_campaign.successful_runs == 5
        and .pipe_campaign.failed_runs == 0
        and (.pipe_campaign.runs | length) == 5
        and all(.pipe_campaign.runs[]; .gl_error_rounds == 0)
        and (.pipe_campaign.bracket_deltas | length) == 2
        and all(.pipe_campaign.bracket_deltas[];
            .decision == "synthetic_faster"
            and .median_percent < -40
            and .p95_percent < -40)
        and .pipe_campaign.mean_delta.median_percent < -40
        and .pipe_campaign.mean_delta.p95_percent < -40
        and .asg_reference.transport == "virtio-gpu-asg"
        and .asg_reference.brackets == 2
        and .asg_reference.all_decisions == "synthetic_faster"
        and .decision.strategy_result == "pooled_map_once_wins_on_both_transports"
        and .decision.total_winning_pooled_map_once_brackets == 8
        and .decision.transport_selection == "unchanged"
        and .decision.promotion == "none"
    ' "$GLES_UBO_TRANSPORT_CROSSCHECK" >/dev/null \
        || [[ "$(jq -r '.probe.apk_sha256' "$GLES_UBO_TRANSPORT_CROSSCHECK")" \
            != "$(jq -r '.probe.apk_sha256' "$GLES_UBO_ARTIFACT")" ]] \
        || [[ "$(jq -r '.probe.manifest_sha256' "$GLES_UBO_TRANSPORT_CROSSCHECK")" \
            != "$(jq -r '.probe.manifest_sha256' "$GLES_UBO_ARTIFACT")" ]] \
        || [[ "$(jq -r '.probe.activity_source_sha256' "$GLES_UBO_TRANSPORT_CROSSCHECK")" \
            != "$(jq -r '.probe.activity_source_sha256' "$GLES_UBO_ARTIFACT")" ]]; then
    print -u2 "The Android GLES UBO transport cross-check is incomplete."
    exit 1
fi

readonly OPENGL_UBO_CAPACITY_AUDIT="$PROJECT_DIR/artifacts/unreal-opengl-ubo-capacity-sizing-audit-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "unreal_opengl_ubo_capacity_sizing_audit"
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and .source.synthetic_activity_sha256 == "ec1f074e2d1ce10c87fea872252b75a4a48cd80be38235c7ba445be6885aa754"
        and .exact_binary_observations.cvar_registration.storage_vma == "0xbc7dbf4"
        and .exact_binary_observations.cvar_registration.compiled_referenced_default_u32 == 0
        and .exact_binary_observations.uniform_buffer_allocation.gl_target == "0x8a11"
        and .exact_binary_observations.runtime_values.general_uniform_buffer_pooling_effective_u32 == 1
        and .exact_binary_observations.runtime_values.opengl_pool_candidate_u32 == 16777216
        and .synthetic_scope.ubo_stride_bytes == 32
        and ([.synthetic_scope.measured_working_sets[].draws_per_frame] == [256, 512, 1024])
        and ([.synthetic_scope.measured_working_sets[].pooled_buffer_bytes] == [8192, 16384, 32768])
        and ([.synthetic_scope.measured_working_sets[].winning_brackets] | add) == 8
        and .synthetic_scope.largest_measured_working_set_bytes == 32768
        and .synthetic_scope.probe_working_set_ceiling_bytes == 65536
        and .synthetic_scope.candidate_capacity_bytes == 16777216
        and .synthetic_scope.candidate_to_largest_measured_ratio == 512
        and .synthetic_scope.candidate_to_probe_ceiling_ratio == 256
        and .decision.queue_order == "retain_priority_1_unpromoted"
        and .decision.capacity_size_confidence == "unsized_hypothesis"
        and .decision.candidate_added == false
        and .decision.promotion == "none"
    ' "$OPENGL_UBO_CAPACITY_AUDIT" >/dev/null \
        || [[ "$(shasum -a 256 "$GLES_UBO_ACTIVITY" | awk '{ print $1 }')" \
            != "$(jq -r '.source.synthetic_activity_sha256' "$OPENGL_UBO_CAPACITY_AUDIT")" ]] \
        || ! grep -Fq 'int bufferBytes = pooled ? Math.multiplyExact(stride, drawsPerFrame)' \
            "$GLES_UBO_ACTIVITY"; then
    print -u2 "The Unreal OpenGL UBO capacity-sizing audit is incomplete."
    exit 1
fi

readonly SIMPLEPERF_RHI_OFFSET_AUDIT="$PROJECT_DIR/artifacts/simpleperf-rhi-unreal-offset-audit-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "simpleperf_rhi_unreal_offset_audit"
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and ([.source.reports[].sha256] == [
            "571900eec054612852631ebaa9a8064e38d1afbc54fd44f446ee8f3207932864",
            "840394b8b4d729fdd90b7691c2015af6cdef8f70bd50afc1e3a22f5514f2808c",
            "0ddaa81a728eb82a7fdddc85c5947254575ac03fb847e827acf868d6b316433b"
        ])
        and .methodology.audited_ranges.buffer_ubo_corridor == ["0x6ff4e68", "0x700fcf8"]
        and ([.results[].rhi_thread_total_percent] == [31.49, 37.50, 33.93])
        and ([.results[].transport_leaf_percent] == [16.44, 19.78, 18.52])
        and ([.results[].rhi_stripped_unreal_leaf_percent] == [1.60, 1.90, 1.50])
        and all(.results[];
            .buffer_ubo_corridor_percent == 0
            and .buffer_ubo_corridor_rows == 0)
        and .decision.direct_ubo_leaf_attribution == "not_observed_in_flat_reports"
        and (.decision.ubo_queue_order | startswith("retain_priority_1_unpromoted"))
        and .decision.candidate_added == false
        and .decision.promotion == "none"
    ' "$SIMPLEPERF_RHI_OFFSET_AUDIT" >/dev/null \
        || ! grep -Fq 'pull "$remote_data" "$profile_dir/simpleperf.data"' \
            "$PROJECT_DIR/scripts/capture-late-pvp-session.command" \
        || ! grep -Fq 'retain call chains for caller-inclusive offline attribution' \
            "$PROJECT_DIR/scripts/capture-late-pvp-session.command"; then
    print -u2 "The simpleperf RHI stripped-offset audit is incomplete."
    exit 1
fi

readonly STOCK_ROLLBACK_ARTIFACT="$PROJECT_DIR/artifacts/stock-rollback-validation-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "stock_rollback_validation"
        and .launch.renderer == "angle"
        and .launch.graphics_profile == "stable"
        and .launch.overlay_requested == false
        and .launch.cold_boot == true
        and .launch.pre_boot_config_transport == "pipe"
        and .launch.pre_boot_generated_transport == "pipe"
        and .live_attestation.tft_pid_positive == true
        and (.live_attestation.installed_base_apk_sha256
             == .live_attestation.expected_original_base_apk_sha256)
        and .live_attestation.device_profile_present == false
        and .live_attestation.device_profile_mount_count == 0
        and .live_attestation.base_apk_mount_count == 0
        and .live_attestation.angle_profile_transaction_markers == 0
        and .live_attestation.direct_vulkan_profile_transaction_markers == 0
        and .live_attestation.boot_transport == "pipe"
        and .live_attestation.boot_graphics_profile == "stable"
        and .live_attestation.crash_buffer_lines == 0
        and .shutdown_attestation.intentional_interrupt_exit_code == 130
        and .shutdown_attestation.adb_devices == 0
        and .shutdown_attestation.emulator_processes == 0
        and .shutdown_attestation.avd_lock_present == false
        and .shutdown_attestation.post_shutdown_config_transport == "pipe"
        and .shutdown_attestation.post_shutdown_generated_transport == "pipe"
        and .shutdown_attestation.repeat_after_pipe_crosscheck.adb_devices == 0
        and .shutdown_attestation.repeat_after_pipe_crosscheck.emulator_processes == 0
        and .shutdown_attestation.repeat_after_pipe_crosscheck.avd_lock_present == false
        and .shutdown_attestation.repeat_after_pipe_crosscheck.config_transport == "pipe"
        and .shutdown_attestation.repeat_after_pipe_crosscheck.generated_transport == "pipe"
        and .decision.rollback_verified == true
        and .decision.experimental_mounts_active == false
        and .decision.experimental_avd_process_active == false
    ' "$STOCK_ROLLBACK_ARTIFACT" >/dev/null; then
    print -u2 "The final stock rollback attestation is incomplete."
    exit 1
fi

readonly SKELETAL_HOT_PATH_AUDIT="$PROJECT_DIR/artifacts/unreal-skeletal-hot-path-audit-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "unreal_skeletal_hot_path_static_audit"
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and (.observations | length) == 7
        and ([.observations[]
              | select((.cvar == "a.CacheLocalSpaceBounds"
                        or .cvar == "tick.HiPriSkinnedMeshes"
                        or .cvar == "r.Skinning.Buffers.AsyncUpdate"
                        or .cvar == "r.SkeletalMesh.UseCachedMDCs"
                        or .cvar == "r.SkeletalMesh.UpdateMethod"
                        or .cvar == "r.RenderCommandPipe.SkeletalMesh")
                       and .compiled_value_u32 == 1)] | length) == 6
        and ([.observations[]
              | select(.cvar == "r.SkeletalMesh.DynamicDataPoolBudget"
                       and .compiled_value_u32 == 4096
                       and .unit == "KiB")] | length) == 1
        and (.cross_checked_existing_defaults | length) == 4
        and (.decisions.parallel_skeletal_enablement | startswith("reject_noop"))
        and (.decisions.dynamic_data_pool
             | startswith("do_not_raise_without_live_pool-pressure evidence"))
        and .decisions.candidate_added == false
        and .decisions.promotion == "none"
    ' "$SKELETAL_HOT_PATH_AUDIT" >/dev/null; then
    print -u2 "The Unreal skeletal hot-path audit is incomplete."
    exit 1
fi

readonly UNIFORM_COMMAND_PIPELINE_AUDIT="$PROJECT_DIR/artifacts/unreal-uniform-command-pipeline-audit-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "unreal_uniform_command_pipeline_static_audit"
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and (.observations | length) == 6
        and ([.observations[]
              | select((.cvar == "r.DeferUniformExpressionCaching"
                        or .cvar == "r.UniformExpressionCacheAsyncUpdates"
                        or .cvar == "r.AsyncCacheMaterialUniformExpressions"
                        or .cvar == "r.RenderCommandPipe.NiagaraDynamicData"
                        or .cvar == "r.Vulkan.AllowUniformUpload")
                       and .compiled_value_u32 == 1)] | length) == 5
        and ([.observations[]
              | select(.cvar == "r.RenderCommandPipeMode"
                       and .compiled_value_u32 == 2)] | length) == 1
        and .runtime_cross_checks.rhi_thread_effective == true
        and .runtime_cross_checks.source_artifact
            == "artifacts/simpleperf-stage1-8-transport-audit-20260815.json"
        and .runtime_cross_checks.uniform_buffer_pooling_effective_u32 == 1
        and .runtime_cross_checks.uniform_buffer_pooling_transition == "1 -> 1"
        and (.qualified_unknowns | length) == 1
        and .qualified_unknowns[0].cvar == "r.UniformBufferPooling"
        and (.decisions.uniform_expression_enablement | startswith("reject_noop"))
        and (.decisions.render_command_pipe_enablement | startswith("reject_noop"))
        and (.decisions.rhi_command_list_candidate | startswith("retain_priority_2"))
        and .decisions.candidate_added == false
        and .decisions.promotion == "none"
    ' "$UNIFORM_COMMAND_PIPELINE_AUDIT" >/dev/null; then
    print -u2 "The Unreal uniform/command-pipeline audit is incomplete."
    exit 1
fi

readonly UNIFORM_BUFFER_POOLING_RUNTIME_AUDIT="$PROJECT_DIR/artifacts/unreal-uniform-buffer-pooling-runtime-audit-20260815.json"
readonly UNIFORM_BUFFER_POOLING_QUERY_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.uniform-buffer-pooling-query.ini"
if ! jq -e '
        .schema_version == 1
        and .kind == "unreal_uniform_buffer_pooling_runtime_audit"
        and .client.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and .methodology.profile_sha256 == "fa81b21d5da493a455e78c18889bb53bfa99bdd09cf72d17ee64cb7bb95bdb08"
        and .methodology.explicit_cvar_count == 1
        and .runtime_observation.cvar == "r.UniformBufferPooling"
        and .runtime_observation.requested_value_u32 == 1
        and .runtime_observation.effective_value_before_profile_u32 == 1
        and .runtime_observation.effective_value_after_profile_u32 == 1
        and .runtime_observation.startup_transition == "1 -> 1"
        and .runtime_observation.crash_buffer_lines == 0
        and (.excluded_diagnostics | length) == 2
        and .rollback_attestation.adb_devices == 0
        and .rollback_attestation.emulator_processes == 0
        and .rollback_attestation.avd_lock_present == false
        and .rollback_attestation.config_transport == "pipe"
        and .rollback_attestation.generated_transport == "pipe"
        and (.decision.general_pooling | startswith("already_effective"))
        and (.decision.opengl_pool_candidate | startswith("retain_priority_1"))
        and .decision.candidate_added == false
        and .decision.promotion == "none"
    ' "$UNIFORM_BUFFER_POOLING_RUNTIME_AUDIT" >/dev/null \
        || [[ "$(shasum -a 256 "$UNIFORM_BUFFER_POOLING_QUERY_PROFILE" | awk '{ print $1 }')" \
            != "$(jq -r '.methodology.profile_sha256' "$UNIFORM_BUFFER_POOLING_RUNTIME_AUDIT")" ]] \
        || [[ "$(grep -c '^CVars=' "$UNIFORM_BUFFER_POOLING_QUERY_PROFILE")" != "1" ]] \
        || ! grep -Fxq 'CVars=r.UniformBufferPooling=1' "$UNIFORM_BUFFER_POOLING_QUERY_PROFILE" \
        || ! grep -Fq 'r.UniformBufferPooling' "$PROJECT_DIR/scripts/build-unreal-cvar-query-overlay.command" \
        || ! grep -Fq 'OpenGL.UBOPoolSize' "$PROJECT_DIR/scripts/build-unreal-cvar-query-overlay.command" \
        || ! grep -Fq 'OpenGL.UBODirectWrite' "$PROJECT_DIR/scripts/build-unreal-cvar-query-overlay.command" \
        || ! grep -Fq 'DumpCVars' "$PROJECT_DIR/scripts/build-unreal-cvar-query-overlay.command"; then
    print -u2 "The Unreal uniform-buffer-pooling runtime audit is incomplete."
    exit 1
fi

readonly ANIMATION_BUDGET_POLICY_AUDIT="$PROJECT_DIR/artifacts/unreal-animation-budget-policy-audit-20260815.json"
if ! jq -e '
        .schema_version == 1
        and .kind == "unreal_animation_budget_policy_static_audit"
        and .source.binary_sha256 == "4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822"
        and (.compiled_policy | length) == 21
        and ([.compiled_policy[].cvar] | length == (unique | length))
        and ([.compiled_policy[].storage_vma] | length == (unique | length))
        and ([.compiled_policy[]
              | select(.cvar == "a.Budget.BudgetMs"
                       and .value == 1 and .unit == "ms")] | length) == 1
        and ([.compiled_policy[]
              | select(.cvar == "a.Budget.MaxTickRate" and .value == 10)]
             | length) == 1
        and ([.compiled_policy[]
              | select(.cvar == "a.Budget.MaxInterpolatedComponents"
                       and .value == 16)] | length) == 1
        and ([.compiled_policy[]
              | select(.cvar == "a.Budget.MaxTickedOffsreen" and .value == 4)]
             | length) == 1
        and ([.compiled_policy[]
              | select(.cvar == "a.Budget.AutoCalculatedSignificanceMaxDistance"
                       and .value == 30000 and .embedded_help_default == 300)]
             | length) == 1
        and .startup_policy.allocator_enabled == 1
        and .startup_policy.compiled_budget_ms == 1
        and .startup_policy.low_view_scalability_budget_ms == 1.5
        and .startup_policy.later_saved_settings_budget_ms == 1.85
        and .startup_policy.candidate_budget_ms == 1
        and .startup_policy.candidate_profile_sha256 == "5691ec40a9a96b3ee0c238e9db2d70bb3e769ba30fad6f085ee0346adf934fc3"
        and .startup_policy.candidate_isolated_delta_count == 1
        and .startup_policy.candidate_startup_attested == true
        and .startup_policy.lower_priority_override_was_blocked == true
        and .decisions.candidate_ranking == "retain_budget_1ms_as_priority_3"
        and .decisions.promotion == "none"
    ' "$ANIMATION_BUDGET_POLICY_AUDIT" >/dev/null; then
    print -u2 "The Unreal animation-budget policy audit is incomplete."
    exit 1
fi

xcrun clang++ \
    -std=c++17 \
    -Wall \
    -Wextra \
    -Werror \
    -fsyntax-only \
    "$PROJECT_DIR/artifacts/angle-egl-probe.cpp"

if ! grep -Fq 'functional_es32_geometry_pipeline' \
        "$PROJECT_DIR/artifacts/angle-egl-probe.cpp" \
        || ! grep -Fq 'functional_es32_tessellation_pipeline' \
            "$PROJECT_DIR/artifacts/angle-egl-probe.cpp" \
        || ! grep -Fq 'exposeNonConformantExtensionsAndVersions' \
            "$PROJECT_DIR/scripts/run-host-angle-capability-probe.command" \
        || ! grep -Fq 'ANDROID_EMU_gles_max_version_3_2' \
            "$PROJECT_DIR/artifacts/gfxstream-gles32-host-capability-prototype.patch" \
        || ! grep -Fq 'kGles32Aliases' \
            "$PROJECT_DIR/artifacts/gfxstream-gles32-guest-proc-alias-prototype.patch" \
        || ! grep -Fq '{"glTexBuffer", (void*)_egl_glTexBufferEXT}' \
            "$PROJECT_DIR/artifacts/gfxstream-gles32-guest-proc-alias-prototype.patch" \
        || ! grep -Fq 'dynamic_alias_resolution_required' \
            "$PROJECT_DIR/scripts/audit-native-gles-coverage.command" \
        || ! grep -Fq 'runtime.LockOSThread()' \
            "$PROJECT_DIR/artifacts/android-egl-capability-probe/main.go" \
        || ! grep -Fq 'runtime.KeepAlive(highAttrs)' \
            "$PROJECT_DIR/artifacts/android-egl-capability-probe/main.go" \
        || ! grep -Fq 'hwui_renderer: $hwui_renderer' \
            "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        || ! grep -Fq 'display_density: $display_density' \
            "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        || ! grep -Fq 'ro.boot.mactician.graphics_profile' \
            "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        || ! grep -Fq "grep -Fqx 'Status: ok'" \
            "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        || ! grep -Fq 'write_rejected_summary "non_rendering_round_$round"' \
            "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        || ! grep -Fq 'existing evidence will not be overwritten' \
            "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        || ! grep -Fq 'androidboot.mactician.graphics_profile=$GRAPHICS_PROFILE' \
            "$PROJECT_DIR/run-tft-root-affinity.command"; then
    print -u2 "The native GLES capability experiment artifacts are incomplete."
    exit 1
fi
if [[ "$(grep -c '^proc ' \
        "$PROJECT_DIR/artifacts/android-egl-capability-probe/native-clean-boot-output.txt")" != "59" ]] \
        || [[ "$(grep -c '^proc .* false$' \
            "$PROJECT_DIR/artifacts/android-egl-capability-probe/native-clean-boot-output.txt")" != "3" ]]; then
    print -u2 "The recorded native guest proc-address matrix is incomplete."
    exit 1
fi

# The transport summarizer must retain short valid runs, reject empty and
# explicitly failed runs without dividing by zero, and keep display/renderer
# configurations separate.
if "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
        attestation-required 1 \
        >"$LIFECYCLE_ROOT/missing-profile-attestation.out" 2>&1 \
        || ! grep -Fq 'TFT_UI_TRANSPORT_EXPECTED_GRAPHICS_PROFILE is required' \
            "$LIFECYCLE_ROOT/missing-profile-attestation.out"; then
    print -u2 "The Android UI transport probe accepted an unattested graphics profile."
    exit 1
fi
if TFT_UI_TRANSPORT_EXPECTED_GRAPHICS_PROFILE=osft \
        TFT_UI_TRANSPORT_EXPECTED_ANGLE_ENABLED='unsafe feature' \
        "$PROJECT_DIR/scripts/run-android-ui-transport-probe.command" \
            invalid-angle-attestation 1 \
            >"$LIFECYCLE_ROOT/invalid-angle-attestation.out" 2>&1 \
        || ! grep -Fq 'Expected ANGLE features must be a feature or a colon-separated list.' \
            "$LIFECYCLE_ROOT/invalid-angle-attestation.out"; then
    print -u2 "The Android UI transport probe accepted an unsafe ANGLE feature attestation."
    exit 1
fi
readonly TRANSPORT_FIXTURE_ROOT="$LIFECYCLE_ROOT/android-ui-transport"
mkdir -p "$TRANSPORT_FIXTURE_ROOT/rejected" \
    "$TRANSPORT_FIXTURE_ROOT/empty" \
    "$TRANSPORT_FIXTURE_ROOT/short-osft" \
    "$TRANSPORT_FIXTURE_ROOT/short-stable" \
    "$TRANSPORT_FIXTURE_ROOT/short-skiagl" \
    "$TRANSPORT_FIXTURE_ROOT/short-density"
jq -n '{schema_version: 5, label: "edge-rejected-A", graphics_profile: "osft",
    display: "2560x1440", display_density: 320,
    transport: "virtio-gpu-asg", hwui_renderer: "skiavk",
    rejected_reason: "fixture_failure",
    swipe_pairs: 15,
    minimum_frames_per_round: 120,
    rounds: [range(1; 5) | {round: ., elapsed_ns: 6000000000,
      total_frames: 120, janky_frames: 0, p95_ms: 0, p99_ms: 0}]}' \
    > "$TRANSPORT_FIXTURE_ROOT/rejected/summary.json"
jq -n '{schema_version: 5, label: "edge-rejected-Z", graphics_profile: "osft",
    display: "2560x1440", display_density: 320,
    transport: "virtio-gpu-asg", hwui_renderer: "skiavk",
    swipe_pairs: 15, minimum_frames_per_round: 120, rounds: []}' \
    > "$TRANSPORT_FIXTURE_ROOT/empty/summary.json"
jq -n '{schema_version: 5, label: "edge-short-B", graphics_profile: "osft",
    display: "2560x1440", display_density: 320,
    transport: "virtio-gpu-asg", hwui_renderer: "skiavk",
    swipe_pairs: 15,
    minimum_frames_per_round: 120,
    rounds: [
      {round: 1, elapsed_ns: 6000000000, total_frames: 120,
       janky_frames: 1, p95_ms: 10, p99_ms: 12},
      {round: 2, elapsed_ns: 6200000000, total_frames: 121,
       janky_frames: 2, p95_ms: 11, p99_ms: 13},
      {round: 3, elapsed_ns: 6400000000, total_frames: 122,
       janky_frames: 3, p95_ms: 12, p99_ms: 14}]}' \
    > "$TRANSPORT_FIXTURE_ROOT/short-osft/summary.json"
jq -n '{schema_version: 5, label: "edge-short-C", graphics_profile: "stable",
    display: "2560x1440", display_density: 320,
    transport: "virtio-gpu-asg", hwui_renderer: "skiavk",
    swipe_pairs: 15, minimum_frames_per_round: 120,
    rounds: [
      {round: 1, elapsed_ns: 7000000000, total_frames: 120,
       janky_frames: 0, p95_ms: 9, p99_ms: 11}]}' \
    > "$TRANSPORT_FIXTURE_ROOT/short-stable/summary.json"
jq -n '{schema_version: 5, label: "edge-short-D", graphics_profile: "osft",
    display: "2560x1440", display_density: 320,
    transport: "virtio-gpu-asg", hwui_renderer: "skiagl",
    swipe_pairs: 15, minimum_frames_per_round: 120,
    rounds: [
      {round: 1, elapsed_ns: 7100000000, total_frames: 120,
       janky_frames: 4, p95_ms: 13, p99_ms: 15}]}' \
    > "$TRANSPORT_FIXTURE_ROOT/short-skiagl/summary.json"
jq -n '{schema_version: 5, label: "edge-short-E", graphics_profile: "osft",
    display: "2560x1440", display_density: 416,
    transport: "virtio-gpu-asg", hwui_renderer: "skiavk",
    swipe_pairs: 15, minimum_frames_per_round: 120,
    rounds: [
      {round: 1, elapsed_ns: 7200000000, total_frames: 120,
       janky_frames: 5, p95_ms: 14, p99_ms: 16}]}' \
    > "$TRANSPORT_FIXTURE_ROOT/short-density/summary.json"
TFT_UI_TRANSPORT_ROOT="$TRANSPORT_FIXTURE_ROOT" \
    "$PROJECT_DIR/scripts/summarize-android-ui-transport.command" \
    '^edge-(rejected|short)-[A-Z]$' \
    > "$TRANSPORT_FIXTURE_ROOT/result.json"
if ! jq -e '
    length == 5
    and .[0].group == "edge-rejected"
    and .[0].graphics_profile == "osft"
    and .[0].display_density == 320
    and .[0].hwui_renderer == "skiavk"
    and .[0].valid_runs == 0
    and .[0].rejected_runs == 2
    and .[0].warm_rounds == 0
    and .[0].warm_mean_elapsed_ms == null
    and .[0].warm_total_janky_frames == null
    and .[1].group == "edge-short"
    and .[1].graphics_profile == "osft"
    and .[1].display == "2560x1440"
    and .[1].display_density == 320
    and .[1].transport == "virtio-gpu-asg"
    and .[1].hwui_renderer == "skiagl"
    and .[1].valid_runs == 1
    and .[1].rejected_runs == 0
    and .[1].warm_rounds == 1
    and .[1].warm_mean_elapsed_ms == 7100
    and .[1].warm_max_p95_ms == 13
    and .[1].warm_max_p99_ms == 15
    and .[1].warm_total_janky_frames == 4
    and .[2].group == "edge-short"
    and .[2].graphics_profile == "osft"
    and .[2].display_density == 320
    and .[2].hwui_renderer == "skiavk"
    and .[2].valid_runs == 1
    and .[2].rejected_runs == 0
    and .[2].warm_rounds == 3
    and .[2].warm_mean_elapsed_ms == 6200
    and .[2].warm_median_elapsed_ms == 6200
    and .[2].warm_max_p95_ms == 12
    and .[2].warm_max_p99_ms == 14
    and .[2].warm_total_janky_frames == 6
    and .[3].group == "edge-short"
    and .[3].graphics_profile == "osft"
    and .[3].display_density == 416
    and .[3].hwui_renderer == "skiavk"
    and .[3].valid_runs == 1
    and .[3].warm_rounds == 1
    and .[3].warm_mean_elapsed_ms == 7200
    and .[3].warm_max_p95_ms == 14
    and .[3].warm_max_p99_ms == 16
    and .[4].group == "edge-short"
    and .[4].graphics_profile == "stable"
    and .[4].display_density == 320
    and .[4].hwui_renderer == "skiavk"
    and .[4].valid_runs == 1
    and .[4].warm_rounds == 1
    and .[4].warm_mean_elapsed_ms == 7000
    and .[4].warm_max_p95_ms == 9
    and .[4].warm_max_p99_ms == 11
' "$TRANSPORT_FIXTURE_ROOT/result.json" >/dev/null; then
    print -u2 "Android UI transport summary edge cases regressed."
    cat "$TRANSPORT_FIXTURE_ROOT/result.json" >&2
    exit 1
fi

if ! grep -Fq -- '--allow-adhoc' "$PROJECT_DIR/scripts/publish-mactician-update.command" \
        || ! grep -Fq 'Signature=adhoc' "$PROJECT_DIR/scripts/publish-mactician-update.command" \
        || ! grep -Fq 'hdiutil verify' "$PROJECT_DIR/scripts/publish-mactician-update.command"; then
    print -u2 "Ad-hoc publication safeguards are incomplete."
    exit 1
fi

if ! grep -Fq 'RELEASE_FILES=("$RELEASE_ARCHIVE" "$RELEASE_NOTES")' \
        "$PROJECT_DIR/scripts/publish-mactician-update.command" \
        || ! grep -Fq 'Mactician"$BUILD"-*.delta(.N)' \
            "$PROJECT_DIR/scripts/publish-mactician-update.command"; then
    print -u2 "Mactician publisher must upload only the current release artifacts."
    exit 1
fi

if ! grep -Fq 'or .gles_stress_succeeded == true' \
        "$PROJECT_DIR/scripts/run-performance-campaign.command" \
        || ! grep -Fq 'or .gles_draw_succeeded == true' \
            "$PROJECT_DIR/scripts/run-performance-campaign.command"; then
    print -u2 "Focused performance campaigns do not accept synthetic GLES evidence."
    exit 1
fi

if ! grep -Fq 'field__input--animate' \
        "$LAUNCHER_DIR/Sources/RiotLoginAnimationRepairService.swift" \
        || ! grep -Fq 'animation: none !important' \
        "$LAUNCHER_DIR/Sources/RiotLoginAnimationRepairService.swift" \
        || ! grep -Fq 'remainingAnimations == 0' \
        "$LAUNCHER_DIR/Sources/RiotLoginAnimationRepairService.swift" \
        || rg -n 'shell input (tap|keyevent)|KEYCODE_TAB|becomeFirstResponder' \
        "$LAUNCHER_DIR/Sources/RiotLoginAnimationRepairService.swift"; then
    print -u2 "Scoped Riot login animation repair is incomplete or uses synthetic focus."
    exit 1
fi

# A user-requested STOP sends TERM while the runtime child is still alive.
# Reproduce that lifecycle with caffeinate as a harmless long-running child and
# verify that it produces a normal stopped event, not a Repair error.
mkdir -p "$LIFECYCLE_ROOT/runtime/scripts"
ln -s /usr/bin/caffeinate "$LIFECYCLE_ROOT/runtime/scripts/run-asg-experiment.command"
env \
    TFT_RUNTIME_PROJECT="$LIFECYCLE_ROOT/runtime" \
    TFT_LAUNCH_LOG="$LIFECYCLE_ROOT/runtime.log" \
    TFT_ADB=/usr/bin/false \
    TFT_AVD_HOME="$LIFECYCLE_ROOT/avd" \
    TFT_AVD_NAME=Tft \
    TFT_SERIAL=emulator-5582 \
    TFT_DISPLAY_SIZE=1920x1080 \
    TFT_DISPLAY_DENSITY=320 \
    TFT_GAME_LANGUAGE=en-US \
    TFT_PACKAGE=com.riotgames.league.teamfighttactics \
    TFT_CPU_CORES=6 \
    TFT_MEMORY_MB=6144 \
    TFT_UI_SCALE=1.0 \
    TFT_PERFORMANCE_MODE=0 \
    "$LAUNCHER_DIR/Resources/launcher-runtime.command" \
    >"$LIFECYCLE_ROOT/events.jsonl" &
readonly LIFECYCLE_PID=$!
typeset lifecycle_ready=0
for lifecycle_attempt in {1..100}; do
    if grep -q '"event":"booting"' "$LIFECYCLE_ROOT/events.jsonl" 2>/dev/null; then
        lifecycle_ready=1
        break
    fi
    if ! kill -0 "$LIFECYCLE_PID" >/dev/null 2>&1; then
        break
    fi
    sleep 0.05
done
if (( lifecycle_ready == 0 )); then
    print -u2 "Launcher runtime did not reach the booting state."
    cat "$LIFECYCLE_ROOT/events.jsonl" >&2 2>/dev/null || true
    exit 1
fi
kill -TERM "$LIFECYCLE_PID"
if wait "$LIFECYCLE_PID"; then
    readonly LIFECYCLE_STATUS=0
else
    readonly LIFECYCLE_STATUS=$?
fi
if (( LIFECYCLE_STATUS != 0 )) \
        || ! grep -q '"event":"stopped"' "$LIFECYCLE_ROOT/events.jsonl" \
        || grep -q '"event":"error"' "$LIFECYCLE_ROOT/events.jsonl"; then
    print -u2 "Launcher runtime STOP was not classified as a normal shutdown."
    cat "$LIFECYCLE_ROOT/events.jsonl" >&2
    exit 1
fi

# After TFT has started, three consecutive missing package-PID checks represent
# a real game close. Verify that the runtime emits game_stopped once and keeps
# the Android session alive until an explicit stop request.
readonly GAME_EXIT_ADB="$LIFECYCLE_ROOT/fake-adb.command"
readonly GAME_EXIT_STATE="$LIFECYCLE_ROOT/fake-adb-state"
cat >"$GAME_EXIT_ADB" <<'FAKE_ADB_EOF'
#!/bin/zsh
set -eu
if [[ "$*" == *" get-state" ]]; then
    exit 0
fi
if [[ "$*" == *" getprop sys.boot_completed" ]]; then
    print 1
    exit 0
fi
if [[ "$*" == *" cmd locale set-app-locales"* ]]; then
    exit 0
fi
if [[ "$*" == *" pidof com.riotgames.league.teamfighttactics" ]]; then
    typeset -i count=0
    [[ -f "$TFT_FAKE_ADB_STATE" ]] && count="$(<"$TFT_FAKE_ADB_STATE")"
    (( count += 1 ))
    print "$count" >"$TFT_FAKE_ADB_STATE"
    (( count <= 2 )) && print 4242
    exit 0
fi
exit 0
FAKE_ADB_EOF
chmod 755 "$GAME_EXIT_ADB"
env \
    TFT_RUNTIME_PROJECT="$LIFECYCLE_ROOT/runtime" \
    TFT_LAUNCH_LOG="$LIFECYCLE_ROOT/game-exit-runtime.log" \
    TFT_ADB="$GAME_EXIT_ADB" \
    TFT_FAKE_ADB_STATE="$GAME_EXIT_STATE" \
    TFT_AVD_HOME="$LIFECYCLE_ROOT/avd" \
    TFT_AVD_NAME=Tft \
    TFT_SERIAL=emulator-5582 \
    TFT_DISPLAY_SIZE=1920x1080 \
    TFT_DISPLAY_DENSITY=320 \
    TFT_GAME_LANGUAGE=en-US \
    TFT_PACKAGE=com.riotgames.league.teamfighttacticsvn \
    TFT_FALLBACK_PACKAGE=com.riotgames.league.teamfighttactics \
    TFT_CPU_CORES=6 \
    TFT_MEMORY_MB=6144 \
    TFT_UI_SCALE=1.0 \
    TFT_PERFORMANCE_MODE=0 \
    "$LAUNCHER_DIR/Resources/launcher-runtime.command" \
    >"$LIFECYCLE_ROOT/game-exit-events.jsonl" &
readonly GAME_EXIT_PID=$!
typeset game_exit_detected=0
for game_exit_attempt in {1..200}; do
    if grep -q '"event":"game_stopped"' \
            "$LIFECYCLE_ROOT/game-exit-events.jsonl" 2>/dev/null; then
        game_exit_detected=1
        break
    fi
    if ! kill -0 "$GAME_EXIT_PID" >/dev/null 2>&1; then
        break
    fi
    sleep 0.05
done
typeset game_exit_runtime_alive=0
if (( game_exit_detected == 1 )) && kill -0 "$GAME_EXIT_PID" >/dev/null 2>&1; then
    game_exit_runtime_alive=1
fi
kill -TERM "$GAME_EXIT_PID" >/dev/null 2>&1 || true
wait "$GAME_EXIT_PID" || true
if (( game_exit_detected == 0 )) \
        || (( game_exit_runtime_alive == 0 )) \
        || [[ "$(grep -c '"event":"game_stopped"' "$LIFECYCLE_ROOT/game-exit-events.jsonl")" != 1 ]] \
        || grep -q '"event":"error"' "$LIFECYCLE_ROOT/game-exit-events.jsonl"; then
    print -u2 "Launcher runtime did not preserve Android after TFT closed."
    cat "$LIFECYCLE_ROOT/game-exit-events.jsonl" >&2
    exit 1
fi

mkdir -p "$LAUNCHER_DIR/.build/module-cache"
xcrun swiftc \
    -target "$TEST_TARGET" \
    -module-cache-path "$LAUNCHER_DIR/.build/module-cache" \
    "$LAUNCHER_DIR/Sources/CoreModels.swift" \
    "$LAUNCHER_DIR/Sources/HostedGameUpdate.swift" \
    "$LAUNCHER_DIR/Sources/LauncherPresentation.swift" \
    "$LAUNCHER_DIR/Sources/LauncherTelemetryService.swift" \
    "$LAUNCHER_DIR/Sources/LauncherPaths.swift" \
    "$LAUNCHER_DIR/Sources/SystemServices.swift" \
    "$LAUNCHER_DIR/Sources/EmulatorBrandingPatch.swift" \
    "$LAUNCHER_DIR/Sources/EmulatorAudioRecoveryService.swift" \
    "$LAUNCHER_DIR/Sources/FPSOverlayService.swift" \
    "$LAUNCHER_DIR/Sources/InputBridgeService.swift" \
    "$LAUNCHER_DIR/Sources/InstallerService.swift" \
    "$LAUNCHER_DIR/Sources/RuntimeController.swift" \
    "$LAUNCHER_DIR/Sources/NativeIPadRuntime.swift" \
    "$LAUNCHER_DIR/Tests/LauncherTests.swift" \
    -o "$TEST_BINARY"

"$TEST_BINARY" \
    "$LAUNCHER_DIR/Resources/release-manifest.json" \
    "$LAUNCHER_DIR"

typeset -a ALL_SOURCES
ALL_SOURCES=("$LAUNCHER_DIR"/Sources/*.swift)
xcrun swiftc \
    -typecheck \
    -parse-as-library \
    -target arm64-apple-macosx12.0 \
    -module-cache-path "$LAUNCHER_DIR/.build/module-cache" \
    -F "$SPARKLE_ROOT" \
    "${ALL_SOURCES[@]}"

print "Mactician typecheck: OK"
