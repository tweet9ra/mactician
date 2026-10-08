# Building

## Requirements

- Apple Silicon Mac with macOS 12.0 or later
- Xcode Command Line Tools (`xcrun swiftc`, `xcrun clang`, `codesign`, `plutil`)
- zsh, `jq`, `rg`, `curl`, `tar`, `zip`, `unzip`, `shasum`, and `xmllint`
- Node.js only for `scripts/login-tft-from-keychain.command`
- Android NDK r27d (`27.3.13750724`) for the bundled ARM64 Vulkan cache;
  set `TFT_ANDROID_NDK` to its directory. End users do not need the NDK.
- Four exact unmodified TFT `18.4-5637330` APK splits in a private local
  directory; names, sizes, and hashes are in
  `launcher/Resources/release-manifest.json`

Production binaries target `arm64-apple-macosx12.0`. Unit-test binaries target
the current macOS host architecture so CI can run on either Intel or Apple
Silicon runners; production and release targets remain Apple Silicon-only.

## Sparkle preparation

`scripts/prepare-sparkle.command` downloads Sparkle 2.9.4 from its upstream
GitHub release into `launcher/.build/`, verifies SHA-256
`ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9`,
validates its signature, and stages the framework and release tools. A valid
cached copy is reused.

```sh
./scripts/prepare-sparkle.command
```

## Fast validation

```sh
./scripts/verify-repository.command
./scripts/test-mactician.command
TFT_ANDROID_NDK="$ANDROID_HOME/ndk/27.3.13750724" ./scripts/test-vulkan-view-cache.command
```

Together these commands check repository policy, shell syntax, plist/strings
and JSON syntax, Markdown links, executable bits, version consistency, C
syntax, unit tests, and full Swift typechecking. The test script also verifies
runtime shutdown classification, update safeguards, the scoped login repaint
repair, English/Russian UI resources, resource selectors, overlay preparation, and
state serialization.

The native test command cross-compiles the shipped layer, tests its object
lifetimes and dispatch on the host, and injects failures throughout its Android
settings transaction. CI also runs it. GPU readbacks and paired game captures
remain device tests; see [the cache implementation](../native/vulkan-buffer-view-cache/README.md).

Install the pinned NDK with Android Studio or
[`sdkmanager`](https://developer.android.com/tools/sdkmanager):

```sh
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install "ndk;27.3.13750724"
export TFT_ANDROID_NDK="$ANDROID_HOME/ndk/27.3.13750724"
```

Equivalent focused checks include:

```sh
find . -type f \( -name '*.command' -o -name '*.sh' \) -print0 \
  | xargs -0 -n 1 zsh -o NO_BG_NICE -n
find launcher -type f \( -name '*.plist' -o -name '*.strings' \) -print0 \
  | xargs -0 -n 1 plutil -lint
find . -type f -name '*.json' -print0 | xargs -0 -n 1 jq empty
xcrun clang -target arm64-apple-macosx12.0 -fsyntax-only launcher/EmulatorHost/main.c
```

## Local ad-hoc build

```sh
PROJECT_DIR="$PWD"
TFT_GAME_APK_DIR="$PROJECT_DIR/private/tft-apks" \
  ./scripts/build-mactician.command
```

The builder verifies all APK hashes, compiles the SwiftUI app and emulator host,
copies the pinned Sparkle framework and runtime template, rejects embedded
developer paths, signs nested code from the inside out with an ad-hoc identity,
verifies the app, and creates the DMG in `dist/`.

The resulting DMG embeds the four verified game APK splits.

## Provisioning integration test

Build the app first, close every Android Emulator process, then run:

```sh
./scripts/integration-test-mactician.command
```

The script downloads and verifies the three large Android fixtures, compiles
`InstallerIntegration.swift`, provisions a temporary SDK/AVD, and validates the
ready state. It is deliberately excluded from normal pull-request CI.

## Optional Developer ID and notarized build

After the `mactician-notary` Keychain profile and a single Developer ID
Application identity are installed, build a public release with one command:

```sh
./scripts/build-mactician-release.command
```

The wrapper uses `private/tft-apks` by default, validates the notarization
profile before compiling, and automatically selects the installed Developer ID
Application identity. Override `TFT_GAME_APK_DIR`,
`MACTICIAN_NOTARY_PROFILE`, or `MACTICIAN_CODESIGN_IDENTITY` only when the
machine has a non-default setup.

The lower-level equivalent is:

```sh
PROJECT_DIR="$PWD"
: "${MACTICIAN_CODESIGN_IDENTITY:?Set MACTICIAN_CODESIGN_IDENTITY in the environment}"
: "${MACTICIAN_NOTARY_PROFILE:?Set MACTICIAN_NOTARY_PROFILE in the environment}"
TFT_GAME_APK_DIR="$PROJECT_DIR/private/tft-apks" \
  ./scripts/build-mactician.command
```

The script requires a Developer ID Application identity when either public
release setting is present. It enables hardened runtime, uses secure timestamps,
submits the DMG, waits for acceptance, staples and validates the ticket, and
assesses the distribution.

## Environment variables

| Variable | Purpose |
| --- | --- |
| `TFT_GAME_APK_DIR` | Required build input directory containing four pinned APK splits |
| `TFT_ANDROID_NDK` / `ANDROID_NDK_HOME` | Android NDK r27d for the native cache build |
| `TFT_VULKAN_VIEW_CACHE` | `auto` enables the built cache on the validated game/ANGLE combination; `0` disables it; `1` requires it |
| `MACTICIAN_CODESIGN_IDENTITY` | Developer ID Application identity; default `-` is ad hoc |
| `MACTICIAN_NOTARY_PROFILE` | notarytool Keychain profile for a public release |
| `TFT_ANDROID_SDK_ROOT` / `TFT_ROOT_SDK` | Explicit Android SDK for source launch scripts |
| `ANDROID_SDK_ROOT`, `ANDROID_HOME` | Standard Android SDK discovery fallbacks |
| `TFT_ADB`, `TFT_EMULATOR` | Explicit tool binaries |
| `TFT_AVD_HOME`, `TFT_ROOT_AVD_HOME`, `TFT_AVD_NAME` | External AVD selection |
| `TFT_JQ` | Non-standard `jq` path |
| `MACTICIAN_KEYCHAIN_SERVICE` | Optional login-helper Keychain service |
| `MACTICIAN_SPARKLE_ACCOUNT` | Sparkle Ed25519 Keychain account for appcast generation |
| `MACTICIAN_UPDATE_*` | Release URLs, SSH destination, remote root, work directory, and inputs |

## Common failures

- **Sparkle download/hash failure:** remove only the partial cache file and
  retry on a trusted network; do not change the pinned hash to match a download.
- **Missing APK input:** set `TFT_GAME_APK_DIR`; the repository intentionally
  does not contain game packages.
- **APK mismatch:** use the exact pinned release or update the manifest only as
  part of a separately verified game-version change.
- **No signing identity:** use the default ad-hoc mode for local testing or
  install the intended Developer ID identity and set its exact reported name.
- **Module-cache or stale output issue:** remove ignored `launcher/.build/` or
  `dist/` output, then rerun; source files are unaffected.
- **Integration test refuses to start:** close other Emulator processes to avoid
  shared host/ADB state.
