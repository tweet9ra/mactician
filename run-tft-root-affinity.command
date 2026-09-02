#!/bin/zsh
set -euo pipefail

unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
SDK_ROOT="$(tft_resolve_android_sdk_root)"
readonly SDK_ROOT
EMULATOR="$(tft_resolve_emulator)"
readonly EMULATOR
ADB="$(tft_resolve_adb)"
readonly ADB
readonly AVD_HOME="${TFT_ROOT_AVD_HOME:-$(tft_resolve_avd_home)}"
readonly AVD_NAME="${TFT_AVD_NAME:-TftRootAffinity}"
readonly AVD_LOCK_FILE="$AVD_HOME/$AVD_NAME.avd/.mactician-avd.lock"
readonly INHERITED_AVD_LOCK_OWNER="${TFT_AVD_LOCK_OWNER_PID:-}"
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly EMULATOR_PORT="${TFT_EMULATOR_PORT:-${SERIAL#emulator-}}"
readonly BOOT_TIMEOUT_SECONDS="${TFT_BOOT_TIMEOUT_SECONDS:-120}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly ACTIVITY="com.epicgames.unreal.SplashActivity"
readonly ANGLE_BASE_FEATURES="exposeNonConformantExtensionsAndVersions:exposeES32ForTesting"
readonly ANGLE_EXTRA_FEATURES="${TFT_ANGLE_EXTRA_FEATURES:-}"
readonly ANGLE_DISABLED_FEATURES="${TFT_ANGLE_DISABLED_FEATURES:-}"
readonly BATCHED_DESCRIPTORS="${TFT_VULKAN_BATCHED_DESCRIPTORS:-0}"
readonly MVK_QUEUE_MODE="${TFT_MVK_QUEUE_MODE:-default}"
readonly MACOS_GAME_MODE="${TFT_MACOS_GAME_MODE:-0}"
readonly VIRTIO_GPU_NATIVE_SYNC="${TFT_VIRTIO_GPU_NATIVE_SYNC:-0}"
readonly VIRTIO_GPU_NEXT="${TFT_VIRTIO_GPU_NEXT:-0}"
readonly GL_DRAW_FLUSH_INTERVAL="${TFT_GL_DRAW_FLUSH_INTERVAL:-}"
readonly HWUI_RENDERER="${TFT_HWUI_RENDERER:-skiagl}"
readonly GRAPHICS_PROFILE="${TFT_GRAPHICS_PROFILE:-stable}"
readonly DISPLAY_SIZE="${TFT_DISPLAY_SIZE:-1600x900}"
readonly DISPLAY_DENSITY="${TFT_DISPLAY_DENSITY:-260}"
readonly UI_SCALE="${TFT_UI_SCALE:-1.0}"
readonly PERFORMANCE_MODE="${TFT_PERFORMANCE_MODE:-0}"
readonly CPU_CORES="${TFT_CPU_CORES:-7}"
readonly MEMORY_MB="${TFT_MEMORY_MB:-6144}"
readonly GAME_LANGUAGE="${TFT_GAME_LANGUAGE:-en-US}"
readonly AUDIO_ENABLED="${TFT_AUDIO_ENABLED:-1}"
readonly RENDERER="${TFT_RENDERER:-angle}"
readonly HOST_GPU="${TFT_HOST_GPU:-host}"
readonly GUEST_GL_DRIVER="${TFT_GUEST_GL_DRIVER:-angle}"
readonly GUEST_SUBMIT_THREAD="${TFT_GUEST_SUBMIT_THREAD:-default}"
readonly PACKAGED_EMULATOR_APP="$PROJECT_DIR/Mactician Game Host.app"
readonly GAME_MODE_APP="$PROJECT_DIR/tools/Mactician Game Host.app"
readonly INPUT_BRIDGE_ENABLED="${TFT_INPUT_BRIDGE_ENABLED:-1}"
readonly INPUT_DIAGNOSTICS="${TFT_INPUT_DIAGNOSTICS:-0}"
readonly INPUT_DIAGNOSTICS_LOG="${TFT_INPUT_DIAGNOSTICS_LOG:-}"
readonly INPUT_BRIDGE_SOURCE="$PROJECT_DIR/tools/tft-input-bridge.swift"
readonly INPUT_BRIDGE_BINARY="$PROJECT_DIR/runtime/tft-input-bridge"
readonly INPUT_SHOP_POINT="${TFT_INPUT_SHOP_POINT:-0.96,0.93}"
readonly INPUT_REROLL_POINT="${TFT_INPUT_REROLL_POINT:-0.955,0.79}"
readonly INPUT_XP_POINT="${TFT_INPUT_XP_POINT:-0.032,0.925}"
readonly INPUT_TRAITS_POINT="${TFT_INPUT_TRAITS_POINT:-0.029,0.04}"
readonly INPUT_ITEMS_POINT="${TFT_INPUT_ITEMS_POINT:-0.059,0.04}"
readonly INPUT_DAMAGE_POINT="${TFT_INPUT_DAMAGE_POINT:-0.947,0.04}"
readonly INPUT_PLAYERS_POINT="${TFT_INPUT_PLAYERS_POINT:-0.975,0.04}"
readonly DIRECT_VULKAN_DIR="$PROJECT_DIR/artifacts/tft-18.1-direct-vulkan"
readonly DIRECT_VULKAN_APK="$DIRECT_VULKAN_DIR/base-direct-vulkan.apk"
readonly DIRECT_VULKAN_PROFILE="$DIRECT_VULKAN_DIR/Android_Codex.DeviceProfiles.ini"
readonly DIRECT_VULKAN_REMOTE_DIR="/data/local/tmp/tft-direct-vulkan"
readonly ANGLE_OPENGL_DIR="$PROJECT_DIR/artifacts/tft-18.1-angle-opengl"
readonly ANGLE_OPENGL_APK="${TFT_ANGLE_OPENGL_APK:-$ANGLE_OPENGL_DIR/base-angle-opengl.apk}"
readonly ANGLE_OPENGL_PROFILE_OVERRIDE="${TFT_ANGLE_OPENGL_PROFILE:-}"
readonly ANGLE_OPENGL_PROFILE="${ANGLE_OPENGL_PROFILE_OVERRIDE:-$ANGLE_OPENGL_DIR/Android_Codex.DeviceProfiles.ini}"
readonly ANGLE_OPENGL_PROFILE_SHA256="${TFT_ANGLE_OPENGL_PROFILE_SHA256:-}"
readonly ANGLE_OPENGL_REMOTE_DIR="/data/local/tmp/tft-angle-opengl"
readonly ORIGINAL_BASE_SHA256="${TFT_ORIGINAL_BASE_APK_SHA256:-2f4996a620623d0b958383bfe58bdec78fb70cca095099ca2474f3d08c62ff18}"
readonly DIRECT_VULKAN_SHA256="3cabacef5ba122467d2eea8fb2874f41530a8d0c1b8cda3f391a58134b936236"
readonly ANGLE_OPENGL_SHA256="${TFT_ANGLE_OPENGL_APK_SHA256:-f3a257750e1875298a1203c40e9bb98aaf9521b4466f75a53d16fd2d6ea63865}"
readonly UNREAL_LIB_OVERLAY="${TFT_UNREAL_LIB_OVERLAY:-}"
readonly UNREAL_LIB_OVERLAY_SHA256="${TFT_UNREAL_LIB_OVERLAY_SHA256:-}"
readonly UNREAL_LIB_ORIGINAL_SHA256="dd59c46a07d6f7394add255a1f11ede357489a7f1b6f2f925bd87c878c16ec08"
readonly UNREAL_LIB_REMOTE_DIR="/data/local/tmp/tft-unreal-lib-overlay"
readonly WRAP_PROPERTY="wrap.$PACKAGE"

OVERLAY_LABEL=""
OVERLAY_APK=""
OVERLAY_PROFILE=""
OVERLAY_REMOTE_DIR=""
OVERLAY_SHA256=""
OVERLAY_BASE_PATH=""
OVERLAY_MOUNTED=0
PROFILE_DESTINATION=""
PROFILE_BACKUP=""
PROFILE_PRESENT_MARKER=""
PROFILE_ABSENT_MARKER=""
PROFILE_ORIGINAL_OWNER=""
PROFILE_ORIGINAL_MODE=""
PROFILE_WAS_PRESENT=0
PROFILE_MANAGED=0
PROFILE_MOUNTED=0
UNREAL_LIB_TARGET=""
UNREAL_LIB_MOUNTED=0
ANGLE_SETTINGS_MANAGED=0
ANGLE_ORIGINAL_PACKAGES=""
ANGLE_ORIGINAL_VALUES=""
ANGLE_ORIGINAL_FEATURES=""
GUEST_WRAP_MANAGED=0
GUEST_WRAP_ORIGINAL=""
HWUI_RENDERER_MANAGED=0
HWUI_RENDERER_ORIGINAL=""
AVD_LOCK_HELD=0

release_avd_lock() {
    if [[ "$AVD_LOCK_HELD" != "1" ]]; then
        return
    fi
    typeset lock_owner=""
    if [[ -f "$AVD_LOCK_FILE" ]]; then
        IFS= read -r lock_owner < "$AVD_LOCK_FILE" || true
    fi
    if [[ "$lock_owner" == "$$" ]]; then
        rm -f "$AVD_LOCK_FILE"
    else
        print "Warning: the AVD lock changed owners; the foreign lock was not removed."
    fi
    AVD_LOCK_HELD=0
}

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 to 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export TFT_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ADB_MDNS_AUTO_CONNECT=""
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

readonly OSFT_QEMU_PATTERN='Application Support/OSFT/sdk/emulator/.*/qemu-system-aarch64.*-avd PlayDroid'
if pgrep -f "$OSFT_QEMU_PATTERN" >/dev/null 2>&1; then
    print "OSFT PlayDroid is already running. Close it before TFT fast-quality: two VMs cause severe CPU/GPU contention."
    exit 1
fi

if [[ "$MACOS_GAME_MODE" != "0" && "$MACOS_GAME_MODE" != "1" ]]; then
    print "TFT_MACOS_GAME_MODE must be either 0 or 1."
    exit 2
fi
if [[ "$HWUI_RENDERER" != "skiagl" && "$HWUI_RENDERER" != "skiavk" ]]; then
    print "TFT_HWUI_RENDERER must be either skiagl or skiavk."
    exit 2
fi
if [[ "$INPUT_BRIDGE_ENABLED" != "0" && "$INPUT_BRIDGE_ENABLED" != "1" ]]; then
    print "TFT_INPUT_BRIDGE_ENABLED must be either 0 or 1."
    exit 2
