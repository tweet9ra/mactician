# Troubleshooting

Use the launcher's recovery actions before manually changing AVD files. Keep
diagnostics narrow and sanitized.

## Installation does not complete

Check available disk space and Internet access, then retry. Partial component
downloads are resumable. **Repair Installation** rechecks the host, manifest,
component layout, hashes, runtime template, AVD, and game installation without
clearing an otherwise valid AVD.

The launcher log is under
`$HOME/Library/Application Support/Mactician/logs/launcher.log`.
Share only the small section around the error after removing home paths,
identifiers, and unrelated output.

## Component hash verification fails

Do not edit the expected hash. Remove only the named incomplete archive from
the launcher's `downloads/` directory and retry on a trusted network. A repeat
failure can mean an upstream archive changed; that requires a reviewed manifest
update, not a local bypass.

For build-time APK mismatches, confirm `TFT_GAME_APK_DIR` contains the exact
four pinned, unmodified splits listed in `release-manifest.json`.

## Emulator does not start

- Confirm the Mac is Apple Silicon, macOS is 12.0 or later, and Hypervisor
  Framework is available.
- Run `./scripts/verify-environment.sh` for the source-tree runtime.
- Set `TFT_ANDROID_SDK_ROOT`, `ANDROID_SDK_ROOT`, or `ANDROID_HOME` when the SDK
  is outside the standard macOS directory.
- Set `TFT_AVD_HOME` and `TFT_AVD_NAME` when using an external source-tree AVD.
- Use **Repair Installation** for missing launcher-managed components.
- Use **Reset** only when the launcher reports corrupted AVD state and preserving
  Riot/game state is less important than recreating the AVD.

## Another emulator process is running

Close other Android Emulator or PlayDroid/OSFT virtual machines before launch or
provisioning. The project isolates its ADB server on port 5038, but simultaneous
VMs still compete for host CPU/GPU and can mutate shared expectations. Do not
kill an unrelated process unless you have identified it.

## TFT restarts inside the AVD

The launcher keeps the verified APK and device-profile overlays mounted for the
whole AVD session so a Riot disconnect or TFT process restart retains the
selected graphics path. UI scale and game locale are applied during launcher
startup; if an independent restart does not retain the intended presentation,
close the emulator and press Play again.

## Hotkeys do not work

Grant Accessibility permission to **Mactician**, not the emulator, in
System Settings. The bridge retries after permission is granted. Hotkeys are
deliberately inactive outside TFT's exact `GameActivity`; the official Riot
login WebView and unknown activities pass input through unchanged.

## A white haze appears after pressing Space

Without the hotkey bridge, a physical key can focus the full-screen Android
container above Unreal's game surface. AppCompat then draws its white focus
ripple over the game. The haze disappears in Android Recents while the window
is unfocused, and returns when the game regains focus.

Before starting TFT, the runtime replaces only the game's native Android ripple
color with a transparent resource overlay. This also removes native Android
button ripples inside TFT; Unreal visuals and the Riot login WebView's HTML
styles are unaffected. The protection works without macOS Accessibility access.
It is reapplied at launch because fabricated overlays may be cleared on reboot.
Never apply resource changes during a match: Android may restart the app.

## Repair versus Reset

**Repair Installation** preserves the AVD, Riot sign-in, game assets, and
preferences while re-verifying and refreshing launcher-owned pieces.

**Reset** removes the entire Application Support directory, including the AVD,
Riot sign-in, game data, downloads, state, and logs. It cannot be undone by the
launcher.

## Streaming-install cache is damaged

An interrupted public asset download can leave a zero-byte
`StreamingInstalls/Metadata.manifest`. The runtime detects exactly this case and
removes only `StreamingInstalls` so TFT can download public assets again. It
does not clear Riot sign-in or other app data. Use Repair to refresh this logic
on an existing installation.

## Pinned game version does not match

The launcher intentionally refuses to mount an OpenGL overlay over an unknown
`base.apk`. Install a launcher release built for the new TFT version. Do not
replace hashes or patch the installed APK to force compatibility.

## Update check fails

Confirm Internet access and system time, then retry **Check for Updates…**. Do
not disable Ed25519 verification or replace the appcast URL. If the feed is
temporarily unavailable, the installed launcher remains usable; updates are not
automatic without confirmation.

## Safe diagnostics

Prefer launcher status, `wm size`, `wm density`, filtered process lists,
`dumpsys input`, `dumpsys display`, `dumpsys gfxinfo`, and short, purpose-built
captures. Never post complete game logs, AVD images, `/data/anr` archives,
Keychain output, cookies, tokens, credentials, or unfiltered crash memory.
