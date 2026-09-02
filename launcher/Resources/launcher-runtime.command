#!/bin/zsh
set -uo pipefail
unsetopt BG_NICE

readonly REQUIRED_ENV=(
    TFT_RUNTIME_PROJECT TFT_LAUNCH_LOG TFT_ADB TFT_AVD_HOME TFT_AVD_NAME
    TFT_SERIAL TFT_DISPLAY_SIZE TFT_DISPLAY_DENSITY TFT_GAME_LANGUAGE TFT_PACKAGE
    TFT_CPU_CORES TFT_MEMORY_MB TFT_UI_SCALE TFT_PERFORMANCE_MODE
)
for required_name in "${REQUIRED_ENV[@]}"; do
    if [[ -z "${(P)required_name:-}" ]]; then
        print -r -- '{"event":"error","message":"Runtime environment is incomplete","code":2}'
        exit 2
    fi
done

case "$TFT_PACKAGE" in
    com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn) ;;
    *)
        print -r -- '{"event":"error","message":"Unsupported TFT package","code":2}'
        exit 2
        ;;
esac
if [[ -n "${TFT_FALLBACK_PACKAGE:-}" ]]; then
    case "$TFT_FALLBACK_PACKAGE" in
        com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn) ;;
        *)
            print -r -- '{"event":"error","message":"Unsupported fallback TFT package","code":2}'
            exit 2
            ;;
    esac
fi

case "$TFT_GAME_LANGUAGE" in
    en-US|ru-RU|de-DE|fr-FR|es-ES|es-MX|pt-BR|it-IT|pl-PL|cs-CZ|hu-HU|ro-RO|el-GR|tr-TR|ar-AE|ja-JP|ko-KR|zh-CN|zh-SG|zh-TW|vi-VN|th-TH|id-ID)
        ;;
    *)
        print -r -- '{"event":"error","message":"Unsupported game language","code":2}'
        exit 2
        ;;
esac

emit() {
    print -r -- "$1"
}

typeset child_pid=""
typeset stop_requested=0
stop_child() {
    stop_requested=1
    if [[ -n "$child_pid" ]] && kill -0 "$child_pid" >/dev/null 2>&1; then
        kill -TERM "$child_pid" >/dev/null 2>&1 || true
    fi
}
trap stop_child INT TERM HUP

mkdir -p "${TFT_LAUNCH_LOG:h}"
emit '{"event":"booting","message":"Starting Android…"}'

"$TFT_RUNTIME_PROJECT/scripts/run-asg-experiment.command" >>"$TFT_LAUNCH_LOG" 2>&1 &
child_pid=$!

running_game_package() {
    typeset package_name
    typeset package_pid
    for package_name in "$TFT_PACKAGE" "${TFT_FALLBACK_PACKAGE:-}"; do
        [[ -n "$package_name" ]] || continue
        package_pid="$("$TFT_ADB" -s "$TFT_SERIAL" shell pidof "$package_name" 2>/dev/null | tr -d '\r')"
        if [[ -n "$package_pid" ]]; then
            print -r -- "$package_name"
            return 0
        fi
    done
    return 1
}

typeset emulator_pid=""
typeset emitted_pid=0
typeset emitted_ready=0
typeset emitted_device_ready=0
typeset game_started_once=0
typeset locale_applied=0
typeset missing_game_checks=0
while kill -0 "$child_pid" >/dev/null 2>&1; do
    if (( emitted_pid == 0 )); then
        emulator_pid="$(pgrep -f 'qemu-system-aarch64.*-port 5582' 2>/dev/null | head -n 1 || true)"
        if [[ -z "$emulator_pid" ]]; then
            emulator_pid="$(pgrep -f 'emulator.*-port 5582' 2>/dev/null | head -n 1 || true)"
        fi
        if [[ "$emulator_pid" == <-> ]]; then
            emit "{\"event\":\"emulator_started\",\"pid\":$emulator_pid,\"serial\":\"$TFT_SERIAL\"}"
            emitted_pid=1
        fi
    fi
    if (( locale_applied == 0 )) \
            && "$TFT_ADB" -s "$TFT_SERIAL" get-state >/dev/null 2>&1 \
            && [[ "$("$TFT_ADB" -s "$TFT_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
        typeset locale_package
        for locale_package in "$TFT_PACKAGE" "${TFT_FALLBACK_PACKAGE:-}"; do
            [[ -n "$locale_package" ]] || continue
            "$TFT_ADB" -s "$TFT_SERIAL" shell cmd locale set-app-locales \
                "$locale_package" "$TFT_GAME_LANGUAGE" \
                >>"$TFT_LAUNCH_LOG" 2>&1 || true
        done
        locale_applied=1
    fi
    typeset current_game_package=""
    current_game_package="$(running_game_package || true)"
    if (( locale_applied == 1 && emitted_device_ready == 0 && emitted_ready == 0 )) \
            && [[ -z "$current_game_package" ]]; then
        emit "{\"event\":\"device_ready\",\"message\":\"Android is ready\",\"serial\":\"$TFT_SERIAL\"}"
        emitted_device_ready=1
    fi
    if (( emitted_ready == 0 )) \
            && "$TFT_ADB" -s "$TFT_SERIAL" get-state >/dev/null 2>&1 \
            && [[ -n "$current_game_package" ]]; then
        emit "{\"event\":\"ready\",\"message\":\"TFT is open\",\"serial\":\"$TFT_SERIAL\",\"package\":\"$current_game_package\"}"
        emitted_ready=1
        emitted_device_ready=1
        game_started_once=1
    fi
    if (( emitted_ready == 1 )); then
        if [[ -n "$current_game_package" ]]; then
            missing_game_checks=0
        else
            (( missing_game_checks += 1 ))
            if (( missing_game_checks >= 3 )); then
                emit "{\"event\":\"game_stopped\",\"message\":\"TFT closed\",\"serial\":\"$TFT_SERIAL\"}"
                emitted_ready=0
                missing_game_checks=0
            fi
        fi
    fi
    sleep 1
done

wait "$child_pid"
readonly child_status=$?
typeset normal_stop=0
if (( stop_requested == 1 || game_started_once == 1 )); then
    normal_stop=1
fi
if (( child_status == 42 && stop_requested == 0 )); then
    emit '{"event":"error","message":"The TFT version changed. The old OpenGL overlay will not be applied. Prepare a new verified private launcher build.","code":42}'
elif (( child_status != 0 && normal_stop == 0 )); then
    emit "{\"event\":\"error\",\"message\":\"Could not launch TFT. Open the log or repair the installation.\",\"code\":$child_status}"
fi
emit "{\"event\":\"stopped\",\"code\":$child_status}"
if (( normal_stop == 1 )); then
    exit 0
fi
exit "$child_status"