fi
if [[ "$INPUT_DIAGNOSTICS" != "0" && "$INPUT_DIAGNOSTICS" != "1" ]]; then
    print "TFT_INPUT_DIAGNOSTICS must be either 0 or 1."
    exit 2
fi
for input_point_name input_point_value in \
        TFT_INPUT_SHOP_POINT "$INPUT_SHOP_POINT" \
        TFT_INPUT_REROLL_POINT "$INPUT_REROLL_POINT" \
        TFT_INPUT_XP_POINT "$INPUT_XP_POINT" \
        TFT_INPUT_TRAITS_POINT "$INPUT_TRAITS_POINT" \
        TFT_INPUT_ITEMS_POINT "$INPUT_ITEMS_POINT" \
        TFT_INPUT_DAMAGE_POINT "$INPUT_DAMAGE_POINT" \
        TFT_INPUT_PLAYERS_POINT "$INPUT_PLAYERS_POINT"; do
    if [[ ! "$input_point_value" =~ '^(0([.][0-9]+)?|1([.]0+)?),(0([.][0-9]+)?|1([.]0+)?)$' ]]; then
        print "$input_point_name must be a pair of relative X,Y coordinates from 0 to 1."
        exit 2
    fi
done
if [[ "$VIRTIO_GPU_NATIVE_SYNC" != "0" && "$VIRTIO_GPU_NATIVE_SYNC" != "1" ]]; then
    print "TFT_VIRTIO_GPU_NATIVE_SYNC must be either 0 or 1."
    exit 2
fi
if [[ "$VIRTIO_GPU_NEXT" != "0" && "$VIRTIO_GPU_NEXT" != "1" ]]; then
    print "TFT_VIRTIO_GPU_NEXT must be either 0 or 1."
    exit 2
fi
if [[ -n "$GL_DRAW_FLUSH_INTERVAL" ]]; then
    if [[ "$GL_DRAW_FLUSH_INTERVAL" != <-> ]] \
            || (( GL_DRAW_FLUSH_INTERVAL < 100 || GL_DRAW_FLUSH_INTERVAL > 10000 )); then
        print "TFT_GL_DRAW_FLUSH_INTERVAL must be an integer from 100 to 10000 microseconds."
        exit 2
    fi
fi

if [[ "$EMULATOR_PORT" != <-> ]] || (( EMULATOR_PORT < 5554 || EMULATOR_PORT > 5682 )) \
        || [[ "$SERIAL" != "emulator-$EMULATOR_PORT" ]]; then
    print "TFT_SERIAL/TFT_EMULATOR_PORT must be a matching emulator-PORT and PORT pair."
    exit 2
fi
if [[ "$BOOT_TIMEOUT_SECONDS" != <-> ]] || (( BOOT_TIMEOUT_SECONDS < 30 || BOOT_TIMEOUT_SECONDS > 600 )); then
    print "TFT_BOOT_TIMEOUT_SECONDS must be an integer from 30 to 600 seconds."
    exit 2
fi

if [[ ! "$CPU_CORES" =~ '^[0-9]+$' ]] || (( CPU_CORES < 1 || CPU_CORES > 16 )); then
    print "TFT_CPU_CORES must be an integer from 1 to 16."
    exit 2
fi
if [[ ! "$MEMORY_MB" =~ '^[0-9]+$' ]] || (( MEMORY_MB < 2048 || MEMORY_MB > 32768 )); then
    print "TFT_MEMORY_MB must be an integer from 2048 to 32768."
    exit 2
fi
case "$GAME_LANGUAGE" in
    en-US|ru-RU|de-DE|fr-FR|es-ES|es-MX|pt-BR|it-IT|pl-PL|cs-CZ|hu-HU|ro-RO|el-GR|tr-TR|ar-AE|ja-JP|ko-KR|zh-CN|zh-SG|zh-TW|vi-VN|th-TH|id-ID)
        ;;
    *)
        print "TFT_GAME_LANGUAGE must be a supported locale."
        exit 2
        ;;
esac
if [[ ! "$DISPLAY_SIZE" =~ '^[0-9]+x[0-9]+$' ]]; then
    print "TFT_DISPLAY_SIZE must use WIDTHxHEIGHT format, for example 1600x900."
    exit 2
fi
if [[ ! "$DISPLAY_DENSITY" =~ '^[0-9]+$' ]] || (( DISPLAY_DENSITY < 120 || DISPLAY_DENSITY > 640 )); then
    print "TFT_DISPLAY_DENSITY must be an integer from 120 to 640."
    exit 2
fi
if [[ "$UI_SCALE" != "1.0" && "$UI_SCALE" != "1.25" && "$UI_SCALE" != "1.5" \
        && "$UI_SCALE" != "1.75" && "$UI_SCALE" != "2.0" ]]; then
    print "TFT_UI_SCALE must be one of 1.0, 1.25, 1.5, 1.75, or 2.0."
    exit 2
fi
if [[ "$PERFORMANCE_MODE" != "0" && "$PERFORMANCE_MODE" != "1" ]]; then
    print "TFT_PERFORMANCE_MODE must be either 0 or 1."
    exit 2
fi
if [[ -n "$ANGLE_EXTRA_FEATURES" && ! "$ANGLE_EXTRA_FEATURES" =~ '^([A-Za-z0-9_]+[*]?)(:[A-Za-z0-9_]+[*]?)*$' ]]; then
    print "TFT_ANGLE_EXTRA_FEATURES must be an ANGLE feature or a colon-separated list."
    exit 2
fi
if [[ -n "$ANGLE_DISABLED_FEATURES" \
        && ! "$ANGLE_DISABLED_FEATURES" =~ '^([A-Za-z0-9_]+[*]?)(:[A-Za-z0-9_]+[*]?)*$' ]]; then
    print "TFT_ANGLE_DISABLED_FEATURES must be a feature or a colon-separated list."
    exit 2
fi
if [[ "$GUEST_GL_DRIVER" != "angle" && "$GUEST_GL_DRIVER" != "native" ]]; then
    print "TFT_GUEST_GL_DRIVER must be either angle or native."
    exit 2
fi
if [[ "$GUEST_SUBMIT_THREAD" != "default" \
        && "$GUEST_SUBMIT_THREAD" != "on-demand" \
        && "$GUEST_SUBMIT_THREAD" != "0" \
        && "$GUEST_SUBMIT_THREAD" != "1" ]]; then
    print "TFT_GUEST_SUBMIT_THREAD must be one of default, on-demand, 0, or 1."
    exit 2
fi
if [[ "$GUEST_SUBMIT_THREAD" != "default" && "$GUEST_GL_DRIVER" != "angle" ]]; then
    print "The guest Vulkan submit thread is supported only with TFT_GUEST_GL_DRIVER=angle."
    exit 2
fi
if [[ "$HOST_GPU" != "host" && "$HOST_GPU" != "swangle" ]]; then
    print "TFT_HOST_GPU must be either host or swangle."
    exit 2
fi
if [[ "$HOST_GPU" == "swangle" && "$GUEST_GL_DRIVER" != "native" ]]; then
    print "The isolated swangle control is supported only with TFT_GUEST_GL_DRIVER=native."
    exit 2
fi

ANGLE_FEATURES="$ANGLE_BASE_FEATURES"
if [[ -n "$ANGLE_EXTRA_FEATURES" ]]; then
    ANGLE_FEATURES+=":$ANGLE_EXTRA_FEATURES"
fi
readonly ANGLE_FEATURES

if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
    if [[ "$RENDERER" != "angle-opengl" ]]; then
        print "TFT_GUEST_GL_DRIVER=native is supported only with TFT_RENDERER=angle-opengl."
        exit 2
    fi
    if [[ "$GRAPHICS_PROFILE" != "osft" && "$GRAPHICS_PROFILE" != "osft-no-batching" ]]; then
        print "Native gfxstream GLES is incompatible with VulkanNativeSwapchain; use the osft or osft-no-batching profile."
        exit 2
    fi
    export ANGLE_FEATURE_OVERRIDES_ENABLED="$ANGLE_FEATURES"
    if [[ -n "$ANGLE_DISABLED_FEATURES" ]]; then
        export ANGLE_FEATURE_OVERRIDES_DISABLED="$ANGLE_DISABLED_FEATURES"
    else
        unset ANGLE_FEATURE_OVERRIDES_DISABLED
    fi
fi

case "$RENDERER" in
    angle)
        ;;
    direct-vulkan)
        OVERLAY_LABEL="direct-Vulkan"
        OVERLAY_APK="$DIRECT_VULKAN_APK"
        OVERLAY_PROFILE="$DIRECT_VULKAN_PROFILE"
        OVERLAY_REMOTE_DIR="$DIRECT_VULKAN_REMOTE_DIR"
        OVERLAY_SHA256="$DIRECT_VULKAN_SHA256"
        ;;
    angle-opengl)
        OVERLAY_LABEL="ANGLE/OpenGL"
        OVERLAY_APK="$ANGLE_OPENGL_APK"
        OVERLAY_PROFILE="$ANGLE_OPENGL_PROFILE"
        OVERLAY_REMOTE_DIR="$ANGLE_OPENGL_REMOTE_DIR"
        OVERLAY_SHA256="$ANGLE_OPENGL_SHA256"
        ;;
    *)
        print "TFT_RENDERER must be one of angle, angle-opengl, or direct-vulkan."
        exit 2
        ;;
esac

if [[ -n "$OVERLAY_APK" ]]; then
    if [[ ! -f "$OVERLAY_APK" || ! -f "$OVERLAY_PROFILE" ]]; then
        print "$OVERLAY_LABEL APK/profile artifacts were not found."
        exit 1
    fi
    if [[ "$(shasum -a 256 "$OVERLAY_APK" | awk '{ print $1 }')" != "$OVERLAY_SHA256" ]]; then
        print "The $OVERLAY_LABEL APK SHA-256 does not match the verified value."
        exit 1
    fi
fi
if [[ -n "$ANGLE_OPENGL_PROFILE_OVERRIDE" ]]; then
    if [[ "$RENDERER" != "angle-opengl" ]] \
            || [[ ! "$ANGLE_OPENGL_PROFILE_SHA256" =~ '^[0-9a-f]{64}$' ]]; then
        print "The custom ANGLE/OpenGL profile requires TFT_RENDERER=angle-opengl and a verified SHA-256."
        exit 2
    fi
    if [[ "$(shasum -a 256 "$ANGLE_OPENGL_PROFILE" | awk '{ print $1 }')" != "$ANGLE_OPENGL_PROFILE_SHA256" ]]; then
        print "The custom ANGLE/OpenGL profile SHA-256 does not match the expected value."
        exit 1
    fi
