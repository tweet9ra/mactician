#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly LAUNCHER_DIR="$PROJECT_DIR/launcher"
readonly BUILD_DIR="$LAUNCHER_DIR/.build"
readonly DIST_DIR="${MACTICIAN_DIST_DIR:-$PROJECT_DIR/dist}"
readonly SPARKLE_ROOT="$("$PROJECT_DIR/scripts/prepare-sparkle.command")"
readonly SPARKLE_FRAMEWORK_SOURCE="$SPARKLE_ROOT/Sparkle.framework"
readonly SPARKLE_LICENSE_SOURCE="$SPARKLE_ROOT/LICENSE"
readonly SIGNING_IDENTITY="${MACTICIAN_CODESIGN_IDENTITY:--}"
readonly NOTARY_PROFILE="${MACTICIAN_NOTARY_PROFILE:-}"
readonly VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LAUNCHER_DIR/Info.plist")"
typeset -i PUBLIC_RELEASE=0
if [[ "$SIGNING_IDENTITY" != "-" || -n "$NOTARY_PROFILE" ]]; then
    if [[ "$SIGNING_IDENTITY" != 'Developer ID Application: '* || -z "$NOTARY_PROFILE" ]]; then
        print -u2 "A public release requires both a Developer ID Application identity and MACTICIAN_NOTARY_PROFILE."
        exit 2
    fi
    if ! security find-identity -v -p codesigning \
            | grep -Fq -- "\"$SIGNING_IDENTITY\""; then
        print -u2 "Developer ID signing identity is not available in the login Keychain: $SIGNING_IDENTITY"
        exit 2
    fi
    PUBLIC_RELEASE=1
fi
readonly PUBLIC_RELEASE
readonly APP="$DIST_DIR/Mactician.app"
readonly DMG="$DIST_DIR/Mactician-$VERSION.dmg"
readonly APP_CONTENTS="$APP/Contents"
readonly RESOURCES="$APP_CONTENTS/Resources"
readonly HELPERS="$APP_CONTENTS/Helpers"
readonly THIRD_PARTY_LICENSES="$RESOURCES/ThirdPartyLicenses"
readonly FRAMEWORKS="$APP_CONTENTS/Frameworks"
readonly GAME_RESOURCES="$RESOURCES/Game"
readonly RUNTIME_TEMPLATE="$RESOURCES/RuntimeTemplate"
readonly EMULATOR_APP="$HELPERS/Mactician Game Host.app"
readonly EMULATOR_APP_CONTENTS="$EMULATOR_APP/Contents"
readonly APK_DIR="${TFT_GAME_APK_DIR:-}"

if [[ -z "$APK_DIR" ]]; then
    print -u2 "TFT_GAME_APK_DIR must point to the directory containing the four pinned, unmodified APK splits."
    exit 1
fi

typeset -A EXPECTED_APK_HASHES
EXPECTED_APK_HASHES=(
    base.apk 020cac678a80783d3fd092a93d6ccd3bb53becffca24a1fc367714b84467d97a
    config.arm64_v8a.apk 29194f199ffc9a61cc96f6f265e79a8a8e8f558f7796370188a1a233e83e403d
    config.en.apk 3d4893049d1229a940f148268a9aeb63fbda2b21084875b2aa9feb631d66bc04
    config.mdpi.apk db8ffe004222597c7e0b51c39899fd599129ea32a56fc4e9ec11f65fcf15f431
)

for apk expected_hash in ${(kv)EXPECTED_APK_HASHES}; do
    apk_path="$APK_DIR/$apk"
    if [[ ! -f "$apk_path" ]]; then
        print -u2 "Private build input not found: $apk_path"
        exit 1
    fi
    actual_hash="$(shasum -a 256 "$apk_path" | awk '{print $1}')"
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        print -u2 "SHA-256 for $apk does not match the TFT 18.1 manifest."
        exit 1
    fi
done

copy_plain_file() {
    local source_path="$1"
    local destination_path="$2"
    local temporary_copy
    temporary_copy="$(mktemp /private/tmp/mactician-copy.XXXXXX)"
    if ! cp -X "$source_path" "$temporary_copy"; then
        rm -f "$temporary_copy"
        return 1
    fi
    chmod 644 "$temporary_copy"
    if ! mv -f "$temporary_copy" "$destination_path"; then
        rm -f "$temporary_copy"
        return 1
    fi
}

rm -rf "$BUILD_DIR/module-cache" "$APP" "$DMG"
mkdir -p "$BUILD_DIR" "$APP_CONTENTS/MacOS" "$RESOURCES" "$HELPERS" "$FRAMEWORKS" "$GAME_RESOURCES" \
    "$THIRD_PARTY_LICENSES" \
    "$RUNTIME_TEMPLATE/scripts" \
    "$RUNTIME_TEMPLATE/artifacts/tft-18.1-angle-opengl" \
    "$EMULATOR_APP_CONTENTS/MacOS" "$EMULATOR_APP_CONTENTS/Resources" \
    "$DIST_DIR"

