#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly LAUNCHER_DIR="$PROJECT_DIR/launcher"
readonly APP_RESOURCES="${MACTICIAN_APP_RESOURCES:-$PROJECT_DIR/dist/Mactician.app/Contents/Resources}"
readonly TEST_ROOT="$(mktemp -d /tmp/mactician-integration.XXXXXX)"
readonly TEST_BINARY="$TEST_ROOT/InstallerIntegration"
readonly FIXTURE_DIR="$LAUNCHER_DIR/.build/integration-fixtures"
cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

if pgrep -f '[q]emu-system-aarch64' >/dev/null 2>&1; then
    print -u2 "Another Android Emulator is running. Close it before the provisioning integration test."
    exit 2
fi

if [[ ! -f "$APP_RESOURCES/release-manifest.json" ]]; then
    print -u2 "Build the app first: ./scripts/build-mactician.command"
    exit 1
fi

mkdir -p "$FIXTURE_DIR"
download_fixture() {
    local -r fixture_name="$1"
    local -r fixture_url="$2"
    local -r fixture_sha256="$3"
    local -r fixture_path="$FIXTURE_DIR/$fixture_name"
    if [[ ! -f "$fixture_path" ]] \
            || [[ "$(shasum -a 256 "$fixture_path" | awk '{print $1}')" != "$fixture_sha256" ]]; then
        curl -fL --retry 3 --continue-at - "$fixture_url" -o "$fixture_path.partial"
        if [[ "$(shasum -a 256 "$fixture_path.partial" | awk '{print $1}')" != "$fixture_sha256" ]]; then
            print -u2 "Integration fixture SHA-256 mismatch: $fixture_name"
            return 1
        fi
        mv -f "$fixture_path.partial" "$fixture_path"
    fi
}

download_fixture \
    platform-tools_r36.0.2-darwin.zip \
    https://dl.google.com/android/repository/platform-tools_r36.0.2-darwin.zip \
    106a5d31fad8c1c0c5a180d06f5779767d129d7d5edbe629005c11a85eec5b4b
download_fixture \
    emulator-darwin_aarch64-15917651.zip \
    https://dl.google.com/android/repository/emulator-darwin_aarch64-15917651.zip \
    22530de9363f34ea945ecb5cad74523abd4b615f27f3c1a9899efb183ea9e144
download_fixture \
    arm64-v8a-36_r07-playstore.zip \
    https://dl.google.com/android/repository/sys-img/google_apis_playstore/arm64-v8a-36_r07.zip \
    ddb0feff5c23db9f42ceabd28f6542e8ffec639abf818bf6831a2658e6cf7905

mkdir -p "$LAUNCHER_DIR/.build/module-cache"
xcrun swiftc \
    -target arm64-apple-macosx12.0 \
    -module-cache-path "$LAUNCHER_DIR/.build/module-cache" \
    "$LAUNCHER_DIR/Sources/EmulatorBrandingPatch.swift" \
    "$LAUNCHER_DIR/Sources/LauncherPresentation.swift" \
    "$LAUNCHER_DIR/Sources/CoreModels.swift" \
    "$LAUNCHER_DIR/Sources/HostedGameUpdate.swift" \
    "$LAUNCHER_DIR/Sources/LauncherPaths.swift" \
    "$LAUNCHER_DIR/Sources/SystemServices.swift" \
    "$LAUNCHER_DIR/Sources/InstallerService.swift" \
    "$LAUNCHER_DIR/Tests/InstallerIntegration.swift" \
    -o "$TEST_BINARY"

"$TEST_BINARY" \
    "$TEST_ROOT/data" \
    "$APP_RESOURCES" \
    "$FIXTURE_DIR/platform-tools_r36.0.2-darwin.zip" \
    "$FIXTURE_DIR/emulator-darwin_aarch64-15917651.zip" \
    "$FIXTURE_DIR/arm64-v8a-36_r07-playstore.zip"