fi
if [[ -n "$UNREAL_LIB_OVERLAY" ]]; then
    if [[ "$GUEST_GL_DRIVER" != "native" ]]; then
        print "TFT_UNREAL_LIB_OVERLAY is allowed only for the isolated native-GLES test."
        exit 2
    fi
    if [[ ! -f "$UNREAL_LIB_OVERLAY" ]] \
            || [[ ! "$UNREAL_LIB_OVERLAY_SHA256" =~ '^[0-9a-f]{64}$' ]]; then
        print "TFT_UNREAL_LIB_OVERLAY/SHA256 do not reference a verified artifact."
        exit 2
    fi
    if [[ "$(shasum -a 256 "$UNREAL_LIB_OVERLAY" | awk '{ print $1 }')" != "$UNREAL_LIB_OVERLAY_SHA256" ]]; then
        print "The temporary libUnreal.so overlay SHA-256 does not match the expected value."
        exit 1
    fi
fi

if [[ "$MACOS_GAME_MODE" == "1" && ( "$BATCHED_DESCRIPTORS" != "0" || "$MVK_QUEUE_MODE" != "default" ) ]]; then
    print "Game Mode, descriptor batching, and the MoltenVK queue mode must be tested one at a time."
    exit 2
fi

case "$MVK_QUEUE_MODE" in
    default)
        unset MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS
        ;;
    async)
        export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0
        ;;
    sync)
        export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1
        ;;
    *)
        print "TFT_MVK_QUEUE_MODE must be one of default, async, or sync."
        exit 2
        ;;
esac

typeset -a EXTRA_EMULATOR_FLAGS
EXTRA_EMULATOR_FLAGS=()
case "$GRAPHICS_PROFILE" in
    stable)
        EXTRA_EMULATOR_FLAGS=(-feature VulkanNativeSwapchain)
        ;;
    osft)
        if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
            EXTRA_EMULATOR_FLAGS=(
                -feature 'GLESDynamicVersion,Vulkan,-GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts'
                -append-userspace-opt androidboot.opengles.version=196610
            )
        else
            EXTRA_EMULATOR_FLAGS=(
                -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts'
                -append-userspace-opt androidboot.opengles.version=196610
            )
        fi
        ;;
    osft-no-batching)
        if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
            EXTRA_EMULATOR_FLAGS=(
                -feature 'GLESDynamicVersion,Vulkan,-GuestAngle,-GLPipeChecksum,-VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts'
                -append-userspace-opt androidboot.opengles.version=196610
            )
        else
            EXTRA_EMULATOR_FLAGS=(
                -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,-VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts'
                -append-userspace-opt androidboot.opengles.version=196610
            )
        fi
        ;;
    osft-no-async-compose)
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,-AsyncComposeSupport,VirtioGpuFenceContexts'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    osft-no-queue-submit-with-commands)
        # Diagnostic reproduction only. Real TFT cold boots abort before ADB
        # while decoding VK_STRUCTURE_TYPE_APPLICATION_INFO; this profile is
        # deliberately absent from the performance-candidate manifest.
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts,-VulkanQueueSubmitWithCommands'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    osft-no-native-swapchain)
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts,-VulkanNativeSwapchain'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    osft-no-fence-contexts)
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,-VirtioGpuFenceContexts'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    osft-no-virtual-queue)
        # Diagnostic reproduction only. Emulator 37.1.11 reports that this
        # guest feature override is ignored, so it cannot form a valid A/B.
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts,-VulkanVirtualQueue'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    osft-native-swapchain)
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts,VulkanNativeSwapchain'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    osft-low-latency)
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,-AsyncComposeSupport,VirtioGpuFenceContexts,VulkanNativeSwapchain'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    turbo)
        EXTRA_EMULATOR_FLAGS=(
            -feature 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts,VulkanNativeSwapchain'
            -append-userspace-opt androidboot.opengles.version=196610
        )
        ;;
    *)
        print "TFT_GRAPHICS_PROFILE must be one of stable, osft, osft-no-batching, osft-no-async-compose, osft-no-queue-submit-with-commands, osft-no-native-swapchain, osft-no-fence-contexts, osft-no-virtual-queue, osft-native-swapchain, osft-low-latency, or turbo."
        exit 2
        ;;
esac

if [[ "$BATCHED_DESCRIPTORS" == "1" && "$GRAPHICS_PROFILE" == "stable" ]]; then
    EXTRA_EMULATOR_FLAGS+=(-feature VulkanBatchedDescriptorSetUpdate)
fi
if [[ "$VIRTIO_GPU_NATIVE_SYNC" == "1" ]]; then
    EXTRA_EMULATOR_FLAGS+=(-feature VirtioGpuNativeSync)
fi
if [[ "$VIRTIO_GPU_NEXT" == "1" ]]; then
    EXTRA_EMULATOR_FLAGS+=(-feature VirtioGpuNext)
fi

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_AVD_HOME="$AVD_HOME"

if [[ ! -x "$EMULATOR" ]]; then
    print "Android Emulator was not found: $EMULATOR"
    exit 1
fi

if [[ "$INPUT_BRIDGE_ENABLED" == "1" ]]; then
    if [[ ! -f "$INPUT_BRIDGE_SOURCE" ]]; then
        print "The input bridge source was not found: $INPUT_BRIDGE_SOURCE"
        exit 1
    fi
    if [[ ! -x "$INPUT_BRIDGE_BINARY" || "$INPUT_BRIDGE_SOURCE" -nt "$INPUT_BRIDGE_BINARY" ]]; then
        readonly INPUT_BRIDGE_NEXT="$INPUT_BRIDGE_BINARY.next"
        mkdir -p "${INPUT_BRIDGE_BINARY:h}" "$PROJECT_DIR/runtime/swift-module-cache"
        /usr/bin/xcrun swiftc \
            -O \
            -module-cache-path "$PROJECT_DIR/runtime/swift-module-cache" \
            "$INPUT_BRIDGE_SOURCE" \
            -o "$INPUT_BRIDGE_NEXT"
        mv -f "$INPUT_BRIDGE_NEXT" "$INPUT_BRIDGE_BINARY"
    fi
fi

if [[ ! -f "$AVD_HOME/$AVD_NAME.ini" ]]; then
    print "The rootable AVD was not found: $AVD_HOME/$AVD_NAME.ini"
    exit 1
fi

EMULATOR_APP=""
if [[ -x "$PACKAGED_EMULATOR_APP/Contents/MacOS/MacticianGameHost" ]]; then
    EMULATOR_APP="$PACKAGED_EMULATOR_APP"
elif [[ "$MACOS_GAME_MODE" == "1" && -x "$GAME_MODE_APP/Contents/MacOS/MacticianGameHost" ]]; then
    EMULATOR_APP="$GAME_MODE_APP"
fi
readonly EMULATOR_APP

if [[ "$MACOS_GAME_MODE" == "1" && -z "$EMULATOR_APP" ]]; then
    print "The Game Mode app wrapper was not found: $GAME_MODE_APP"
    exit 1
fi

if [[ -n "$INHERITED_AVD_LOCK_OWNER" ]]; then
    typeset inherited_lock_pid=""
    if [[ -f "$AVD_LOCK_FILE" ]]; then
        IFS= read -r inherited_lock_pid < "$AVD_LOCK_FILE" || true
    fi
    if [[ "$INHERITED_AVD_LOCK_OWNER" != <-> \
            || "$INHERITED_AVD_LOCK_OWNER" != "$PPID" \
            || "$inherited_lock_pid" != "$INHERITED_AVD_LOCK_OWNER" ]] \
            || ! kill -0 "$INHERITED_AVD_LOCK_OWNER" >/dev/null 2>&1; then
        print "The inherited AVD lock does not belong to the parent launcher process."
        exit 1
    fi
else
    if ! /usr/bin/shlock -f "$AVD_LOCK_FILE" -p "$$"; then
        typeset active_lock_pid="unknown"
        if [[ -f "$AVD_LOCK_FILE" ]]; then
            IFS= read -r active_lock_pid < "$AVD_LOCK_FILE" || true
        fi
        print "Another TFT launcher already owns the AVD lock (PID $active_lock_pid)."
        exit 1
    fi
    AVD_LOCK_HELD=1
    trap release_avd_lock EXIT
fi

if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The rootable TFT AVD is already running on $SERIAL. Close it first."
    exit 1
fi
if [[ "$AUDIO_ENABLED" != "0" && "$AUDIO_ENABLED" != "1" ]]; then
    print "TFT_AUDIO_ENABLED must be 0 or 1."
    exit 2
fi

typeset -a EMULATOR_ARGS
EMULATOR_ARGS=(
    "@$AVD_NAME"
    -id "TFT-$AVD_NAME"
    -port "$EMULATOR_PORT"
    -gpu "$HOST_GPU"
    "${EXTRA_EMULATOR_FLAGS[@]}"
    -append-userspace-opt "androidboot.mactician.graphics_profile=$GRAPHICS_PROFILE"
    -skin "$DISPLAY_SIZE"
    -vsync-rate 60
    -dns-server 1.1.1.1,8.8.8.8
    -cores "$CPU_CORES"
    -memory "$MEMORY_MB"
    -no-snapshot
    -no-metrics
    -no-boot-anim
    -crash-report-mode disabled
)
typeset AUDIO_STATUS="enabled"
if [[ "$AUDIO_ENABLED" == "0" ]]; then
    EMULATOR_ARGS+=(-no-audio)
    AUDIO_STATUS="disabled"
fi
readonly AUDIO_STATUS
if [[ -n "$EMULATOR_APP" ]]; then
    typeset -a APP_ENV_ARGS
    APP_ENV_ARGS=(
        --env "TFT_EMULATOR=$EMULATOR"
        --env "TFT_ADB_SERVER_PORT=$ADB_SERVER_PORT"
        --env "ANDROID_ADB_SERVER_PORT=$ADB_SERVER_PORT"
        --env "ADB_MDNS_AUTO_CONNECT="
        --env "ANDROID_SDK_ROOT=$SDK_ROOT"
        --env "ANDROID_AVD_HOME=$AVD_HOME"
    )
    for environment_name in \
            ANGLE_FEATURE_OVERRIDES_ENABLED \
            ANGLE_FEATURE_OVERRIDES_DISABLED \
            MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS \
            MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION \
            MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE \
            MVK_CONFIG_LOG_LEVEL \
            MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT \
            MVK_CONFIG_PERFORMANCE_TRACKING \
            MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS \
            MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE \
            MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS \
            MVK_CONFIG_USE_MTLHEAP \
            MVK_CONFIG_FAST_MATH_ENABLED \
            MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS \
            MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE; do
        if [[ -n "${(P)environment_name:-}" ]]; then
            APP_ENV_ARGS+=(--env "$environment_name=${(P)environment_name}")
        fi
    done
    /usr/bin/open -n -W \
        "${APP_ENV_ARGS[@]}" \
        "$EMULATOR_APP" --args "${EMULATOR_ARGS[@]}" &