mkdir -p "$BUILD_DIR/module-cache"
typeset -a SWIFT_SOURCES
SWIFT_SOURCES=("$LAUNCHER_DIR"/Sources/*.swift)
xcrun swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macosx12.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -F "$SPARKLE_ROOT" \
    "${SWIFT_SOURCES[@]}" \
    -framework Sparkle \
    -Xlinker -rpath \
    -Xlinker @executable_path/../Frameworks \
    -o "$APP_CONTENTS/MacOS/Mactician"

ditto "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS/Sparkle.framework"
# The launcher is not App Sandbox-enabled. Sparkle's XPC services are only for
# sandboxed hosts and complicate manual Developer ID signing unnecessarily.
rm -rf "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices"
rm -f "$FRAMEWORKS/Sparkle.framework/XPCServices"

copy_plain_file "$LAUNCHER_DIR/Info.plist" "$APP_CONTENTS/Info.plist"
copy_plain_file "$LAUNCHER_DIR/Resources/Mactician.icns" "$RESOURCES/Mactician.icns"
copy_plain_file "$LAUNCHER_DIR/Resources/release-manifest.json" "$RESOURCES/release-manifest.json"
copy_plain_file "$LAUNCHER_DIR/Resources/MacticianHero.png" "$RESOURCES/MacticianHero.png"
copy_plain_file "$LAUNCHER_DIR/Resources/launcher-runtime.command" "$RESOURCES/launcher-runtime.command"
copy_plain_file "$LAUNCHER_DIR/Resources/QEMU-Hypervisor.entitlements" "$RESOURCES/QEMU-Hypervisor.entitlements"
copy_plain_file "$SPARKLE_LICENSE_SOURCE" "$THIRD_PARTY_LICENSES/Sparkle-LICENSE.txt"
chmod 755 "$RESOURCES/launcher-runtime.command"

for localization in en ru; do
    mkdir -p "$RESOURCES/$localization.lproj"
    copy_plain_file "$LAUNCHER_DIR/Resources/$localization.lproj/Localizable.strings" \
        "$RESOURCES/$localization.lproj/Localizable.strings"
    plutil -lint "$RESOURCES/$localization.lproj/Localizable.strings" >/dev/null
done

copy_plain_file "$LAUNCHER_DIR/Resources/EmulatorHost-Info.plist" "$EMULATOR_APP_CONTENTS/Info.plist"
copy_plain_file "$LAUNCHER_DIR/Resources/EmulatorIcon.icns" "$EMULATOR_APP_CONTENTS/Resources/EmulatorIcon.icns"
xcrun clang \
    -x objective-c \
    -O2 \
    -target arm64-apple-macosx12.0 \
    "$LAUNCHER_DIR/EmulatorHost/main.c" \
    -framework AppKit \
    -o "$EMULATOR_APP_CONTENTS/MacOS/MacticianGameHost"

for apk in ${(k)EXPECTED_APK_HASHES}; do
    copy_plain_file "$APK_DIR/$apk" "$GAME_RESOURCES/$apk"
done

copy_plain_file "$PROJECT_DIR/run-tft-root-affinity.command" "$RUNTIME_TEMPLATE/run-tft-root-affinity.command"
copy_plain_file "$PROJECT_DIR/run-tft-angle-opengl.command" "$RUNTIME_TEMPLATE/run-tft-angle-opengl.command"
copy_plain_file "$PROJECT_DIR/run-tft-google-play.command" "$RUNTIME_TEMPLATE/run-tft-google-play.command"
copy_plain_file "$PROJECT_DIR/scripts/run-asg-experiment.command" "$RUNTIME_TEMPLATE/scripts/run-asg-experiment.command"
copy_plain_file "$PROJECT_DIR/scripts/watch-root-pso.command" "$RUNTIME_TEMPLATE/scripts/watch-root-pso.command"
copy_plain_file "$PROJECT_DIR/scripts/update-tft-performance-mode.command" "$RUNTIME_TEMPLATE/scripts/update-tft-performance-mode.command"
copy_plain_file "$PROJECT_DIR/scripts/android-environment.sh" "$RUNTIME_TEMPLATE/scripts/android-environment.sh"
copy_plain_file "$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.shader-prewarm.ini" \
    "$RUNTIME_TEMPLATE/artifacts/tft-18.1-angle-opengl/Android_Codex.DeviceProfiles.shader-prewarm.ini"
copy_plain_file "$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini" \
    "$RUNTIME_TEMPLATE/artifacts/tft-18.1-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini"
copy_plain_file "$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.effects-high.ini" \
    "$RUNTIME_TEMPLATE/artifacts/tft-18.1-angle-opengl/Android_Codex.DeviceProfiles.effects-high.ini"
copy_plain_file "$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.effects-performance.ini" \
    "$RUNTIME_TEMPLATE/artifacts/tft-18.1-angle-opengl/Android_Codex.DeviceProfiles.effects-performance.ini"
chmod 755 \
    "$RUNTIME_TEMPLATE/run-tft-root-affinity.command" \
    "$RUNTIME_TEMPLATE/run-tft-angle-opengl.command" \
    "$RUNTIME_TEMPLATE/run-tft-google-play.command" \
    "$RUNTIME_TEMPLATE/scripts/run-asg-experiment.command" \
    "$RUNTIME_TEMPLATE/scripts/watch-root-pso.command" \
    "$RUNTIME_TEMPLATE/scripts/update-tft-performance-mode.command" \
    "$RUNTIME_TEMPLATE/scripts/android-environment.sh"

if rg -n '/Users/[[:alnum:]_.-]+/' "$APP_CONTENTS"; then
    print -u2 "The launcher build contains an absolute developer path."
    exit 1
fi

plutil -lint "$APP_CONTENTS/Info.plist" >/dev/null
plutil -lint "$EMULATOR_APP_CONTENTS/Info.plist" >/dev/null
plutil -lint "$RESOURCES/QEMU-Hypervisor.entitlements" >/dev/null

# Some synchronized or sandboxed directories can block codesign while it
# atomically replaces the linker signature. Sign an identical temporary bundle
# on the local filesystem, then copy the verified result back into dist.
readonly SIGNING_ROOT="$(mktemp -d /private/tmp/mactician-sign.XXXXXX)"
readonly SIGNING_APP="$SIGNING_ROOT/Mactician.app"
readonly SIGNING_EMULATOR_APP="$SIGNING_APP/Contents/Helpers/Mactician Game Host.app"
readonly SIGNING_SPARKLE="$SIGNING_APP/Contents/Frameworks/Sparkle.framework"
readonly SIGNING_SPARKLE_VERSION="$SIGNING_SPARKLE/Versions/B"
cleanup_signing_root() {
    rm -rf "$SIGNING_ROOT"
}
trap cleanup_signing_root EXIT
cp -R -X "$APP" "$SIGNING_APP"
if (( PUBLIC_RELEASE == 1 )); then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_SPARKLE_VERSION/Autoupdate"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_SPARKLE_VERSION/Updater.app"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_SPARKLE"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_EMULATOR_APP/Contents/MacOS/MacticianGameHost"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_EMULATOR_APP"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_APP/Contents/MacOS/Mactician"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
        "$SIGNING_APP"
else
    codesign --force --sign - --timestamp=none --options runtime \
        "$SIGNING_SPARKLE_VERSION/Autoupdate"
    codesign --force --sign - --timestamp=none --options runtime \
        "$SIGNING_SPARKLE_VERSION/Updater.app"
    codesign --force --sign - --timestamp=none --options runtime \
        "$SIGNING_SPARKLE"
    codesign --force --sign - --timestamp=none "$SIGNING_EMULATOR_APP/Contents/MacOS/MacticianGameHost"
    codesign --force --sign - --timestamp=none "$SIGNING_EMULATOR_APP"
    codesign --force --sign - --timestamp=none "$SIGNING_APP/Contents/MacOS/Mactician"
    codesign --force --sign - --timestamp=none "$SIGNING_APP"
fi
codesign --verify --deep --strict --verbose=2 "$SIGNING_APP"
rm -rf "$APP"
mv "$SIGNING_APP" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if (( PUBLIC_RELEASE == 1 )) && [[ -x /usr/bin/syspolicy_check ]]; then
    if ! syspolicy_check notary-submission "$APP"; then
        print -u2 "Warning: local syspolicy_check did not accept the unnotarized app; continuing to the authoritative Apple notary service."
    fi
fi

readonly DMG_ROOT="$SIGNING_ROOT/dmg-root"
mkdir -p "$DMG_ROOT"
cp -R -X "$APP" "$DMG_ROOT/Mactician.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
    -size 512m \
    -fs HFS+ \
    -volname "Mactician" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null
xattr -c "$DMG"

if (( PUBLIC_RELEASE == 1 )); then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
    readonly NOTARY_RESULT="$SIGNING_ROOT/notary-result.json"
    if ! xcrun notarytool submit "$DMG" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait \
            --timeout 30m \
            --output-format json >"$NOTARY_RESULT"; then
        cat "$NOTARY_RESULT" >&2
        exit 1
    fi
    cat "$NOTARY_RESULT"
    readonly NOTARY_ID="$(jq -r '.id // empty' "$NOTARY_RESULT")"
    readonly NOTARY_STATUS="$(jq -r '.status // empty' "$NOTARY_RESULT")"
    if [[ -z "$NOTARY_ID" || "$NOTARY_STATUS" != "Accepted" ]]; then
        print -u2 "Apple did not accept the notarization submission."
        exit 1
    fi
    xcrun notarytool log "$NOTARY_ID" \
        --keychain-profile "$NOTARY_PROFILE"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    if [[ -x /usr/bin/syspolicy_check ]]; then
        syspolicy_check distribution "$APP"
    fi
fi

print "App: $APP"
print "DMG: $DMG"
if (( PUBLIC_RELEASE == 1 )); then
    print "Developer ID-signed and notarized public release is ready."
else
    print "Private ad-hoc build is ready. On another Mac, allow the first launch via System Settings → Privacy & Security → Open Anyway."
fi
