# Vietnam (VNG) edition

Settings offers Global, Vietnam (VNG), and [Taiwan](taiwan.md), remembers the last
selection, and defaults to Global. Selecting an uninstalled edition downloads it when the
shared Android runtime is already present. A fresh setup still requires the
Android SDK license step. Game language remains an independent setting.

Vietnam is a separate Android application,
[`com.riotgames.league.teamfighttacticsvn`](https://play.google.com/store/apps/details?id=com.riotgames.league.teamfighttacticsvn).
Both packages coexist in `Tft.avd` and retain separate sign-ins, files, caches,
and updates. Switching is disabled until installation, stopping, or gameplay
finishes. Reset removes all editions and the shared runtime.

## Verified release input

Prepared on 2026-10-08 from the APKPure `18.4-5637330` ARM64 XAPK
([source](https://d.apkpure.net/b/XAPK/com.riotgames.league.teamfighttacticsvn?version=latest)).
Android manifest metadata confirms version code `8637330`.
Official Android Build Tools 36 verified the cryptographic signatures, package
IDs, split IDs, and matching version codes of all four APKs. All use the pinned
Riot certificate SHA-256:

```text
931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c
```

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| base.apk | 113017143 | fe37e7fbcdf68c6d74a97ecf1159bb678a1beff902c622cd8b95539b2bcf3abc |
| config.arm64_v8a.apk | 95139041 | 624143e86e669717e993eef6d504ad1ba0062a7029c74091fca424f1298a5580 |
| config.en.apk | 37273 | 61154b649700d41c5a38ba9724c4ce059fd9cf706901f5b44c0179f2903be6a7 |
| config.mdpi.apk | 83007 | 005ceca1e6774febfa97eaa28bd32b7610d409f6168bd45e0fdbea36975b27a3 |

The four private inputs live in `private/tft-vietnam-apks/`. The signed update
feed is generated with `MACTICIAN_GAME_EDITION=vietnam`; see
[the release procedure](releasing.md#publish-a-tft-game-update).

## Distribution

The VNG channel was published on 2026-09-05 with TFT `18.1-5423749`.
The existing Global feed and launcher appcast were unchanged. Existing launcher
releases continue using Global; the edition selector requires the new build.

Global keeps its bundled APKs and existing feed URL. Vietnam is downloaded on
demand and has no bundled Global fallback. Its feed uses the same pinned game
update signing key and the path `/mactician/updates/game/vietnam/manifest.json`.
APK paths are `/mactician/updates/game/vietnam/releases/<baseSHA256>/<filename>`.
Publish this signed feed and its APKs before distributing the new launcher.
Preparation alone does not make the VNG download available to users.

The first game launch separately requests its own content download (about
4.2 GB for TFT 18.2 in the startup check), then its own sign-in. The launcher’s APK download size
does not include that content. No credentials transfer between editions.

## Initial validation (TFT 18.1)

Unit tests cover schema 1 migration to Global, schema 2 round trips with both
editions, edition selection defaults, signed cross-edition feed rejection,
exact APK URL validation, downgrade rejection, and isolated cache/overlay paths.
Runtime lifecycle fixtures exercise process polling for both Android packages.

A test copy of an existing Global AVD was used to install VNG with the production
installer. Both per-game state records survived. VNG reached Unreal GameActivity,
stayed alive for more than 25 seconds, and displayed its content-download prompt
in the selected English language with an empty crash log. Switching back to Global
and launching it from the new UI also reached GameActivity with no crash records.
The selector was disabled during gameplay and re-enabled after stopping.
Account sign-in and a
full match are separate manual checks; neither is implied by this startup test.

## TFT 18.2 validation — 2026-09-10

The four verified APKs upgraded the existing 18.1 package in an isolated AVD
copy with unchanged `firstInstallTime`. The normal Mactician runtime reached
Unreal `GameActivity`, remained alive for 45 seconds with an empty crash log,
and displayed the English content-download prompt (4,175.8 MB). Account sign-in
and a full match were not tested.

The 18.2 signed game feed was published on 2026-09-10. The public manifest
passed the launcher's signature verification, and all four downloaded APKs
matched the tested sizes and SHA-256 hashes with immutable cache headers.
The launcher appcast was unchanged.

## TFT 18.4 validation — 2026-10-08

The four verified APKs passed the upgrade and 35-second startup checks in a
read-only AVD session with unchanged `firstInstallTime` and no crash records.
See [the shared validation record](reproducibility.md#tft-184-5637330-validation--2026-10-08)
for the source-bundle hash, test setup, and limits.

The signed 18.4 feed was published on 2026-10-08. Its public signature and all
four APK downloads passed the size/hash checks with immutable cache headers.