else
    "$EMULATOR" "${EMULATOR_ARGS[@]}" &
fi
readonly EMULATOR_PID=$!
WATCHER_PID=""
INPUT_BRIDGE_PID=""
UI_SCALE_TEMP_DIR=""

cleanup() {
    if [[ -n "$UI_SCALE_TEMP_DIR" && -d "$UI_SCALE_TEMP_DIR" ]]; then
        rm -rf "$UI_SCALE_TEMP_DIR"
        UI_SCALE_TEMP_DIR=""
    fi
    if [[ -n "$INPUT_BRIDGE_PID" ]] && kill -0 "$INPUT_BRIDGE_PID" >/dev/null 2>&1; then
        kill "$INPUT_BRIDGE_PID" >/dev/null 2>&1 || true
        wait "$INPUT_BRIDGE_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$WATCHER_PID" ]] && kill -0 "$WATCHER_PID" >/dev/null 2>&1; then
        kill "$WATCHER_PID" >/dev/null 2>&1 || true
        wait "$WATCHER_PID" >/dev/null 2>&1 || true
    fi
    if [[ ( "$OVERLAY_MOUNTED" == "1" || "$PROFILE_MANAGED" == "1" \
            || "$UNREAL_LIB_MOUNTED" == "1" ) ]] \
            && "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        "$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
        integer wait_attempt
        for (( wait_attempt = 1; wait_attempt <= 20; wait_attempt++ )); do
            if [[ -z "$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')" ]]; then
                break
            fi
            sleep 0.25
        done
        if [[ "$PROFILE_MANAGED" == "1" && -n "$PROFILE_DESTINATION" ]]; then
            if [[ "$PROFILE_MOUNTED" == "1" ]]; then
                if "$ADB" -s "$SERIAL" shell umount "$PROFILE_DESTINATION" >/dev/null 2>&1; then
                    PROFILE_MOUNTED=0
                    print "The persistent guest DeviceProfiles.ini mount was removed."
                else
                    print "Warning: the guest DeviceProfiles.ini mount was not removed; the transaction marker remains for cold-boot recovery."
                fi
            fi
            if [[ "$PROFILE_MOUNTED" == "0" ]]; then
                PROFILE_ROLLBACK_APPLIED=0
                if [[ "$PROFILE_WAS_PRESENT" == "1" && -n "$PROFILE_BACKUP" ]]; then
                    if "$ADB" -s "$SERIAL" shell cp "$PROFILE_BACKUP" "$PROFILE_DESTINATION" \
                            && "$ADB" -s "$SERIAL" shell chown "$PROFILE_ORIGINAL_OWNER" "$PROFILE_DESTINATION" \
                            && "$ADB" -s "$SERIAL" shell chmod "$PROFILE_ORIGINAL_MODE" "$PROFILE_DESTINATION"; then
                        PROFILE_ROLLBACK_APPLIED=1
                        print "The original guest DeviceProfiles.ini was restored; the journal will be cleared on the next cold boot."
                    else
                        print "Warning: guest DeviceProfiles.ini could not be restored before the AVD shut down."
                    fi
                else
                    if "$ADB" -s "$SERIAL" shell rm -f "$PROFILE_DESTINATION"; then
                        PROFILE_ROLLBACK_APPLIED=1
                        print "The temporary guest DeviceProfiles.ini was removed; the journal will be cleared on the next cold boot."
                    else
                        print "Warning: the guest profile marker remains for recovery on the next launch."
                    fi
                fi
                if [[ "$PROFILE_ROLLBACK_APPLIED" == "1" ]]; then
                    PROFILE_MANAGED=0
                fi
            fi
        fi
        if [[ "$OVERLAY_MOUNTED" == "1" && -n "$OVERLAY_BASE_PATH" ]]; then
            if "$ADB" -s "$SERIAL" shell umount "$OVERLAY_BASE_PATH" >/dev/null 2>&1; then
                OVERLAY_MOUNTED=0
            else
                print "Warning: the APK overlay is busy; shutting down the AVD will clear the mount."
            fi
        fi
        if [[ "$UNREAL_LIB_MOUNTED" == "1" && -n "$UNREAL_LIB_TARGET" ]]; then
            if "$ADB" -s "$SERIAL" shell umount "$UNREAL_LIB_TARGET" >/dev/null 2>&1; then
                UNREAL_LIB_MOUNTED=0
                print "The temporary libUnreal.so overlay was removed."
            else
                print "Warning: the libUnreal.so overlay is busy; shutting down the AVD will clear the mount."
            fi
        fi
    fi
    if [[ "$ANGLE_SETTINGS_MANAGED" == "1" ]] \
            && "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        typeset setting_name original_value
        for setting_name original_value in \
                angle_gl_driver_selection_pkgs "$ANGLE_ORIGINAL_PACKAGES" \
                angle_gl_driver_selection_values "$ANGLE_ORIGINAL_VALUES" \
                angle_egl_features "$ANGLE_ORIGINAL_FEATURES"; do
            if [[ "$original_value" == "null" ]]; then
                "$ADB" -s "$SERIAL" shell settings delete global "$setting_name" >/dev/null 2>&1 || true
            else
                "$ADB" -s "$SERIAL" shell settings put global "$setting_name" "$original_value" >/dev/null 2>&1 || true
            fi
        done
        ANGLE_SETTINGS_MANAGED=0
        print "The original Android graphics-driver selection was restored."
    fi
    if [[ "$GUEST_WRAP_MANAGED" == "1" ]] \
            && "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        if "$ADB" -s "$SERIAL" shell \
                "setprop '$WRAP_PROPERTY' '$GUEST_WRAP_ORIGINAL'" >/dev/null 2>&1; then
            typeset restored_guest_wrap
            restored_guest_wrap="$("$ADB" -s "$SERIAL" shell getprop "$WRAP_PROPERTY" 2>/dev/null | tr -d '\r')"
            if [[ "$restored_guest_wrap" == "$GUEST_WRAP_ORIGINAL" ]]; then
                GUEST_WRAP_MANAGED=0
                print "The original Android process wrapper was restored and verified."
            else
                print "Warning: the Android process wrapper does not match the original after rollback."
            fi
        else
            print "Warning: the Android process wrapper could not be restored."
        fi
    fi
    if [[ "$HWUI_RENDERER_MANAGED" == "1" ]] \
            && "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        if "$ADB" -s "$SERIAL" shell \
                "setprop debug.hwui.renderer '$HWUI_RENDERER_ORIGINAL'" >/dev/null 2>&1; then
            typeset restored_hwui_renderer
            restored_hwui_renderer="$(
                "$ADB" -s "$SERIAL" shell getprop debug.hwui.renderer 2>/dev/null \
                    | tr -d '\r'
            )"
            if [[ "$restored_hwui_renderer" == "$HWUI_RENDERER_ORIGINAL" ]]; then
                HWUI_RENDERER_MANAGED=0
                print "The original Android HWUI renderer was restored: ${HWUI_RENDERER_ORIGINAL:-unset}."
            else
                print "Warning: the Android HWUI renderer does not match the original after rollback."
            fi
        else
            print "Warning: the Android HWUI renderer could not be restored."
        fi
    fi
    if kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
        wait "$EMULATOR_PID" >/dev/null 2>&1 || true
    fi
    release_avd_lock
}
trap cleanup EXIT
trap 'exit 130' INT TERM

print "Waiting for the dedicated userdebug/rootable TFT AVD to boot..."
typeset -i adb_waited=0
until "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
    if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        print "The emulator exited before ADB connected."
        exit 0
    fi
    if (( adb_waited >= BOOT_TIMEOUT_SECONDS )); then
        print "ADB did not become available within ${BOOT_TIMEOUT_SECONDS} seconds."
        exit 1
    fi
    sleep 1
    (( adb_waited += 1 ))
done

typeset -i boot_waited=0
until [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        print "The emulator exited before Android finished booting."
        exit 0
    fi
    if (( boot_waited >= BOOT_TIMEOUT_SECONDS )); then
        print "Android did not finish booting within ${BOOT_TIMEOUT_SECONDS} seconds."
        exit 1
    fi
    sleep 1
    (( boot_waited += 1 ))
done

typeset -i root_attempt
for (( root_attempt = 1; root_attempt <= 10; root_attempt++ )); do
    "$ADB" -s "$SERIAL" root >/dev/null 2>&1 || true
    typeset -i root_waited=0
    until "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; do
        if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
            print "The emulator exited while adbd was restarting."
            exit 0
        fi
        if (( root_waited >= 10 )); then
            break
        fi
        sleep 1
        (( root_waited += 1 ))
    done
    if [[ "$("$ADB" -s "$SERIAL" shell id -u 2>/dev/null | tr -d '\r')" == "0" ]]; then
        break
    fi
    sleep 1
done

if [[ "$("$ADB" -s "$SERIAL" shell id -u 2>/dev/null | tr -d '\r')" != "0" ]]; then
    print "Official adbd root could not be enabled."
    exit 1
fi

if [[ -n "$GL_DRAW_FLUSH_INTERVAL" ]]; then
    readonly ACTIVE_DRAW_FLUSH_INTERVAL="$(
        "$ADB" -s "$SERIAL" shell getprop ro.boot.qemu.gltransport.drawFlushInterval 2>/dev/null \
            | tr -d '\r'
    )"
    if [[ "$ACTIVE_DRAW_FLUSH_INTERVAL" != "$GL_DRAW_FLUSH_INTERVAL" ]]; then
        print "The draw flush interval was not applied: expected $GL_DRAW_FLUSH_INTERVAL, active ${ACTIVE_DRAW_FLUSH_INTERVAL:-unknown}."
        exit 1
    fi
fi

"$ADB" -s "$SERIAL" shell wm size "$DISPLAY_SIZE"
"$ADB" -s "$SERIAL" shell wm density "$DISPLAY_DENSITY"

