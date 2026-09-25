# Changelog

The current application metadata is version 1.2.5, build 54.

## Unreleased

Planned for 1.3.0: the validated Global Vulkan buffer-view cache.

## 1.2.5 — 2026-09-25

- Classify performance samples from bounded game-log reads instead of screenshot
  OCR, independent of game language and display resolution.
- Report recent lobby, matchmaking, match-starting and match activity separately;
  preserve unknown context when signals are stale, missing or inconsistent.
- Keep coarse match activity separate from verified combat/planning and numeric
  stages. Raw game logs and account details are never saved or uploaded.
- Preserve game inputs, graphics profiles and the sampling duty budget while
  establishing a baseline for later performance updates.

## 1.2.4 — 2026-09-14

- Test a passive game-log source alongside screenshot performance diagnostics.
  Record only predefined event categories, freshness and read-cost counters.
- Handle unavailable, replaced and stale game logs without changing frame labels.
- Keep unknown samples excluded from gameplay eligibility while evaluating the
  incomplete lifecycle and GC-departure signals.

## 1.2.3 — 2026-09-11

- Explain performance-sample losses with bounded diagnostics for captures,
  recognition, scene transitions, frame collection, and collector timings.
- Record the requested game language and screenshot-size category to diagnose
  coverage gaps. Screenshots and recognized text stay on the Mac.
- Preserve the existing scene classifier, measurement cadence, and game runtime
  while collecting a diagnostic baseline.

## 1.2.2 — 2026-09-09

### Changed

- Select Maximum FPS once on the first launch after updating, then preserve
  the player's subsequent choice. New installations also start with Maximum FPS.
- Remove the Performance detail preset; keep High and Maximum FPS.
- Route the Donate button through the website to count donation-page visits.

## 1.2.1 — 2026-09-09

### Changed

- Refresh the launcher with a larger title, dark ribbon artwork, a compact
  Play / Settings card, and a dedicated support and feedback panel.
- Apply the same visual style to installation, launch, running and error screens.
- Move game edition and resolution controls into the existing Settings window.
- Remove the header settings icon; open Settings from each state card or with ⌘,.
- Keep long screens scrollable and button labels readable in English and Russian.

## 1.2.0 — 2026-09-08

### Added

- Persistent Global / Vietnam (VNG) selection with independent updates and sign-ins.
- Feedback-board and Lava donation links in the launcher.
- Performance telemetry for all users, independently of optional diagnostics,
  including sampled frame times, launch outcomes and coarse scenes processed locally.

### Changed

- Bundle the pinned live TFT 18.1-5423749 split APK set.

### Fixed

- Reapply Riot's session-persistence setting before each launch.
- Honor an immediate Stop before the Android runtime child has been assigned.

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
