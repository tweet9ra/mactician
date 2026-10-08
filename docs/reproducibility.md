# Reproducibility

This project distinguishes source declarations, release inputs, and mutable
runtime state. A reproducible source checkout does not contain the game
packages, downloaded Android runtime, AVD userdata, or signing credentials.

## Pinned release inputs

| Input | Version/build | SHA-256 |
| --- | --- | --- |
| Android Platform Tools | 36.0.2 | `106a5d31fad8c1c0c5a180d06f5779767d129d7d5edbe629005c11a85eec5b4b` |
| Android Emulator | 37.1.11 / 15917651 | `22530de9363f34ea945ecb5cad74523abd4b615f27f3c1a9899efb183ea9e144` |
| Google APIs ARM64 system image | Android 36 revision 7 | `fb47d861d6f87230ee0fe70f610d579935ca77f41a0eefbf391595d3dc4b5ee2` |
| Sparkle | 2.9.4 | `ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9` |

The game release is `18.4-5637330`, package
`com.riotgames.league.teamfighttactics`. The four split names, sizes, and
SHA-256 values are in `launcher/Resources/release-manifest.json`; the APK bytes
are deliberately absent from Git.

The current release manifest itself hashes to:

```text
b2c0ffe7c98901a70116f105aa7e0fc710668c601f9da225e81455ab979275eb  launcher/Resources/release-manifest.json
```

## TFT 18.4-5637330 validation — 2026-10-08

Global, Vietnam, and Taiwan `18.4-5637330` (version code `8637330`) were
extracted from the complete ARM64 Android 9+ APKPure XAPK bundles for their
respective package IDs. Each edition uses the base, ARM64, English, and MDPI
splits. Official Android Build Tools 36 verified every APK signature, package,
version code, and split ID against the pinned Riot certificate SHA-256
`931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c`,
which also matches the previously pinned Global base APK.

| Edition | Complete XAPK SHA-256 |
| --- | --- |
| Global | `78160c66f3b4023c25288fc6f4b2306e93c66a85afc2b60c80785abd90dd0643` |
| Vietnam | `8775a91da6c6abebf8ede87f21d62d63d5786ebb0a083192355de79d60d5f42f` |
| Taiwan | `c1af53eb6cc8a792dc2923c67803893066a5ed77e3ac71b08633deb105bddaa3` |

Global APK hashes are pinned in the release manifest; regional hashes are
recorded in [Vietnam](vietnam.md) and [Taiwan](taiwan.md).
The Vulkan buffer-view-cache allowlist remains restricted to previously tested
Global builds, so 18.4 automatically uses the existing uncached rendering path.

The exact four splits upgraded Global from `18.3-5530794`, Vietnam from
`18.1-5423749`, and Taiwan from `18.2-5450971` in a read-only `Tft` AVD session.
Taiwan's prior pinned package was seeded into that disposable session first.
All three retained `firstInstallTime`, reached Unreal `GameActivity`, and stayed
alive for 35 seconds with no fatal or crash records. The session used the
launcher's OSFT/GuestAngle emulator flags and was stopped after testing.
Account sign-in, a full match, and performance were not tested.

An initial direct Global launch bypassed the launcher's Vulkan-cache recovery
and crashed in Android EGL with stale layer settings from the saved AVD.
The existing `guest-vulkan-view-cache.sh recover` restored those settings;
the clean upgrade/startup checks passed after running that production recovery
step. No runtime code or cache allowlist changes were required.

The full tests, Swift typecheck, ad-hoc app build, and nested code-signature
verification passed. The built app contains the exact tested manifest and
four Global APKs. Repository validation passed in a clean source copy; the
working folder's pre-existing `branding/.DS_Store` still trips the metadata check.

All three signed game feeds were published on 2026-10-08. Their public
manifests passed `HostedGameUpdate.decodeAndVerify` and matched the tested
packages, versions, hashes, and URLs. All 12 public APK HEAD requests and full
downloads matched the expected sizes and SHA-256 hashes, with immutable cache
headers. The Sparkle appcast remained byte-for-byte unchanged; no new
Mactician app release was published.