if [[ "$INPUT_BRIDGE_ENABLED" == "1" ]]; then
    readonly DISPLAY_WIDTH="${DISPLAY_SIZE%x*}"
    readonly DISPLAY_HEIGHT="${DISPLAY_SIZE#*x}"
    "$INPUT_BRIDGE_BINARY" \
        --target-pid "$EMULATOR_PID" \
        --target-bundle-id "dev.sergeinaumov.mactician.experiment-emulator" \
        --adb "$ADB" \
        --adb-port "$ADB_SERVER_PORT" \
        --serial "$SERIAL" \
        --display-width "$DISPLAY_WIDTH" \
        --display-height "$DISPLAY_HEIGHT" \
        --diagnostics "$INPUT_DIAGNOSTICS" \
        --diagnostics-log "$INPUT_DIAGNOSTICS_LOG" \
        --shop-point "$INPUT_SHOP_POINT" \
        --reroll-point "$INPUT_REROLL_POINT" \
        --xp-point "$INPUT_XP_POINT" \
        --traits-point "$INPUT_TRAITS_POINT" \
        --items-point "$INPUT_ITEMS_POINT" \
        --damage-point "$INPUT_DAMAGE_POINT" \
        --players-point "$INPUT_PLAYERS_POINT" &
    INPUT_BRIDGE_PID=$!
    sleep 0.2
    if ! kill -0 "$INPUT_BRIDGE_PID" >/dev/null 2>&1; then
        wait "$INPUT_BRIDGE_PID" || true
        print "The input bridge exited immediately after launch."
        exit 1
    fi
fi

if ! "$ADB" -s "$SERIAL" shell pm path "$PACKAGE" | grep -q '^package:'; then
    print "TFT is not installed in the rootable AVD. The launcher does not copy the APK or private data."
    exit 1
fi

readonly PROFILE_DIR="/data/user/0/$PACKAGE/files/UnrealGame/TFT/TFT/Saved/Config/Android"
PROFILE_DESTINATION="$PROFILE_DIR/DeviceProfiles.ini"
readonly DATA_OWNER="$(
    "$ADB" -s "$SERIAL" shell stat -c '%u:%g' "/data/user/0/$PACKAGE" \
        | tr -d '\r'
)"
if [[ -z "$DATA_OWNER" ]]; then
    print "The owner of TFT private data could not be determined."
    exit 1
fi

# Recover a profile transaction left by SIGKILL/host failure before applying a
# new overlay. This also makes a later stock-root launch self-healing.
typeset RECOVERY_REMOTE_DIR RECOVERY_BACKUP RECOVERY_PRESENT_MARKER RECOVERY_ABSENT_MARKER
for RECOVERY_REMOTE_DIR in "$DIRECT_VULKAN_REMOTE_DIR" "$ANGLE_OPENGL_REMOTE_DIR"; do
    RECOVERY_BACKUP="$RECOVERY_REMOTE_DIR/DeviceProfiles.ini.mactician-backup"
    RECOVERY_PRESENT_MARKER="$RECOVERY_REMOTE_DIR/DeviceProfiles.ini.mactician-present"
    RECOVERY_ABSENT_MARKER="$RECOVERY_REMOTE_DIR/DeviceProfiles.ini.mactician-absent"
    if "$ADB" -s "$SERIAL" shell test -f "$RECOVERY_PRESENT_MARKER"; then
        if ! "$ADB" -s "$SERIAL" shell test -f "$RECOVERY_BACKUP"; then
            print "The rollback guest profile is corrupted: $RECOVERY_BACKUP is missing"
            exit 1
        fi
        "$ADB" -s "$SERIAL" shell mkdir -p "$PROFILE_DIR"
        "$ADB" -s "$SERIAL" shell cp -p "$RECOVERY_BACKUP" "$PROFILE_DESTINATION"
        "$ADB" -s "$SERIAL" shell rm -f "$RECOVERY_BACKUP" "$RECOVERY_PRESENT_MARKER"
        print "Guest DeviceProfiles.ini was restored after an interrupted launch."
    elif "$ADB" -s "$SERIAL" shell test -f "$RECOVERY_ABSENT_MARKER"; then
        "$ADB" -s "$SERIAL" shell rm -f "$PROFILE_DESTINATION" "$RECOVERY_ABSENT_MARKER"
        print "The temporary guest DeviceProfiles.ini was removed after an interrupted launch."
    elif "$ADB" -s "$SERIAL" shell test -f "$RECOVERY_BACKUP"; then
        print "A guest profile backup without a transaction marker was found: $RECOVERY_BACKUP"
        exit 1
    fi
done

if [[ -n "$OVERLAY_APK" ]]; then
    OVERLAY_BASE_PATH="$(
        "$ADB" -s "$SERIAL" shell pm path "$PACKAGE" \
            | tr -d '\r' \
            | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p' \
            | head -n 1
    )"
    if [[ -z "$OVERLAY_BASE_PATH" ]]; then
        print "The installed TFT base.apk could not be located."
        exit 1
    fi

    readonly EXISTING_MOUNT_COUNT="$(
        "$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo \
            | tr -d '\r' \
            | awk -v target="$OVERLAY_BASE_PATH" '$5 == target { count++ } END { print count + 0 }'
    )"
    if [[ "$EXISTING_MOUNT_COUNT" != "0" ]]; then
        print "$OVERLAY_LABEL invariant violation: mounts=$EXISTING_MOUNT_COUNT were found before launch."
        print "Shut down the AVD; the launcher will not stack another APK overlay."
        exit 1
    fi

    readonly OVERLAY_TARGET_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$OVERLAY_BASE_PATH" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$OVERLAY_TARGET_CONTEXT" != "u:object_r:apk_data_file:s0" ]]; then
        print "Unexpected SELinux context for the installed base.apk: ${OVERLAY_TARGET_CONTEXT:-empty}."
        exit 1
    fi

    readonly INSTALLED_BASE_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$OVERLAY_BASE_PATH" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$INSTALLED_BASE_SHA256" != "$ORIGINAL_BASE_SHA256" ]]; then
        print "The installed base.apk does not match the signed TFT update manifest."
        print "Actual SHA-256: $INSTALLED_BASE_SHA256"
        exit 42
    fi

    "$ADB" -s "$SERIAL" shell mkdir -p "$OVERLAY_REMOTE_DIR"
    "$ADB" -s "$SERIAL" push "$OVERLAY_APK" "$OVERLAY_REMOTE_DIR/base.apk.next" >/dev/null
    "$ADB" -s "$SERIAL" shell chmod 644 "$OVERLAY_REMOTE_DIR/base.apk.next"
    "$ADB" -s "$SERIAL" shell chcon "$OVERLAY_TARGET_CONTEXT" "$OVERLAY_REMOTE_DIR/base.apk.next"
    "$ADB" -s "$SERIAL" shell mv "$OVERLAY_REMOTE_DIR/base.apk.next" "$OVERLAY_REMOTE_DIR/base.apk"

    readonly REMOTE_OVERLAY_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$OVERLAY_REMOTE_DIR/base.apk" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    readonly REMOTE_OVERLAY_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$OVERLAY_REMOTE_DIR/base.apk" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$REMOTE_OVERLAY_SHA256" != "$OVERLAY_SHA256" \
            || "$REMOTE_OVERLAY_CONTEXT" != "$OVERLAY_TARGET_CONTEXT" ]]; then
        print "The uploaded $OVERLAY_LABEL APK is corrupted: $REMOTE_OVERLAY_SHA256"
        exit 1
    fi

    "$ADB" -s "$SERIAL" shell mount -o bind "$OVERLAY_REMOTE_DIR/base.apk" "$OVERLAY_BASE_PATH"
    OVERLAY_MOUNTED=1

    readonly ACTIVE_BASE_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$OVERLAY_BASE_PATH" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    readonly ACTIVE_MOUNT_COUNT="$(
        "$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo \
            | tr -d '\r' \
            | awk -v target="$OVERLAY_BASE_PATH" '$5 == target { count++ } END { print count + 0 }'
    )"
    readonly ACTIVE_BASE_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$OVERLAY_BASE_PATH" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$ACTIVE_BASE_SHA256" != "$OVERLAY_SHA256" \
            || "$ACTIVE_MOUNT_COUNT" != "1" \
            || "$ACTIVE_BASE_CONTEXT" != "$OVERLAY_TARGET_CONTEXT" ]]; then
        print "A single verified $OVERLAY_LABEL overlay could not be mounted."
        exit 1
    fi

    readonly PROFILE_REMOTE="$OVERLAY_REMOTE_DIR/DeviceProfiles.ini"

    "$ADB" -s "$SERIAL" push "$OVERLAY_PROFILE" "$PROFILE_REMOTE" >/dev/null
    "$ADB" -s "$SERIAL" shell mkdir -p "$PROFILE_DIR"
    readonly PROFILE_TARGET_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$PROFILE_DIR" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ ! "$PROFILE_TARGET_CONTEXT" =~ '^u:object_r:[A-Za-z0-9_]+:s0(:c[0-9]+(,c[0-9]+)*)?$' ]]; then
        print "The guest profile SELinux context could not be determined safely: $PROFILE_TARGET_CONTEXT"
        exit 1
    fi
    "$ADB" -s "$SERIAL" shell chcon "$PROFILE_TARGET_CONTEXT" "$PROFILE_REMOTE"
    "$ADB" -s "$SERIAL" shell chown 0:0 "$PROFILE_REMOTE"
    "$ADB" -s "$SERIAL" shell chmod 444 "$PROFILE_REMOTE"
    readonly EXPECTED_PROFILE_SHA256="$(shasum -a 256 "$OVERLAY_PROFILE" | awk '{ print $1 }')"
    readonly REMOTE_PROFILE_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$PROFILE_REMOTE" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$REMOTE_PROFILE_SHA256" != "$EXPECTED_PROFILE_SHA256" ]]; then
        print "The uploaded guest DeviceProfiles.ini is corrupted: $REMOTE_PROFILE_SHA256"
        exit 1
    fi
    PROFILE_BACKUP="$OVERLAY_REMOTE_DIR/DeviceProfiles.ini.mactician-backup"
    PROFILE_PRESENT_MARKER="$OVERLAY_REMOTE_DIR/DeviceProfiles.ini.mactician-present"
    PROFILE_ABSENT_MARKER="$OVERLAY_REMOTE_DIR/DeviceProfiles.ini.mactician-absent"
    if "$ADB" -s "$SERIAL" shell test -f "$PROFILE_DESTINATION"; then
        PROFILE_WAS_PRESENT=1
        PROFILE_ORIGINAL_OWNER="$("$ADB" -s "$SERIAL" shell stat -c '%u:%g' "$PROFILE_DESTINATION" | tr -d '\r')"
        PROFILE_ORIGINAL_MODE="$("$ADB" -s "$SERIAL" shell stat -c '%a' "$PROFILE_DESTINATION" | tr -d '\r')"
        "$ADB" -s "$SERIAL" shell cp -p "$PROFILE_DESTINATION" "$PROFILE_BACKUP"
        "$ADB" -s "$SERIAL" shell touch "$PROFILE_PRESENT_MARKER"
    else
        PROFILE_WAS_PRESENT=0
        "$ADB" -s "$SERIAL" shell touch "$PROFILE_ABSENT_MARKER"
    fi
    PROFILE_MANAGED=1
    "$ADB" -s "$SERIAL" shell cp "$PROFILE_REMOTE" "$PROFILE_DESTINATION"
    "$ADB" -s "$SERIAL" shell chown "$DATA_OWNER" "$PROFILE_DESTINATION"
    "$ADB" -s "$SERIAL" shell chmod 600 "$PROFILE_DESTINATION"
    readonly EXISTING_PROFILE_MOUNT_COUNT="$(
        "$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo \
            | tr -d '\r' \
            | awk -v target="$PROFILE_DESTINATION" '$5 == target { count++ } END { print count + 0 }'
    )"
    if [[ "$EXISTING_PROFILE_MOUNT_COUNT" != "0" ]]; then
        print "Guest DeviceProfiles.ini invariant violation: mounts=$EXISTING_PROFILE_MOUNT_COUNT were found before the bind mount."
        exit 1
    fi
    "$ADB" -s "$SERIAL" shell mount -o bind "$PROFILE_REMOTE" "$PROFILE_DESTINATION"
    PROFILE_MOUNTED=1
    readonly ACTIVE_PROFILE_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$PROFILE_DESTINATION" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    readonly ACTIVE_PROFILE_MOUNT_COUNT="$(
        "$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo \
            | tr -d '\r' \
            | awk -v target="$PROFILE_DESTINATION" '$5 == target { count++ } END { print count + 0 }'
    )"
    readonly ACTIVE_PROFILE_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$PROFILE_DESTINATION" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$ACTIVE_PROFILE_SHA256" != "$EXPECTED_PROFILE_SHA256" \
            || "$ACTIVE_PROFILE_MOUNT_COUNT" != "1" \
            || "$ACTIVE_PROFILE_CONTEXT" != "$PROFILE_TARGET_CONTEXT" ]]; then
        print "A single guest DeviceProfiles.ini mount could not be established."
        exit 1
    fi
