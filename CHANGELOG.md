# Changelog

The current application metadata is version 1.1.3, build 48.

## Unreleased

### Changed

- Use Google's official Android 36 Google Play image for the managed emulator,
  keep Play Store applications and account data persistent, and launch the
  Vietnam TFT client when it is installed without requiring root-only overlays.
- Keep the managed Android device open when TFT closes so other installed apps
  remain available until the user explicitly stops the emulator.
- Support signed game releases for the official Vietnam TFT package while
  preserving the existing global package and rejecting unknown package IDs.
- Add an approximate DAU metric backed by at most one unlinkable
  `daily_active` event per retained preferences domain and UTC day. The event
  contains no stable identifier, and the server does not retain its source IP.
- Update the pinned live TFT game and signed update channel to
  `18.1-5392842`, which includes Riot's 18.1B performance fixes.
- Enable Riot's built-in Performance Mode with the **Maximum FPS** preset, and
  disable it again when another graphics-detail preset is selected.

## 1.1.3 — 2026-09-01

### Fixed

- Fix telemetry.

## 1.1.2 — 2026-09-01

### Changed

- Send an anonymous duration-only summary after every completed game session,
  without a stable identifier, device data, settings, or exact timestamps.
- Show the updated telemetry notice once without changing the saved Extended
  Diagnostics choice.
- Reduce background FPS-monitoring work during gameplay.

## 1.1.1 — 2026-08-31

### Changed

- Add a versioned, one-time activation snapshot after the explicit Extended
  Diagnostics choice is known, without game-session diagnostics or a stable
  installation identifier.
- Retry the same snapshot event until the telemetry backend acknowledges it,
  while keeping it independent from legacy first-session telemetry.

## 1.1.0 — 2026-08-27

### Changed

- Switch the bundled game channel to the live TFT `18.1-5388569` release.
- Remove test-client wording and use a dedicated live-game Android device. The
  channel switch requires one Riot sign-in.

## 1.0.8 — 2026-08-25

### Changed

- Add best-effort support for Apple Silicon Macs with 8 GB of unified memory by
  using a 4 GB Android guest during installation and gameplay; Macs with 16 GB
  or more retain the existing 6 GB default.

## 1.0.7 — 2026-08-22

### Fixed

- Restore the branded active-game Dock icon instead of showing the generic
  `qemu-system-aarch64` executable icon.

## 1.0.6 — 2026-08-20

### Changed

- Sign the launcher and bundled game host with Apple Developer ID, enable the
  hardened runtime, and notarize the release for standard Gatekeeper approval.

## 1.0.5 — 2026-08-15

### Added

- Add a reversible **Maximum FPS** graphics-detail preset that selects the
  audited 67% 3D-scale Performance Max profile from the app.

## 1.0.4 — 2026-08-14

### Fixed

- Restore four asynchronous OpenGL PSO compiler services when a TFT update
  disables them in its inherited Android device profile, avoiding first-use
  shader compilation stalls on the gameplay render path.

## 1.0.3 — 2026-08-14

### Changed

- Check the signed TFT PBE feed when the launcher becomes ready.
- Show **Update game** in place of **Play** only when a newer verified game
  version is available.
- Prevent starting a known-outdated game build until its update completes.

## 1.0.2 — 2026-08-13

### Fixed

- Check for Mactician updates on every launch instead of waiting only for the
  daily Sparkle schedule.
- Show an explicit localized result after a game update check, including the
  installed TFT PBE version when no newer hosted build is available.
- Record completed game update checks in the launcher log.

## 1.0.1 — 2026-08-13

### Added

- Added a separately signed TFT PBE update channel hosted on
  `sergeinaumov.dev`.
- Added in-place split APK updates that preserve Riot sign-in and local game
  data.

## 1.0.0 — 2026-08-10

### Added

- Initial public version of Mactician.

### Changed

- Restyled the active game Dock icon as a distinct Mactician play variant and
  replaced the Android Emulator title with `Mactician: TFT PBE`.
- Reduced Trial benchmark preparation from roughly 20 seconds to 1–3 seconds
  by overlapping one shop decision with combat and batching reward, XP, item,
  and replay actions.
- Preserved valid measurements across same-emulator Trial retries, added a
  bounded same-combat capture retry, and repaired early-exit cleanup after a
  launcher crash.
- Updated Performance Max with the confirmed 67% effects/LOD profile and a
  16 KiB ASG write step; repeated Trial 1-8 proxies remained above 30 FPS.