## TFT 18.3-5530794 validation — 2026-09-24

Global `18.3-5530794` (version code `8530794`) was extracted from the ARM64
[APKMirror bundle](https://www.apkmirror.com/apk/riot-games-inc/teamfight-tactics-league-of-legends-strategy-game/tft-teamfight-tactics-18-3-5530794-release/tft-teamfight-tactics-18-3-5530794-android-apk-download/).
The complete bundle SHA-256 is
`2daa90932806d5a24f7b959b4701805db98dcdc90a54770e303f6e3f0f6db6f4`.
Official Android Build Tools 36 verified all four unmodified splits against
Riot certificate SHA-256
`931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c`,
matching the previously pinned base APK.

The four splits upgraded `18.2-5492233` in a read-only `Tft` AVD session with
`adb install-multiple --no-streaming -r -g`. The version code became `8530794`
and `firstInstallTime` remained unchanged. Starting `SplashActivity` reached
Unreal `GameActivity`; the process remained alive for more than 30 seconds
with an empty crash buffer and no fatal records. The test session was stopped
afterward. This checks installation and startup, not a complete match or
performance.

The full tests, Swift typecheck, ad-hoc app build, and nested code-signature
verification passed. The control app contains the exact tested manifest and
four APKs. Repository validation passed in a clean source copy; the original
working tree retains a pre-existing validation failure caused by Russian
resources in the untracked `branding/Mactician.app` copy.

The Global signed game feed was published on 2026-09-24. Its public manifest
passed `HostedGameUpdate.decodeAndVerify`; all four public APK HEAD requests
and full downloads matched the tested sizes and SHA-256 hashes and had
immutable cache headers. The Sparkle appcast remained byte-for-byte unchanged;
no Mactician app release was published.

## TFT 18.2-5492233 validation — 2026-09-17

Global `18.2-5492233` (version code `8492233`) was extracted from the ARM64
[APKMirror bundle](https://www.apkmirror.com/apk/riot-games-inc/teamfight-tactics-league-of-legends-strategy-game/tft-teamfight-tactics-18-2-5492233-release/tft-teamfight-tactics-18-2-5492233-android-apk-download/).
Official Android Build Tools 36 verified all four unmodified splits against
Riot certificate SHA-256
`931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c`,
matching the previously pinned base APK.

The four splits upgraded `18.2-5450971` in a read-only `Tft` AVD session with
`adb install-multiple --no-streaming -r -g`. The version code became `8492233`
and `firstInstallTime` remained unchanged. Starting `SplashActivity` reached
Unreal `GameActivity`; the process remained alive for more than 60 seconds
with an empty crash buffer. The test session was stopped afterward. This
checks installation and startup, not a complete match or performance.

The full tests, Swift typecheck, ad-hoc app build, and nested code-signature
verification passed. Repository validation passed in a clean source copy;
the original working tree has a pre-existing validation failure caused by
Russian resources in the untracked `branding/Mactician.app` copy.

The Global signed game feed was published on 2026-09-17. Its public manifest
passed `HostedGameUpdate.decodeAndVerify`; all four public APK downloads
matched the tested sizes and SHA-256 hashes and had immutable cache headers.
The Sparkle appcast remained byte-for-byte unchanged.

## TFT 18.2 validation — 2026-09-10

Global `18.2-5450971` (version code `8450971`) was extracted from the ARM64
[APKMirror bundle](https://www.apkmirror.com/apk/riot-games-inc/teamfight-tactics-league-of-legends-strategy-game/tft-teamfight-tactics-18-2-5450971-release/tft-teamfight-tactics-18-2-5450971-android-apk-download/).
Official Android Build Tools 36 verified all four unmodified splits against
Riot certificate SHA-256
`931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c`.
[Vietnam](vietnam.md) and [Taiwan](taiwan.md) passed the same checks for their
separate packages and APK hashes.

All three editions upgraded from `18.1-5423749` in a test AVD copy without
changing `firstInstallTime`. The normal `RuntimeController` path, using the
built app's resources, reached Unreal `GameActivity` and remained alive for
45 seconds with empty crash logs. Global retained its signed-in session and
began patching; Vietnam and Taiwan displayed their content-download prompts.
This verifies installation and startup, not a complete match or performance.
The existing buffer-view-cache allowlist remains tied to the previously tested
18.1 APK and therefore falls back automatically on 18.2.

Repository validation passed in a clean source copy; the full tests, Swift
typecheck, ad-hoc app build, and nested code-signature verification passed.

Global, Vietnam, and Taiwan signed game feeds were published on 2026-09-10.
Each public manifest passed `HostedGameUpdate.decodeAndVerify`; all 12 public
APK downloads matched the tested sizes and SHA-256 hashes and had immutable
cache headers. The Sparkle appcast remained byte-for-byte unchanged.

## Active profile hashes

The retained profile identifiers are compatibility-sensitive because the
Shipping game command line selects `DeviceProfile=Android_Codex`.

```text
c9c84bec09e60d2ee965f91ef0b7b1eb687521527e478e3df5054f779137c42b  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.ini
3479ffb5482b7e8d79d04627de4ffe052d9f7b9078f4107a690a575db87bea99  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.shader-prewarm.ini
b0b83466abef72b1f7f751bf92e804abbd3f9a1aac02f502a5d979d40f2b71ef  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini
fe480214929c713f9e302bf9fde7abcb66d424979deae7e2c09b8c0428314ee9  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-ubo-direct-write.ini
1799397dd17f53462b306f3c9d564b05da645c228f0b660f5a0903c5932e9540  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-ubo-pool-16m.ini
b030063d912b9f2ad96b56ac8923cbba587ff6242abafcc82f6342fba922992d  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-fx-budget-2ms.ini
5691ec40a9a96b3ee0c238e9db2d70bb3e769ba30fad6f085ee0346adf934fc3  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-animation-budget-1ms.ini
740bf39d38004679fd1613c89b0398b73bf8a22712654a416aeefc48a1907026  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-actor-pool-warming.ini
7e411bb6c2a5bf18866d3864aa33185d8803ab25b24339ccca6177b039cc8f92  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-niagara-all-batches-async.ini
f26f101beeb4ec2a2f6aee41213a7821eb643704d9c35d578898e54892fc41d3  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-fx-early-schedule.ini
cf77b183bb4e62e69cad3437e1fcc08b46a1833f34dfcecf00f13f8e8e819859  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-niagara-batch-size-8.ini
10dfd8967f4b13d90ab93a4ce37500be153671f396469b4748538bdaeab186b2  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-parallel-dynamic-mesh.ini
7a82dd3a105beea7a50e96b91677b07c9b6bf9e5d207ed0ed20a9976965aac74  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-rhi-command-list.ini
2083f6bc5bbe53131eb192641194d35f71ef4feb9e890f725bf52ec1529b2b9d  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-gpu-scene-parallel-512.ini
7c3947b44bd7f7488786973b06c26cd06d312b3c43426b3417cb608c7c912668  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max-drag-tickless.ini
183d2196f3b79fdcff1d433480e803322c1b580bfaf117991e7229c2754002b5  artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.no-frame-ahead.ini
e92e08b1f1f62b463cdbb43a522929a1cee66145b1abcf7380749e16f93ff451  artifacts/tft-pbe-18.1-5212127-direct-vulkan/Android_Codex.DeviceProfiles.ini
```

Other experiment profiles remain in `artifacts/` and can be hashed directly
with `shasum -a 256`; documentation does not pin hashes for inactive files.

## Live-binary and synthetic-probe provenance

Static CVar conclusions in the 2026-08-15 artifacts use the exact
`libUnreal.so` copied from the running PBE process, SHA-256
`4edeb935c1e800c6846aac77d066d9895435d0e68e2d585937601484e7589822`.
`scripts/read-unreal-cvar-storage.command` refuses a mismatched binary hash and
reads named four-byte storage from the live process; startup push logs alone do
not prove that a candidate changed the effective value.

The separate UBO strategy screen is reproducible with:

```sh
./scripts/build-android-gles-ubo-stress-app.command
./scripts/run-android-gles-ubo-stress.command \
  control single_subdata 20 120 256 7
./scripts/summarize-android-gles-ubo-campaign.command \
  control-before.json candidate.json control-after.json
```

The curated 13-run artifact pins the APK, manifest, and Java source hashes,
requires guest ANGLE/Vulkan mapping, identical graphics flags and workload,
alternating controls, and zero GLES errors. It is a strategy-ranking
microbenchmark, not a TFT frame-rate result.

The same source hash is used by the capacity-sizing audit. Its byte counts are
derived from the attested 32-byte stride and the exact `bufferBytes = stride *
drawsPerFrame` implementation; they do not estimate TFT's live pool pressure.
The resulting 32 KiB measured maximum versus 16 MiB candidate ratio is checked
in `scripts/test-mactician.command` and retained in
[`artifacts/unreal-opengl-ubo-capacity-sizing-audit-20260815.json`](../artifacts/unreal-opengl-ubo-capacity-sizing-audit-20260815.json).

The final post-experiment rollback is also machine-readable. A cold stock
launch must recover any interrupted profile journal, see the original base APK
with zero base/profile bind mounts, and leave no emulator, ADB device, or AVD
lock after shutdown. Both AVD transport files must remain `pipe`. The retained
attestation is
[`artifacts/stock-rollback-validation-20260815.json`](../artifacts/stock-rollback-validation-20260815.json).

Exact-binary static audits, including the uniform-expression cache and
render-command-pipe elimination screen, are hash-bound to the copied live
`libUnreal.so`. They establish shipped defaults only and must not be treated as
frame-rate measurements. The latest record is
[`artifacts/unreal-uniform-command-pipeline-audit-20260815.json`](../artifacts/unreal-uniform-command-pipeline-audit-20260815.json).

When a registration default cannot be decoded statically, a one-CVar profile
can expose the effective pre-write value through Riot's startup transition.
The uniform-buffer-pooling query uses exactly one explicit CVar, pins the live
profile and log hashes, and records crash plus post-shutdown rollback state in
[`artifacts/unreal-uniform-buffer-pooling-runtime-audit-20260815.json`](../artifacts/unreal-uniform-buffer-pooling-runtime-audit-20260815.json).

## Three manifests/states

- **Source manifest:** the committed JSON records downloadable Android
  components, game split metadata, disk requirement, and UI launch profiles.
- **Release manifest:** the copy embedded in a built app. The build copies it
  byte-for-byte and verifies every private game input before packaging.
- **Runtime state:** `install-state.json` in Application Support records what was
  successfully installed on one Mac. It is mutable, private, and never a source
  of release hashes.

The runtime also generates effective AVD configuration, downloaded package
`source.properties`, overlay hashes, and rollback sidecars. Those values prove a
specific run; they are not committed build inputs.

## Verify an environment

```sh
./scripts/verify-repository.command
./scripts/test-mactician.command
./scripts/verify-environment.sh
./run-tft-best-verified.command --print-config
```

For an accepted benchmark, retain the effective display/density, graphics flags,
APK/profile/runtime hashes, power/thermal state, semantic before/after gates,
frame summary, and cleanup/rollback result. `--print-config` is read-only and
shows the recommended source profile without starting the emulator.

## Release verification

After building, compare the embedded manifest to the source, verify nested code
signatures, and hash the DMG:

```sh
cmp launcher/Resources/release-manifest.json \
  "dist/Mactician.app/Contents/Resources/release-manifest.json"
codesign --verify --deep --strict --verbose=2 "dist/Mactician.app"
shasum -a 256 "dist/Mactician-1.0.0.dmg"
```

A public build additionally requires the Developer ID authority, notarization
acceptance, and a stapled ticket. Rebuilding a DMG can change container bytes;
published versioned artifacts are therefore immutable rather than assumed to be
bit-for-bit reproducible across machines.