fi

# Unreal exposes ApplicationScale as the global multiplier applied after its
# resolution-dependent DPI rule. Stage it before every game start without
# changing the 3D framebuffer resolution or r.ScreenPercentage. TFT may later
# normalize Saved/Config/Android/Engine.ini, so the launcher preference remains
# the source of truth and is reapplied on every Play.
readonly ENGINE_CONFIG="$PROFILE_DIR/Engine.ini"
UI_SCALE_TEMP_DIR="$(mktemp -d /private/tmp/tft-ui-scale.XXXXXX)"
readonly ENGINE_CONFIG_CURRENT="$UI_SCALE_TEMP_DIR/Engine.ini.current"
readonly ENGINE_CONFIG_NEXT="$UI_SCALE_TEMP_DIR/Engine.ini.next"
"$ADB" -s "$SERIAL" shell mkdir -p "$PROFILE_DIR"
if "$ADB" -s "$SERIAL" shell test -f "$ENGINE_CONFIG"; then
    "$ADB" -s "$SERIAL" pull "$ENGINE_CONFIG" "$ENGINE_CONFIG_CURRENT" >/dev/null
else
    /usr/bin/touch "$ENGINE_CONFIG_CURRENT"
fi
/usr/bin/awk -v scale="$UI_SCALE" '
    BEGIN {
        section = "[/Script/Engine.UserInterfaceSettings]"
        found = 0
        in_section = 0
    }
    $0 == section {
        print
        print "ApplicationScale=" scale
        found = 1
        in_section = 1
        next
    }
    /^\[/ { in_section = 0 }
    in_section && /^[[:space:]]*ApplicationScale[[:space:]]*=/ { next }
    { print }
    END {
        if (!found) {
            print ""
            print section
            print "ApplicationScale=" scale
        }
    }
' "$ENGINE_CONFIG_CURRENT" > "$ENGINE_CONFIG_NEXT"
readonly ENGINE_CONFIG_CONTEXT="$(
    if "$ADB" -s "$SERIAL" shell test -f "$ENGINE_CONFIG"; then
        "$ADB" -s "$SERIAL" shell ls -Zd "$ENGINE_CONFIG"
    else
        "$ADB" -s "$SERIAL" shell ls -Zd "$PROFILE_DIR"
    fi | tr -d '\r' | awk '{ print $1 }'
)"
if [[ ! "$ENGINE_CONFIG_CONTEXT" =~ '^u:object_r:[A-Za-z0-9_]+:s0(:c[0-9]+(,c[0-9]+)*)?$' ]]; then
    print "The Engine.ini SELinux context could not be determined safely: $ENGINE_CONFIG_CONTEXT"
    exit 1
fi
readonly ENGINE_CONFIG_REMOTE_NEXT="$PROFILE_DIR/Engine.ini.ui-scale-next"
"$ADB" -s "$SERIAL" push "$ENGINE_CONFIG_NEXT" "$ENGINE_CONFIG_REMOTE_NEXT" >/dev/null
"$ADB" -s "$SERIAL" shell chown "$DATA_OWNER" "$ENGINE_CONFIG_REMOTE_NEXT"
"$ADB" -s "$SERIAL" shell chmod 600 "$ENGINE_CONFIG_REMOTE_NEXT"
"$ADB" -s "$SERIAL" shell chcon "$ENGINE_CONFIG_CONTEXT" "$ENGINE_CONFIG_REMOTE_NEXT"
"$ADB" -s "$SERIAL" shell mv "$ENGINE_CONFIG_REMOTE_NEXT" "$ENGINE_CONFIG"
readonly EXPECTED_ENGINE_CONFIG_SHA256="$(shasum -a 256 "$ENGINE_CONFIG_NEXT" | awk '{ print $1 }')"
readonly ACTIVE_ENGINE_CONFIG_SHA256="$(
    "$ADB" -s "$SERIAL" shell sha256sum "$ENGINE_CONFIG" \
        | tr -d '\r' \
        | awk '{ print $1 }'
)"
if [[ "$ACTIVE_ENGINE_CONFIG_SHA256" != "$EXPECTED_ENGINE_CONFIG_SHA256" ]]; then
    print "Engine.ini with the UI scale failed SHA-256 verification: ${ACTIVE_ENGINE_CONFIG_SHA256:-empty}."
    exit 1
fi

# Riot persists its built-in Performance Mode in GameUserSettings.ini. Keep it
# aligned with Mactician's graphics preset before TFT starts, without changing
# any of the other user-owned settings in the GraphicsSettings structure.
readonly GAME_USER_SETTINGS="$PROFILE_DIR/GameUserSettings.ini"
readonly GAME_USER_SETTINGS_CURRENT="$UI_SCALE_TEMP_DIR/GameUserSettings.ini.current"
readonly GAME_USER_SETTINGS_NEXT="$UI_SCALE_TEMP_DIR/GameUserSettings.ini.next"
if "$ADB" -s "$SERIAL" shell test -f "$GAME_USER_SETTINGS"; then
    "$ADB" -s "$SERIAL" pull "$GAME_USER_SETTINGS" "$GAME_USER_SETTINGS_CURRENT" >/dev/null
else
    /usr/bin/touch "$GAME_USER_SETTINGS_CURRENT"
fi
"$PROJECT_DIR/scripts/update-tft-performance-mode.command" \
    "$PERFORMANCE_MODE" "$GAME_USER_SETTINGS_CURRENT" > "$GAME_USER_SETTINGS_NEXT"
readonly GAME_USER_SETTINGS_CONTEXT="$(
    if "$ADB" -s "$SERIAL" shell test -f "$GAME_USER_SETTINGS"; then
        "$ADB" -s "$SERIAL" shell ls -Zd "$GAME_USER_SETTINGS"
    else
        "$ADB" -s "$SERIAL" shell ls -Zd "$PROFILE_DIR"
    fi | tr -d '\r' | awk '{ print $1 }'
)"
if [[ ! "$GAME_USER_SETTINGS_CONTEXT" =~ '^u:object_r:[A-Za-z0-9_]+:s0(:c[0-9]+(,c[0-9]+)*)?$' ]]; then
    print "The GameUserSettings.ini SELinux context could not be determined safely: $GAME_USER_SETTINGS_CONTEXT"
    exit 1
fi
readonly GAME_USER_SETTINGS_REMOTE_NEXT="$PROFILE_DIR/GameUserSettings.ini.performance-mode-next"
"$ADB" -s "$SERIAL" push "$GAME_USER_SETTINGS_NEXT" "$GAME_USER_SETTINGS_REMOTE_NEXT" >/dev/null
"$ADB" -s "$SERIAL" shell chown "$DATA_OWNER" "$GAME_USER_SETTINGS_REMOTE_NEXT"
"$ADB" -s "$SERIAL" shell chmod 600 "$GAME_USER_SETTINGS_REMOTE_NEXT"
"$ADB" -s "$SERIAL" shell chcon "$GAME_USER_SETTINGS_CONTEXT" "$GAME_USER_SETTINGS_REMOTE_NEXT"
"$ADB" -s "$SERIAL" shell mv "$GAME_USER_SETTINGS_REMOTE_NEXT" "$GAME_USER_SETTINGS"
readonly EXPECTED_GAME_USER_SETTINGS_SHA256="$(shasum -a 256 "$GAME_USER_SETTINGS_NEXT" | awk '{ print $1 }')"
readonly ACTIVE_GAME_USER_SETTINGS_SHA256="$(
    "$ADB" -s "$SERIAL" shell sha256sum "$GAME_USER_SETTINGS" \
        | tr -d '\r' \
        | awk '{ print $1 }'
)"
if [[ "$ACTIVE_GAME_USER_SETTINGS_SHA256" != "$EXPECTED_GAME_USER_SETTINGS_SHA256" ]]; then
    print "GameUserSettings.ini with Performance Mode failed SHA-256 verification: ${ACTIVE_GAME_USER_SETTINGS_SHA256:-empty}."
    exit 1
fi
rm -rf "$UI_SCALE_TEMP_DIR"
UI_SCALE_TEMP_DIR=""
print "Unreal UI scale is configured: ${UI_SCALE}x with a ${DISPLAY_SIZE} framebuffer."
if [[ "$PERFORMANCE_MODE" == "1" ]]; then
    print "Riot Performance Mode is enabled for Maximum FPS."
else
    print "Riot Performance Mode is disabled for the selected graphics preset."
fi

