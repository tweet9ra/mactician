# Releasing

The current metadata is Mactician version 1.1.3, build 48. Version and build
numbers live in `launcher/Info.plist` and the matching emulator-host plist.
Release notes live under `launcher/Resources/release-notes/` using the short
version as the filename.

## Release identity

Do not casually change:

- app bundle ID `dev.sergeinaumov.mactician`;
- game-host bundle ID `dev.sergeinaumov.mactician.game-host`;
- app name and executable `Mactician`;
- Application Support and DMG volume name `Mactician`;
- Sparkle feed `https://sergeinaumov.dev/mactician/updates/appcast.xml`;
- pinned Sparkle Ed25519 public key in `launcher/Info.plist`;
- UserDefaults domain and Keychain service `dev.sergeinaumov.mactician`;
- supported Android package IDs, release-manifest hashes, or the
  `Android_Codex` device profile identifier.

These are the only current product identifiers. No old feed, local-data path,
redirect, alias, or compatibility wrapper is part of the release.

## Prepare metadata

1. Update `CFBundleShortVersionString` and monotonically increase
   `CFBundleVersion` in both plist files.
2. Add matching Markdown release notes.
3. Update the `Unreleased` section in `CHANGELOG.md`.
4. Update the release manifest only when a pinned Android/game input changes;
   verify size, origin, and hash independently.
5. Run the full fast validation and review `git diff --check`.

## Build the public artifact

```sh
./scripts/build-mactician-release.command
```

The release wrapper uses the pinned APK directory, automatically selects the
installed Developer ID Application identity, enables hardened runtime and
secure timestamps, submits the DMG for Apple notarization, staples both the DMG
and app tickets, and runs the final Gatekeeper checks. No production upload
occurs in this step. Use `build-mactician.command` directly only for a local
ad-hoc validation build.

Keep the notarization profile, Developer ID private key, Apple credentials, and
Sparkle private Ed25519 key in Keychain. Never pass secret values as committed
arguments or defaults.

## Generate the appcast

Exercise generation without upload:

```sh
: "${MACTICIAN_SPARKLE_ACCOUNT:?Set MACTICIAN_SPARKLE_ACCOUNT in the environment}"
./scripts/publish-mactician-update.command --prepare-only
```

This copies the DMG and release notes to versioned names, generates Ed25519
enclosure signatures and deltas, validates XML, and requires an `edSignature`.
Prepare-only never uploads files.

## Publish

Production-specific destinations have no secret or machine-specific defaults:

```sh
: "${MACTICIAN_SPARKLE_ACCOUNT:?Set MACTICIAN_SPARKLE_ACCOUNT in the environment}"
: "${MACTICIAN_UPDATE_SSH_TARGET:?Set MACTICIAN_UPDATE_SSH_TARGET in the environment}"
: "${MACTICIAN_UPDATE_SSH_PORT:?Set MACTICIAN_UPDATE_SSH_PORT in the environment}"
: "${MACTICIAN_UPDATE_REMOTE_ROOT:?Set MACTICIAN_UPDATE_REMOTE_ROOT in the environment}"
./scripts/publish-mactician-update.command
```

Optional public settings are `MACTICIAN_UPDATE_BASE_URL`,
`MACTICIAN_UPDATE_PRODUCT_URL`, `MACTICIAN_UPDATE_WORKDIR`, `MACTICIAN_APP`,
`MACTICIAN_DMG`, and `MACTICIAN_RELEASE_NOTES`.

The publisher verifies the Developer ID app and stapled DMG, uploads immutable
artifacts for the current version and its deltas, uploads the next appcast under
a temporary name, then atomically moves the appcast into place last. Older
release files remain untouched on the server. Never overwrite a published
versioned DMG with different bytes.

`--allow-adhoc` is reserved for an explicitly approved temporary release. It
accepts only a valid ad-hoc-signed app, verifies the DMG, and still requires the
Sparkle Ed25519 signature.

## Publish a TFT game update

Game releases use a separate signed manifest and do not require a new Mactician
build. Put the complete official split APK set in one directory and run:

```sh
: "${MACTICIAN_GAME_APK_DIR:?Set the split APK directory}"
: "${MACTICIAN_GAME_VERSION:?Set the Android version name}"
: "${MACTICIAN_GAME_VERSION_CODE:?Set the Android version code}"
./scripts/publish-game-update.command --prepare-only
```

Review the generated payload and APK hashes. To publish, set
`MACTICIAN_UPDATE_SSH_TARGET` and `MACTICIAN_UPDATE_REMOTE_ROOT`, then rerun
without `--prepare-only`. `MACTICIAN_GAME_SIGNING_ACCOUNT` defaults to the
dedicated `mactician-game-updates` Keychain account.

The publisher defaults to the global TFT package. Set
`MACTICIAN_GAME_PACKAGE=com.riotgames.league.teamfighttacticsvn` when preparing
an official Vietnam release. Only the global and Vietnam package identifiers
are accepted.

The publisher uploads immutable APK files before atomically replacing the
signed `game/manifest.json`. Never publish an incomplete split set, reuse a
release URL for different bytes, or roll the version code backwards.

## Make the repository public

The canonical repository is `https://github.com/tweet9ra/mactician`. Before
changing its visibility, run `./scripts/verify-repository.command`, the complete
test suite, and the secret/history scan on the exact commit that will become
public. Confirm that the repository contains no ignored build inputs, release
artifacts, credentials, signing material, or local experiment output.

Apply the description, homepage, topics, and social preview recorded in
`.github/repository-metadata.yml`. Enable Issues and GitHub Private Vulnerability
Reporting, then verify the public Source, Issues, Security, and Releases pages in
a signed-out browser. Protect the default branch against force pushes once the
initial public commit is final.

Create an immutable `v1.0.0` tag and GitHub release only after the corresponding
DMG and release notes are final. Publish the SHA-256 shown on the product page
with the release, upload the self-hosted Sparkle files, and publish the appcast
last. Repository settings, visibility changes, tags, releases, and uploads are
separate external actions.

## Validation and rollback

Before announcing a release, install the DMG on another supported Mac, verify
Gatekeeper assessment, install/update flow, Sparkle signature verification,
runtime-state preservation, first launch, Repair, stop/rollback, and a manual
update check.

If a release is defective, stop advertising it or publish a higher, fixed
version. Do not reuse a version/build number or rotate the Ed25519 key as an
incident shortcut. A compromised private key requires an explicit security
response.