if [[ -n "$UNREAL_LIB_OVERLAY" ]]; then
    if [[ -z "$OVERLAY_BASE_PATH" ]]; then
        print "The temporary libUnreal.so overlay requires a verified base.apk target."
        exit 1
    fi
    UNREAL_LIB_TARGET="${OVERLAY_BASE_PATH%/base.apk}/lib/arm64/libUnreal.so"
    readonly INSTALLED_UNREAL_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$UNREAL_LIB_TARGET" 2>/dev/null \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$INSTALLED_UNREAL_SHA256" != "$UNREAL_LIB_ORIGINAL_SHA256" ]]; then
        print "The installed libUnreal.so does not match the verified original: $INSTALLED_UNREAL_SHA256"
        exit 1
    fi
    readonly EXISTING_UNREAL_MOUNT_COUNT="$(
        "$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo \
            | tr -d '\r' \
            | awk -v target="$UNREAL_LIB_TARGET" '$5 == target { count++ } END { print count + 0 }'
    )"
    if [[ "$EXISTING_UNREAL_MOUNT_COUNT" != "0" ]]; then
        print "A libUnreal.so mount already exists before launch; shut down the AVD before applying another overlay."
        exit 1
    fi

    readonly UNREAL_REMOTE="$UNREAL_LIB_REMOTE_DIR/libUnreal.so"
    readonly UNREAL_TARGET_OWNER="$("$ADB" -s "$SERIAL" shell stat -c '%u:%g' "$UNREAL_LIB_TARGET" | tr -d '\r')"
    readonly UNREAL_TARGET_MODE="$("$ADB" -s "$SERIAL" shell stat -c '%a' "$UNREAL_LIB_TARGET" | tr -d '\r')"
    readonly UNREAL_TARGET_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$UNREAL_LIB_TARGET" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ ! "$UNREAL_TARGET_CONTEXT" =~ '^u:object_r:[A-Za-z0-9_]+:s0$' ]]; then
        print "The libUnreal.so SELinux context could not be determined safely: $UNREAL_TARGET_CONTEXT"
        exit 1
    fi
    "$ADB" -s "$SERIAL" shell mkdir -p "$UNREAL_LIB_REMOTE_DIR"
    "$ADB" -s "$SERIAL" push "$UNREAL_LIB_OVERLAY" "$UNREAL_REMOTE.next" >/dev/null
    "$ADB" -s "$SERIAL" shell chmod "$UNREAL_TARGET_MODE" "$UNREAL_REMOTE.next"
    "$ADB" -s "$SERIAL" shell chown "$UNREAL_TARGET_OWNER" "$UNREAL_REMOTE.next"
    "$ADB" -s "$SERIAL" shell chcon "$UNREAL_TARGET_CONTEXT" "$UNREAL_REMOTE.next"
    readonly UNREAL_REMOTE_CONTEXT="$(
        "$ADB" -s "$SERIAL" shell ls -Zd "$UNREAL_REMOTE.next" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    if [[ "$UNREAL_REMOTE_CONTEXT" != "$UNREAL_TARGET_CONTEXT" ]]; then
        print "The staging libUnreal.so SELinux context does not match the target."
        exit 1
    fi
    "$ADB" -s "$SERIAL" shell mv "$UNREAL_REMOTE.next" "$UNREAL_REMOTE"
    "$ADB" -s "$SERIAL" shell mount -o bind "$UNREAL_REMOTE" "$UNREAL_LIB_TARGET"
    UNREAL_LIB_MOUNTED=1

    readonly ACTIVE_UNREAL_SHA256="$(
        "$ADB" -s "$SERIAL" shell sha256sum "$UNREAL_LIB_TARGET" \
            | tr -d '\r' \
            | awk '{ print $1 }'
    )"
    readonly ACTIVE_UNREAL_MOUNT_COUNT="$(
        "$ADB" -s "$SERIAL" shell cat /proc/self/mountinfo \
            | tr -d '\r' \
            | awk -v target="$UNREAL_LIB_TARGET" '$5 == target { count++ } END { print count + 0 }'
    )"
    if [[ "$ACTIVE_UNREAL_SHA256" != "$UNREAL_LIB_OVERLAY_SHA256" \
            || "$ACTIVE_UNREAL_MOUNT_COUNT" != "1" ]]; then
        print "A single verified libUnreal.so overlay could not be mounted."
        exit 1
    fi
fi

if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
    ANGLE_ORIGINAL_PACKAGES="$("$ADB" -s "$SERIAL" shell settings get global angle_gl_driver_selection_pkgs | tr -d '\r')"
    ANGLE_ORIGINAL_VALUES="$("$ADB" -s "$SERIAL" shell settings get global angle_gl_driver_selection_values | tr -d '\r')"
    ANGLE_ORIGINAL_FEATURES="$("$ADB" -s "$SERIAL" shell settings get global angle_egl_features | tr -d '\r')"
    ANGLE_SETTINGS_MANAGED=1
fi

"$ADB" -s "$SERIAL" shell settings put global angle_gl_driver_selection_pkgs "$PACKAGE"
"$ADB" -s "$SERIAL" shell settings put global angle_gl_driver_selection_values "$GUEST_GL_DRIVER"
if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
    "$ADB" -s "$SERIAL" shell settings delete global angle_egl_features >/dev/null
    "$ADB" -s "$SERIAL" shell "setprop debug.angle.feature_overrides_enabled ''"
    "$ADB" -s "$SERIAL" shell "setprop debug.angle.feature_overrides_disabled ''"
else
    "$ADB" -s "$SERIAL" shell settings put global angle_egl_features "$ANGLE_FEATURES"
    "$ADB" -s "$SERIAL" shell setprop debug.angle.feature_overrides_enabled "$ANGLE_FEATURES"
    if [[ -n "$ANGLE_DISABLED_FEATURES" ]]; then
        "$ADB" -s "$SERIAL" shell setprop debug.angle.feature_overrides_disabled "$ANGLE_DISABLED_FEATURES"
    else
        "$ADB" -s "$SERIAL" shell "setprop debug.angle.feature_overrides_disabled ''"
    fi
fi
"$ADB" -s "$SERIAL" shell settings put global show_angle_in_use_dialog_box 0

if [[ "$GUEST_SUBMIT_THREAD" != "default" ]]; then
    GUEST_WRAP_ORIGINAL="$("$ADB" -s "$SERIAL" shell getprop "$WRAP_PROPERTY" | tr -d '\r')"
    if [[ ! "$GUEST_WRAP_ORIGINAL" =~ '^[-A-Za-z0-9_./= ]*$' ]]; then
        print "The original Android process wrapper contains unsafe characters; refusing to modify it."
        exit 1
    fi
    GUEST_WRAP_MANAGED=1
    if [[ "$GUEST_SUBMIT_THREAD" == "on-demand" ]]; then
        "$ADB" -s "$SERIAL" shell "setprop '$WRAP_PROPERTY' '/system/bin/env'"
        readonly EXPECTED_GUEST_WRAP="/system/bin/env"
    else
        "$ADB" -s "$SERIAL" shell \
            "setprop '$WRAP_PROPERTY' '/system/bin/env MESA_VK_ENABLE_SUBMIT_THREAD=$GUEST_SUBMIT_THREAD'"
        readonly EXPECTED_GUEST_WRAP="/system/bin/env MESA_VK_ENABLE_SUBMIT_THREAD=$GUEST_SUBMIT_THREAD"
    fi
    readonly ACTIVE_GUEST_WRAP="$("$ADB" -s "$SERIAL" shell getprop "$WRAP_PROPERTY" | tr -d '\r')"
    if [[ "$ACTIVE_GUEST_WRAP" != "$EXPECTED_GUEST_WRAP" ]]; then
        print "The Android process wrapper was not applied: ${ACTIVE_GUEST_WRAP:-empty}."
        exit 1
    fi
fi

HWUI_RENDERER_ORIGINAL="$(
    "$ADB" -s "$SERIAL" shell getprop debug.hwui.renderer \
        | tr -d '\r'
)"
if [[ ! "$HWUI_RENDERER_ORIGINAL" =~ '^[-A-Za-z0-9._]*$' ]]; then
    print "The original Android HWUI renderer contains unsafe characters."
    exit 1
fi
if [[ "$HWUI_RENDERER_ORIGINAL" != "$HWUI_RENDERER" ]]; then
    "$ADB" -s "$SERIAL" shell setprop debug.hwui.renderer "$HWUI_RENDERER"
    HWUI_RENDERER_MANAGED=1
fi
readonly ACTIVE_HWUI_RENDERER="$(
    "$ADB" -s "$SERIAL" shell getprop debug.hwui.renderer \
        | tr -d '\r'
)"
if [[ "$ACTIVE_HWUI_RENDERER" != "$HWUI_RENDERER" ]]; then
    print "The Android HWUI renderer was not applied: ${ACTIVE_HWUI_RENDERER:-empty}."
    exit 1
fi

if ! "$ADB" -s "$SERIAL" shell cmd locale set-app-locales "$PACKAGE" "$GAME_LANGUAGE" >/dev/null 2>&1; then
    print "Android app locale could not be applied; Unreal will use the selected culture from UECommandLine."
fi
"$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE"

# Riot's streaming installer can leave a zero-byte release manifest and sparse
# chunk placeholders behind when its first download is interrupted. On every
# later start the game tries to repair that cache, fails with "Truncated
# manifest header", and leaves the patching screen waiting forever. The cache
# contains only downloadable public game resources, so reset that directory
# when the exact corrupt state is present. Login and other app data stay intact.
readonly STREAMING_INSTALL_DIR="/sdcard/Android/data/$PACKAGE/files/StreamingInstalls"
readonly STREAMING_INSTALL_MANIFEST="$STREAMING_INSTALL_DIR/Metadata.manifest"
if "$ADB" -s "$SERIAL" shell test -e "$STREAMING_INSTALL_MANIFEST" \
        && ! "$ADB" -s "$SERIAL" shell test -s "$STREAMING_INSTALL_MANIFEST"; then
    print "Empty TFT streaming manifest detected; resetting the downloadable streaming cache."
    "$ADB" -s "$SERIAL" shell rm -rf "$STREAMING_INSTALL_DIR"
    "$ADB" -s "$SERIAL" shell sync
    if "$ADB" -s "$SERIAL" shell test -e "$STREAMING_INSTALL_DIR"; then
        print "Could not remove the corrupt TFT streaming cache."
        exit 1
    fi
    print "Corrupt TFT streaming cache removed; TFT will download the required resources again."
fi

"$ADB" -s "$SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

if [[ "$PROFILE_MOUNTED" == "1" ]]; then
    typeset -i profile_waited=0
    typeset PROFILE_GAME_PID PROFILE_PROCESS_MOUNT_COUNT PROFILE_PROCESS_SHA256
    PROFILE_PROCESS_VERIFIED=0
    while (( profile_waited < 90 )); do
        PROFILE_GAME_PID="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
        PROFILE_GAME_PID="${PROFILE_GAME_PID%% *}"
        if [[ -n "$PROFILE_GAME_PID" ]]; then
            PROFILE_PROCESS_MOUNT_COUNT="$(
                "$ADB" -s "$SERIAL" shell cat "/proc/$PROFILE_GAME_PID/mountinfo" 2>/dev/null \
                    | tr -d '\r' \
                    | awk -v target="$PROFILE_DESTINATION" '$5 == target { count++ } END { print count + 0 }' \
                    || true
            )"
            PROFILE_PROCESS_SHA256="$(
                "$ADB" -s "$SERIAL" shell sha256sum "/proc/$PROFILE_GAME_PID/root$PROFILE_DESTINATION" 2>/dev/null \
                    | tr -d '\r' \
                    | awk '{ print $1 }' \
                    || true
            )"
            if [[ "$PROFILE_PROCESS_MOUNT_COUNT" == "1" \
                    && "$PROFILE_PROCESS_SHA256" == "$EXPECTED_PROFILE_SHA256" ]]; then
                PROFILE_PROCESS_VERIFIED=1
                break
            fi
        fi
        if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
            print "The emulator exited while the guest profile namespace was being verified."
            exit 0
        fi
        sleep 1
        (( profile_waited += 1 ))
    done
    if [[ "$PROFILE_PROCESS_VERIFIED" != "1" ]]; then
        print "Guest DeviceProfiles.ini with the expected SHA-256 is not visible in the TFT mount namespace."
        exit 1
    fi
    print "Guest DeviceProfiles.ini was verified in the mount namespace of TFT PID $PROFILE_GAME_PID."
fi

if [[ "$GUEST_SUBMIT_THREAD" == "0" || "$GUEST_SUBMIT_THREAD" == "1" ]]; then
    typeset -i submit_waited=0
    typeset SUBMIT_GAME_PID ACTIVE_SUBMIT_ENV
    SUBMIT_ENV_VERIFIED=0
    while (( submit_waited < 90 )); do
        SUBMIT_GAME_PID="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
        if [[ -n "$SUBMIT_GAME_PID" ]]; then
            ACTIVE_SUBMIT_ENV="$(
                "$ADB" -s "$SERIAL" shell cat "/proc/$SUBMIT_GAME_PID/environ" 2>/dev/null \
                    | tr '\0' '\n' \
                    | grep -Fx "MESA_VK_ENABLE_SUBMIT_THREAD=$GUEST_SUBMIT_THREAD" || true
            )"
            if [[ "$ACTIVE_SUBMIT_ENV" == "MESA_VK_ENABLE_SUBMIT_THREAD=$GUEST_SUBMIT_THREAD" ]]; then
                SUBMIT_ENV_VERIFIED=1
                break
            fi
        fi
        if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
            print "The emulator exited while the guest submit thread was being verified."
            exit 0
        fi
        sleep 1
        (( submit_waited += 1 ))
    done
    if [[ "$SUBMIT_ENV_VERIFIED" != "1" ]]; then
        print "MESA_VK_ENABLE_SUBMIT_THREAD did not appear in the TFT environment within 90 seconds."
        exit 1
    fi
    print "The guest Vulkan submit mode was verified through /proc/PID/environ: $GUEST_SUBMIT_THREAD."
elif [[ "$GUEST_SUBMIT_THREAD" == "on-demand" ]]; then
    typeset -i control_waited=0
    typeset CONTROL_GAME_PID CONTROL_SUBMIT_ENV
    CONTROL_ENV_VERIFIED=0
    while (( control_waited < 90 )); do
        CONTROL_GAME_PID="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
        CONTROL_GAME_PID="${CONTROL_GAME_PID%% *}"
        if [[ -n "$CONTROL_GAME_PID" ]]; then
            CONTROL_SUBMIT_ENV="$(
                "$ADB" -s "$SERIAL" shell cat "/proc/$CONTROL_GAME_PID/environ" 2>/dev/null \
                    | tr '\0' '\n' \
                    | grep -E '^MESA_VK_ENABLE_SUBMIT_THREAD=' || true
            )"
            if [[ -z "$CONTROL_SUBMIT_ENV" ]]; then
                CONTROL_ENV_VERIFIED=1
                break
            fi
        fi
        if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
            print "The emulator exited while the control submit mode was being verified."
            exit 0
        fi
        sleep 1
        (( control_waited += 1 ))
    done
    if [[ "$CONTROL_ENV_VERIFIED" != "1" ]]; then
        print "The control mode is contaminated by MESA_VK_ENABLE_SUBMIT_THREAD."
        exit 1
    fi
    print "The guest Vulkan submit control was verified: MESA_VK_ENABLE_SUBMIT_THREAD is absent."
fi

if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
    typeset -i native_waited=0
    typeset GAME_PID GAME_MAPS
    NATIVE_GLES_VERIFIED=0
    while (( native_waited < 90 )); do
        GAME_PID="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
        if [[ -n "$GAME_PID" ]]; then
            GAME_MAPS="$("$ADB" -s "$SERIAL" shell cat "/proc/$GAME_PID/maps" 2>/dev/null | tr -d '\r' || true)"
            if [[ "$GAME_MAPS" == *libEGL_emulation.so* \
                    && "$GAME_MAPS" == *libGLESv2_emulation.so* \
                    && "$GAME_MAPS" == *libGLESv2_enc.so* ]]; then
                if [[ "$GAME_MAPS" == *libGLESv2_angle.so* ]]; then
                    print "Native GLES verification failed: guest ANGLE is still loaded."
                    exit 1
                fi
                NATIVE_GLES_VERIFIED=1
                break
            fi
        fi
        if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
            print "The emulator exited while native GLES was being verified."
            exit 0
        fi
        sleep 1
        (( native_waited += 1 ))
    done
    if [[ "$NATIVE_GLES_VERIFIED" != "1" ]]; then
        print "Native GLES could not be verified through /proc/PID/maps within 90 seconds."
        exit 1
    fi
    print "Native GLES was verified: the gfxstream GLES encoder is loaded and guest ANGLE is absent."
fi

TFT_SERIAL="$SERIAL" \
TFT_ADB="$ADB" \
TFT_PSO_CPU_LIST="0-$(( CPU_CORES - 1 ))" \
    "$PROJECT_DIR/scripts/watch-root-pso.command" &
WATCHER_PID=$!

case "$RENDERER" in
    direct-vulkan)
        print "TFT is running: Unreal Vulkan -> gfxstream -> MoltenVK -> Metal, ${DISPLAY_SIZE}@${DISPLAY_DENSITY}dpi@60, audio $AUDIO_STATUS."
        ;;
    angle-opengl)
        if [[ "$GUEST_GL_DRIVER" == "native" ]]; then
            if [[ "$HOST_GPU" == "swangle" ]]; then
                print "TFT is running: Unreal OpenGL ES -> gfxstream GLES encoder -> host ANGLE -> Vulkan -> SwiftShader CPU, ${DISPLAY_SIZE}@${DISPLAY_DENSITY}dpi@60, audio $AUDIO_STATUS."
            else
                print "TFT is running: Unreal OpenGL ES -> gfxstream GLES encoder -> host ANGLE -> Metal, ${DISPLAY_SIZE}@${DISPLAY_DENSITY}dpi@60, audio $AUDIO_STATUS."
            fi
        else
            print "TFT is running: Unreal OpenGL ES -> guest ANGLE -> Vulkan -> Metal, ${DISPLAY_SIZE}@${DISPLAY_DENSITY}dpi@60, audio $AUDIO_STATUS."
        fi
        ;;
    angle)
        print "TFT is running: stock OpenGL ES -> ANGLE -> Vulkan -> Metal, ${DISPLAY_SIZE}@${DISPLAY_DENSITY}dpi@60, audio $AUDIO_STATUS."
        ;;
esac
print "Root remains visible; the watcher only changes live scheduling for PSO threads."
if [[ "$INPUT_BRIDGE_ENABLED" == "1" ]]; then
    print "GameActivity controls: Space - shop, D - reroll, F - buy XP, Tab - items/traits, V - players/damage; right-click is blocked only in game."
    if [[ "$INPUT_DIAGNOSTICS" == "1" ]]; then
        print "Input diagnostics: click marker and host timestamps are enabled; log=${INPUT_DIAGNOSTICS_LOG:-stderr}."
    fi
fi
print "Graphics profile: $GRAPHICS_PROFILE."
print "TFT renderer: $RENDERER."
print "Host GPU backend: $HOST_GPU."
print "Android HWUI renderer: $HWUI_RENDERER; the Unreal renderer is unchanged."
print "Guest GL driver: $GUEST_GL_DRIVER."
print "Guest Vulkan submit thread: $GUEST_SUBMIT_THREAD."
print "Guest resources: ${CPU_CORES} cores, ${MEMORY_MB} MB RAM."
print "Unreal UI scale: ${UI_SCALE}x."
print "ANGLE enabled features: $ANGLE_FEATURES."
print "ANGLE disabled features: ${ANGLE_DISABLED_FEATURES:-none}."
if [[ -n "$OVERLAY_APK" ]]; then
    print "$OVERLAY_LABEL overlay: the APK and DeviceProfile passed SHA-256 verification and bind mounts were established 0->1."
fi
if [[ "$UNREAL_LIB_MOUNTED" == "1" ]]; then
    print "libUnreal.so overlay: SHA-256 and the 0->1 mount invariant were verified before process startup."
fi
if [[ "$BATCHED_DESCRIPTORS" == "1" ]]; then
    print "Experiment enabled: VulkanBatchedDescriptorSetUpdate."
fi
if [[ "$VIRTIO_GPU_NATIVE_SYNC" == "1" ]]; then
    print "Experiment enabled: VirtioGpuNativeSync."
fi
if [[ "$VIRTIO_GPU_NEXT" == "1" ]]; then
    print "Experiment enabled: VirtioGpuNext."
fi
if [[ -n "$GL_DRAW_FLUSH_INTERVAL" ]]; then
    print "Graphics draw flush interval: $GL_DRAW_FLUSH_INTERVAL microseconds."
fi
if [[ "$MVK_QUEUE_MODE" == "async" ]]; then
    print "Experiment enabled: asynchronous MoltenVK queue submissions."
elif [[ "$MVK_QUEUE_MODE" == "sync" ]]; then
    print "Control mode: synchronous MoltenVK queue submissions."
fi
if [[ "${MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE:-}" == "8" \
        && "${MVK_CONFIG_FAST_MATH_ENABLED:-}" == "1" ]]; then
    print "OSFT MoltenVK tuning: 8 active Metal command buffers, fast math."
fi
if [[ "$MACOS_GAME_MODE" == "1" ]]; then
    print "The Game Mode app wrapper is active. Enter fullscreen and verify Cmd-Esc -> Game Mode: On."
fi
print "Closing the Android Emulator window will shut down the experimental AVD."

wait "$EMULATOR_PID" || true
print "The emulator was closed; this is treated as a normal exit."
