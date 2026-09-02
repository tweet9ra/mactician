import AppKit
import CryptoKit
import Foundation

@main
enum LauncherTests {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw TestFailure("usage: LauncherTests MANIFEST SOURCE_ROOT")
        }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceRoot = URL(fileURLWithPath: CommandLine.arguments[2])
        let manifest = try SystemServices.loadManifest(from: manifestURL)

        try expect(manifest.schemaVersion == 1, "manifest schema")
        try expect(manifest.components.count == 3, "component count")
        try expect(manifest.game.apks.count == 4, "APK count")
        let hostedPrivateKey = Curve25519.Signing.PrivateKey()
        let hostedRelease = GameRelease(
            packageName: "com.riotgames.league.teamfighttactics",
            version: "18.2-test",
            versionCode: 8_220_001,
            baseSHA256: String(repeating: "a", count: 64),
            apks: [
                GameAPK(
                    name: "base.apk",
                    size: 100,
                    sha256: String(repeating: "a", count: 64),
                    url: URL(string: "https://sergeinaumov.dev/mactician/updates/game/releases/aaaaaaaa/base.apk")
                ),
                GameAPK(
                    name: "split_config.arm64_v8a.apk",
                    size: 50,
                    sha256: String(repeating: "b", count: 64),
                    url: URL(string: "https://sergeinaumov.dev/mactician/updates/game/releases/aaaaaaaa/split_config.arm64_v8a.apk")
                )
            ]
        )
        let hostedPayload = try JSONEncoder().encode(HostedGameFeed(
            schemaVersion: 1,
            publishedAt: "2026-08-12T12:00:00Z",
            release: hostedRelease
        ))
        let hostedSignature = try hostedPrivateKey.signature(for: hostedPayload)
        let hostedEnvelope = try JSONEncoder().encode(HostedGameFeedEnvelope(
            schemaVersion: 1,
            payload: hostedPayload.base64EncodedString(),
            signature: hostedSignature.base64EncodedString()
        ))
        let verifiedHostedFeed = try HostedGameUpdate.decodeAndVerify(
            hostedEnvelope,
            publicKeyBase64: hostedPrivateKey.publicKey.rawRepresentation.base64EncodedString()
        )
        try expect(verifiedHostedFeed.release == hostedRelease, "signed hosted game feed")
        let vietnamRelease = GameRelease(
            packageName: GameRelease.vietnamPackageName,
            version: hostedRelease.version,
            versionCode: hostedRelease.versionCode,
            baseSHA256: hostedRelease.baseSHA256,
            apks: hostedRelease.apks
        )
        try vietnamRelease.validate()
        try expect(
            GameRelease.supportedPackageNames == Set([
                GameRelease.globalPackageName,
                GameRelease.vietnamPackageName
            ]),
            "global and Vietnam TFT package validation"
        )
        let unknownPackageRelease = GameRelease(
            packageName: "com.example.teamfighttactics",
            version: hostedRelease.version,
            versionCode: hostedRelease.versionCode,
            baseSHA256: hostedRelease.baseSHA256,
            apks: hostedRelease.apks
        )
        do {
            try unknownPackageRelease.validate()
            throw TestFailure("unknown TFT package accepted")
        } catch is LauncherError {
            // Expected.
        }
        var olderInstallState = InstallState()
        olderInstallState.gameVersion = "18.1-old"
        olderInstallState.gameVersionCode = 8_210_000
        try expect(
            HostedGameUpdate.isNewer(hostedRelease, than: olderInstallState),
            "newer hosted game version detection"
        )
        var currentInstallState = olderInstallState
        currentInstallState.gamePackageName = hostedRelease.packageName
        currentInstallState.gameVersion = hostedRelease.version
        currentInstallState.gameVersionCode = hostedRelease.versionCode
        try expect(
            !HostedGameUpdate.isNewer(hostedRelease, than: currentInstallState),
            "current hosted game version detection"
        )
        try expect(
            HostedGameUpdate.isNewer(vietnamRelease, than: currentInstallState),
            "Vietnam package switch is detected even at the same version"
        )
        var newerInstallState = currentInstallState
        newerInstallState.gameVersionCode = 8_230_000
        try expect(
            !HostedGameUpdate.isNewer(hostedRelease, than: newerInstallState),
            "hosted game rollback is not an update"
        )
        var invalidSignature = hostedSignature
        invalidSignature[invalidSignature.startIndex] ^= 0x01
        let invalidEnvelope = try JSONEncoder().encode(HostedGameFeedEnvelope(
            schemaVersion: 1,
            payload: hostedPayload.base64EncodedString(),
            signature: invalidSignature.base64EncodedString()
        ))
        do {
            _ = try HostedGameUpdate.decodeAndVerify(
                invalidEnvelope,
                publicKeyBase64: hostedPrivateKey.publicKey.rawRepresentation.base64EncodedString()
            )
            throw TestFailure("tampered hosted game feed was accepted")
        } catch let error as LauncherError {
            try expect(error == .integrity("The TFT feed signature is invalid"), "tampered game feed rejection")
        }
        try expect(
            manifest.profiles.map(\.id) == ["balanced", "quality", "ultra", "4k"],
            "profile order"
        )
        try expect(
            manifest.profiles.map(\.title) == ["1080p", "1440p", "1800p", "4K"],
            "resolution profile titles"
        )
        try expect(
            EffectsQuality.selection(saved: nil) == .high
                && EffectsQuality.selection(saved: "unknown") == .high
                && EffectsQuality.selection(saved: "performance") == .performance
                && EffectsQuality.selection(saved: "maximum") == .maximum
                && EffectsQuality.maximum.profileFilename
                    == "Android_Codex.DeviceProfiles.performance-max.ini",
            "effects quality selection"
        )
        try expect(manifest.profiles[0].displaySize == "1920x1080", "balanced resolution")
        try expect(manifest.profiles[0].displayResolution == "1920 × 1080", "display resolution formatting")
        try expect(manifest.profiles[1].displaySize == "2560x1440", "quality resolution")
        try expect(manifest.profiles[2].displaySize == "3200x1800", "ultra resolution")
        try expect(manifest.profiles[2].density == 520, "ultra density")
        try expect(manifest.profiles[3].displaySize == "3840x2160", "4K resolution")
        try expect(manifest.profiles[3].density == 640, "4K density")
        try expect(
            BridgeHotkeyTarget.shop == BridgeRelativePoint(x: 0.96, y: 0.93)
                && BridgeHotkeyTarget.shop.pixels(width: 3840, height: 2160)
                == (3686, 2009),
            "shop hotkey touch target"
        )
        try expect(
            BridgeHotkeyTarget.reroll == BridgeRelativePoint(x: 0.955, y: 0.79)
                && BridgeHotkeyTarget.reroll.pixels(width: 3840, height: 2160)
                == (3667, 1706),
            "reroll hotkey touch target"
        )
        try expect(
            BridgeHotkeyTarget.buyXP == BridgeRelativePoint(x: 0.032, y: 0.925)
                && BridgeHotkeyTarget.buyXP.pixels(width: 3840, height: 2160)
                == (123, 1998),
            "XP hotkey touch target"
        )
        try expect(
            BridgeKeyboardBinding.isActionKey(BridgeKeyboardBinding.tab)
                && BridgeHotkeyTarget.traits.pixels(width: 3840, height: 2160) == (111, 86)
                && BridgeHotkeyTarget.items.pixels(width: 3840, height: 2160) == (227, 86),
            "Tab items-and-traits hotkey touch targets"
        )
        try expect(
            BridgeKeyboardBinding.isActionKey(BridgeKeyboardBinding.playersAndDamage)
                && BridgeHotkeyTarget.damage.pixels(width: 3840, height: 2160) == (3636, 86)
                && BridgeHotkeyTarget.players.pixels(width: 3840, height: 2160) == (3744, 86),
            "V players-and-damage hotkey touch targets"
        )
        let surfaceLayer = """
            RequestedLayerState{SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity](BLAST)#103 parentId=102}
            """
        try expect(
            SurfaceFlingerFPS.gameLayer(
                from: surfaceLayer,
                package: "com.riotgames.league.teamfighttactics"
            ) == "SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity](BLAST)#103",
            "FPS overlay SurfaceFlinger layer selection"
        )
        let latencyOutput = """
            16666666
            0 1000000000 0
            0 1016666667 0
            0 1033333334 0
            0 1050000001 0
            """
        let frameRate = SurfaceFlingerFPS.estimate(
            timestamps: SurfaceFlingerFPS.presentationTimestamps(from: latencyOutput),
            after: nil
        )
        try expect(
            frameRate.map { abs($0.framesPerSecond - 60) < 0.1 } == true
                && frameRate?.newestTimestamp == 1_050_000_001,
            "FPS overlay frame-rate calculation"
        )
        var gameSessionTracker = GameSessionTracker()
        let gameSessionStart = Date(timeIntervalSince1970: 1_000)
        gameSessionTracker.start(at: gameSessionStart)
        gameSessionTracker.start(at: gameSessionStart.addingTimeInterval(30))
        try expect(
            gameSessionTracker.finish(
                at: gameSessionStart.addingTimeInterval(90.9)
            ) == 90
                && gameSessionTracker.finish(at: gameSessionStart.addingTimeInterval(100)) == nil,
            "game session duration is recorded once from the first ready event"
        )
        var shortGameSession = GameSessionTracker()
        shortGameSession.start(at: gameSessionStart)
        try expect(
            shortGameSession.finish(at: gameSessionStart.addingTimeInterval(0.2)) == 1,
            "short game sessions meet the telemetry minimum"
        )
        let telemetrySettings = LauncherTelemetrySettings(
            profile: manifest.profiles[1],
            effectsQuality: .performance,
            uiScalePercent: 125,
            androidMemoryMB: 8_192,
            androidCPUCores: 6
        )
        let telemetryDevice = LauncherTelemetryDevice(
            modelIdentifier: "Mac16,1",
            macOSVersion: "26.0.0",
            physicalMemoryMB: 32_768,
            logicalCPUCount: 10
        )
        try expect(
            LauncherTelemetryDevice.normalizedModelIdentifier("Mac16,1") == "Mac16,1"
                && LauncherTelemetryDevice.normalizedModelIdentifier("Mac name") == "unknown",
            "telemetry device model identifier is bounded"
        )
        let currentUTCDay = String(ISO8601DateFormatter().string(from: Date()).prefix(10))

        let dailyDefaultsName = "LauncherTests.daily-active.\(UUID().uuidString)"
        guard let dailyDefaults = UserDefaults(suiteName: dailyDefaultsName) else {
            throw TestFailure("daily-active UserDefaults suite")
        }
        defer { dailyDefaults.removePersistentDomain(forName: dailyDefaultsName) }
        dailyDefaults.set(true, forKey: "telemetry.noticeShown.v3")
        dailyDefaults.set("denied", forKey: "telemetry.extendedConsent.state.v1")
        dailyDefaults.set(1, forKey: "telemetry.extendedConsent.version.v1")
        dailyDefaults.set(true, forKey: "telemetry.firstSession.completed.v2")
        dailyDefaults.set(true, forKey: "telemetry.activationSnapshot.completed.v1")
        let dailyLoader = TelemetryLoaderStub()
        let dailyService = LauncherTelemetryService(
            defaults: dailyDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: dailyLoader.load
        )
        try waitFor("daily-active request") { dailyLoader.requestCount == 1 }
        guard let dailyEvent = dailyLoader.event(at: 0),
              let dailyEventID = dailyEvent["event_id"] as? String,
              let activeDay = dailyEvent["occurred_on"] as? String else {
            throw TestFailure("daily-active payload")
        }
        try expect(
            dailyEvent["event"] as? String == "daily_active"
                && activeDay.range(
                    of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#,
                    options: .regularExpression
                ) != nil
                && Set(dailyEvent.keys) == Set([
                    "schema_version", "event_id", "event", "occurred_on",
                    "launcher_version", "launcher_build"
                ])
                && dailyDefaults.string(
                    forKey: "telemetry.dailyActive.lastCreatedDay.v1"
                ) == activeDay,
            "daily-active payload is unlinkable and created once per UTC day"
        )
        dailyLoader.completeFirst(statusCode: 503)
        withExtendedLifetime(dailyService) {}
        let dailyRetryLoader = TelemetryLoaderStub()
        let dailyRetryService = LauncherTelemetryService(
            defaults: dailyDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: dailyRetryLoader.load
        )
        try waitFor("daily-active retry") { dailyRetryLoader.requestCount == 1 }
        try expect(
            dailyRetryLoader.event(at: 0)?["event_id"] as? String == dailyEventID,
            "daily-active retry preserves its event ID"
        )
        dailyRetryLoader.completeFirst(statusCode: 202)
        try waitFor("daily-active completion") {
            dailyDefaults.data(forKey: "telemetry.dailyActive.pendingEvents.v1") == nil
        }
        withExtendedLifetime(dailyRetryService) {}
        let sameDayLoader = TelemetryLoaderStub()
        let sameDayService = LauncherTelemetryService(
            defaults: dailyDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: sameDayLoader.load
        )
        sameDayService.completeNotice(extendedDiagnostics: false)
        try expect(
            sameDayLoader.requestCount == 0,
            "daily-active event is not recreated on the same UTC day"
        )

        let telemetryDefaultsName = "LauncherTests.telemetry.\(UUID().uuidString)"
        guard let telemetryDefaults = UserDefaults(suiteName: telemetryDefaultsName) else {
            throw TestFailure("telemetry UserDefaults suite")
        }
        defer { telemetryDefaults.removePersistentDomain(forName: telemetryDefaultsName) }
        telemetryDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        telemetryDefaults.set(UUID().uuidString, forKey: "telemetry.installationID.v1")
        telemetryDefaults.set(Data("[]".utf8), forKey: "telemetry.pendingEvents.v1")
        telemetryDefaults.set(true, forKey: "telemetry.activationSnapshot.completed.v1")
        let telemetryLoader = TelemetryLoaderStub()
        let telemetryService = LauncherTelemetryService(
            defaults: telemetryDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: telemetryLoader.load
        )
        try expect(
            telemetryService.shouldShowNotice
                && !telemetryService.isExtendedDiagnosticsEnabled
                && telemetryDefaults.object(forKey: "telemetry.installationID.v1") == nil
                && telemetryDefaults.object(forKey: "telemetry.pendingEvents.v1") == nil,
            "legacy telemetry is removed and extended diagnostics default to off"
        )
        telemetryService.completeNotice(extendedDiagnostics: false)
        telemetryService.recordGameSession(
            durationSeconds: 90,
            launcherSettings: telemetrySettings,
            endedAt: gameSessionStart.addingTimeInterval(90)
        )
        guard let pendingEventData = telemetryDefaults.data(
                forKey: "telemetry.firstSession.pending.v2"
              ),
              let pendingWrapper = try JSONSerialization.jsonObject(with: pendingEventData)
                as? [String: Any],
              let pendingEvent = pendingWrapper["event"] as? [String: Any],
              let firstEventID = pendingEvent["event_id"] as? String else {
            throw TestFailure("first-session telemetry payload")
        }
        guard let summaryData = telemetryDefaults.data(
                forKey: "telemetry.sessionSummary.pendingEvents.v2"
              ),
              let summaryEvents = try JSONSerialization.jsonObject(with: summaryData)
                as? [[String: Any]],
              let summaryEvent = summaryEvents.first else {
            throw TestFailure("anonymous session-summary payload")
        }
        try expect(
            (pendingEvent["schema_version"] as? NSNumber)?.intValue == 2
                && pendingEvent["event"] as? String == "first_game_session"
                && pendingEvent["occurred_on"] as? String == "1970-01-01"
                && pendingEvent["duration_bucket"] as? String == "under_5m"
                && Set(pendingEvent.keys) == Set([
                    "schema_version", "event_id", "event", "occurred_on",
                    "duration_bucket", "launcher_version", "launcher_build"
                ])
                && telemetryDefaults.data(forKey: "telemetry.extended.pendingEvents.v2") == nil,
            "first-session telemetry is minimized and contains only allowed fields"
        )
        try expect(
            summaryEvents.count == 1
                && (summaryEvent["schema_version"] as? NSNumber)?.intValue == 2
                && summaryEvent["event"] as? String == "game_session_summary"
                && (summaryEvent["duration_seconds"] as? NSNumber)?.int64Value == 90
                && Set(summaryEvent.keys) == Set([
                    "schema_version", "event_id", "event", "duration_seconds",
                    "launcher_version", "launcher_build"
                ]),
            "every session creates an unlinkable duration-only summary"
        )
        telemetryService.recordGameSession(
            durationSeconds: 3_700,
            launcherSettings: telemetrySettings
        )
        guard let repeatedPendingData = telemetryDefaults.data(
                forKey: "telemetry.firstSession.pending.v2"
              ),
              let repeatedWrapper = try JSONSerialization.jsonObject(with: repeatedPendingData)
                as? [String: Any],
              let repeatedEvent = repeatedWrapper["event"] as? [String: Any] else {
            throw TestFailure("repeated first-session telemetry payload")
        }
        try expect(
            repeatedEvent["event_id"] as? String == firstEventID,
            "later sessions reuse the single pending first-session event"
        )
        guard let repeatedSummaryData = telemetryDefaults.data(
                forKey: "telemetry.sessionSummary.pendingEvents.v2"
              ),
              let repeatedSummaries = try JSONSerialization.jsonObject(
                with: repeatedSummaryData
              ) as? [[String: Any]] else {
            throw TestFailure("repeated anonymous session-summary payload")
        }
        try expect(
            repeatedSummaries.compactMap {
                ($0["duration_seconds"] as? NSNumber)?.int64Value
            } == [90, 3_700],
            "every completed session is queued independently of diagnostics consent"
        )
        try expect(
            LauncherTelemetryService.durationBucket(for: 299) == "under_5m"
                && LauncherTelemetryService.durationBucket(for: 300) == "5_15m"
                && LauncherTelemetryService.durationBucket(for: 3_600) == "60_120m"
                && LauncherTelemetryService.durationBucket(for: 14_400) == "120_240m"
                && LauncherTelemetryService.durationBucket(for: 14_401) == "over_240m",
            "telemetry duration buckets"
        )
        try waitFor("initial telemetry request") { telemetryLoader.requestCount == 1 }
        telemetryLoader.completeFirst(statusCode: 503)
        let retryLoader = TelemetryLoaderStub()
        let retryService = LauncherTelemetryService(
            defaults: telemetryDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: retryLoader.load
        )
        try waitFor("retried telemetry request") { retryLoader.requestCount == 1 }
        try expect(
            retryLoader.firstEventID == firstEventID,
            "network retry preserves the first-session event ID"
        )
        retryLoader.completeFirst(statusCode: 202)
        try waitFor("successful first-session completion") {
            telemetryDefaults.bool(forKey: "telemetry.firstSession.completed.v2")
                && telemetryDefaults.data(forKey: "telemetry.firstSession.pending.v2") == nil
        }
        try waitFor("anonymous session summary after first-session completion") {
            retryLoader.requestCount == 2
        }
        retryService.recordGameSession(
            durationSeconds: 180,
            launcherSettings: telemetrySettings
        )
        try expect(
            retryLoader.requestCount == 2
                && retryLoader.event(at: 1)?["event"] as? String == "game_session_summary"
                && telemetryDefaults.data(forKey: "telemetry.firstSession.pending.v2") == nil,
            "completed one-time telemetry is not recreated while session summaries continue"
        )

        let upgradedDefaultsName = "LauncherTests.upgradedTelemetry.\(UUID().uuidString)"
        guard let upgradedDefaults = UserDefaults(suiteName: upgradedDefaultsName) else {
            throw TestFailure("upgraded telemetry UserDefaults suite")
        }
        defer { upgradedDefaults.removePersistentDomain(forName: upgradedDefaultsName) }
        upgradedDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        upgradedDefaults.set(true, forKey: "telemetry.firstSession.completed.v2")
        let upgradedLoader = TelemetryLoaderStub()
        let upgradedService = LauncherTelemetryService(
            defaults: upgradedDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: upgradedLoader.load
        )
        upgradedService.recordGameSession(
            durationSeconds: 180,
            launcherSettings: telemetrySettings,
            endedAt: gameSessionStart.addingTimeInterval(180)
        )
        try waitFor("anonymous summary with unknown diagnostics consent") {
            upgradedLoader.requestCount == 1
        }
        try expect(
            upgradedLoader.event(at: 0)?["event"] as? String == "game_session_summary"
                && (upgradedLoader.event(at: 0)?["duration_seconds"] as? NSNumber)?.int64Value
                    == 180
                && upgradedDefaults.data(forKey: "telemetry.activationSnapshot.pending.v1") == nil,
            "unknown consent allows only the anonymous summary, not an activation snapshot"
        )
        upgradedLoader.completeFirst(statusCode: 202)
        try waitFor("anonymous summary completion") {
            upgradedDefaults.data(forKey: "telemetry.sessionSummary.pendingEvents.v2") == nil
        }
        upgradedService.completeNotice(extendedDiagnostics: false)
        try waitFor("activation snapshot after explicit choice") {
            upgradedLoader.requestCount == 2
        }
        guard let deniedSnapshot = upgradedLoader.event(at: 1),
              let deniedSnapshotID = deniedSnapshot["event_id"] as? String else {
            throw TestFailure("denied activation snapshot payload")
        }
        try expect(
            (deniedSnapshot["schema_version"] as? NSNumber)?.intValue == 2
                && deniedSnapshot["event"] as? String == "activation_snapshot"
                && (deniedSnapshot["snapshot_version"] as? NSNumber)?.intValue == 1
                && deniedSnapshot["diagnostics_consent_state"] as? String == "denied"
                && (deniedSnapshot["diagnostics_consent_version"] as? NSNumber)?.intValue == 1
                && Set(deniedSnapshot.keys) == Set([
                    "schema_version", "event_id", "event", "snapshot_version",
                    "diagnostics_consent_state", "diagnostics_consent_version",
                    "launcher_version", "launcher_build"
                ]),
            "activation snapshot contains only versioned explicit consent state"
        )
        upgradedLoader.completeFirst(statusCode: 400)
        try waitFor("snapshot retained after non-2xx") {
            upgradedDefaults.data(forKey: "telemetry.activationSnapshot.pending.v1") != nil
                && !upgradedDefaults.bool(forKey: "telemetry.activationSnapshot.completed.v1")
        }
        let upgradedRetryLoader = TelemetryLoaderStub()
        let upgradedRetryService = LauncherTelemetryService(
            defaults: upgradedDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: upgradedRetryLoader.load
        )
        try waitFor("activation snapshot retry after relaunch") {
            upgradedRetryLoader.requestCount == 1
        }
        try expect(
            upgradedRetryLoader.firstEventID == deniedSnapshotID
                && upgradedRetryLoader.event(at: 0)?["diagnostics_consent_state"] as? String
                    == "denied",
            "activation snapshot retries preserve the event ID and explicit choice"
        )
        upgradedRetryLoader.completeFirst(statusCode: 202)
        try waitFor("activation snapshot 2xx completion") {
            upgradedDefaults.bool(forKey: "telemetry.activationSnapshot.completed.v1")
                && upgradedDefaults.data(forKey: "telemetry.activationSnapshot.pending.v1") == nil
        }
        upgradedRetryService.recordGameSession(
            durationSeconds: 180,
            launcherSettings: telemetrySettings
        )
        upgradedRetryService.recordGameSession(
            durationSeconds: 360,
            launcherSettings: telemetrySettings
        )
        try waitFor("anonymous summaries after completed snapshot") {
            upgradedRetryLoader.requestCount == 2
        }
        upgradedRetryLoader.completeFirst(statusCode: 202)
        try waitFor("second anonymous summary") {
            upgradedRetryLoader.requestCount == 3
        }
        upgradedRetryLoader.completeFirst(statusCode: 202)
        try waitFor("anonymous summary queue drained") {
            upgradedDefaults.data(forKey: "telemetry.sessionSummary.pendingEvents.v2") == nil
        }
        let completedReloadLoader = TelemetryLoaderStub()
        let completedReloadService = LauncherTelemetryService(
            defaults: upgradedDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: completedReloadLoader.load
        )
        completedReloadService.recordGameSession(
            durationSeconds: 540,
            launcherSettings: telemetrySettings
        )
        try waitFor("anonymous summary after relaunch") {
            completedReloadLoader.requestCount == 1
        }
        try expect(
            upgradedRetryLoader.requestCount == 3
                && completedReloadLoader.event(at: 0)?["event"] as? String
                    == "game_session_summary"
                && upgradedDefaults.bool(forKey: "telemetry.activationSnapshot.completed.v1"),
            "later sessions continue without recreating completed snapshot version 1"
        )

        let grantedDefaultsName = "LauncherTests.grantedSnapshot.\(UUID().uuidString)"
        guard let grantedDefaults = UserDefaults(suiteName: grantedDefaultsName) else {
            throw TestFailure("granted snapshot UserDefaults suite")
        }
        defer { grantedDefaults.removePersistentDomain(forName: grantedDefaultsName) }
        grantedDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        grantedDefaults.set(true, forKey: "telemetry.firstSession.completed.v2")
        grantedDefaults.set("granted", forKey: "telemetry.extendedConsent.state.v1")
        grantedDefaults.set(1, forKey: "telemetry.extendedConsent.version.v1")
        let grantedLoader = TelemetryLoaderStub()
        let grantedService = LauncherTelemetryService(
            defaults: grantedDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: grantedLoader.load
        )
        try waitFor("known granted snapshot on updated launcher start") {
            grantedLoader.requestCount == 1
        }
        try expect(
            grantedLoader.event(at: 0)?["diagnostics_consent_state"] as? String == "granted",
            "known granted consent is captured without waiting for a game session"
        )
        grantedLoader.completeFirst(statusCode: 202)
        try waitFor("granted snapshot completion") {
            grantedDefaults.bool(forKey: "telemetry.activationSnapshot.completed.v1")
                && grantedService.isExtendedDiagnosticsEnabled
        }

        let diagnosticsDefaultsName = "LauncherTests.diagnostics.\(UUID().uuidString)"
        guard let diagnosticsDefaults = UserDefaults(suiteName: diagnosticsDefaultsName) else {
            throw TestFailure("diagnostics UserDefaults suite")
        }
        defer { diagnosticsDefaults.removePersistentDomain(forName: diagnosticsDefaultsName) }
        diagnosticsDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        diagnosticsDefaults.set(true, forKey: "telemetry.firstSession.completed.v2")
        diagnosticsDefaults.set(true, forKey: "telemetry.activationSnapshot.completed.v1")
        let diagnosticsService = LauncherTelemetryService(
            defaults: diagnosticsDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            device: telemetryDevice,
            loader: TelemetryLoaderStub().load
        )
        diagnosticsService.completeNotice(extendedDiagnostics: true)
        diagnosticsService.recordGameSession(
            durationSeconds: 2_871,
            launcherSettings: telemetrySettings,
            endedAt: gameSessionStart.addingTimeInterval(2_871)
        )
        guard let diagnosticsData = diagnosticsDefaults.data(
                forKey: "telemetry.extended.pendingEvents.v2"
              ),
              let diagnosticsEvents = try JSONSerialization.jsonObject(with: diagnosticsData)
                as? [[String: Any]],
              let diagnosticsEvent = diagnosticsEvents.first,
              let settingsPayload = diagnosticsEvent["launcher_settings"] as? [String: Any],
              let devicePayload = diagnosticsEvent["device"] as? [String: Any] else {
            throw TestFailure("extended diagnostics payload")
        }
        try expect(
            diagnosticsEvent["event"] as? String == "game_session_diagnostics"
                && (diagnosticsEvent["consent_version"] as? NSNumber)?.intValue == 1
                && (diagnosticsEvent["duration_seconds"] as? NSNumber)?.int64Value == 2_871
                && settingsPayload["profile_id"] as? String == "quality"
                && settingsPayload["effects_quality_id"] as? String == "performance"
                && settingsPayload["game_language"] == nil
                && (settingsPayload["guest_memory_mb"] as? NSNumber)?.intValue == 8_192
                && (settingsPayload["guest_cpu_cores"] as? NSNumber)?.intValue == 6
                && devicePayload["model_identifier"] as? String == "Mac16,1"
                && diagnosticsEvent["installation_id"] == nil,
            "consented diagnostics include applied settings without a persistent identifier"
        )
        try expect(
            diagnosticsDefaults.data(forKey: "telemetry.sessionSummary.pendingEvents.v2") != nil,
            "consented sessions also create the independent anonymous summary"
        )
        diagnosticsService.setExtendedDiagnosticsEnabled(false)
        try expect(
            !diagnosticsService.isExtendedDiagnosticsEnabled
                && diagnosticsDefaults.data(forKey: "telemetry.extended.pendingEvents.v2") == nil
                && diagnosticsDefaults.data(
                    forKey: "telemetry.sessionSummary.pendingEvents.v2"
                ) != nil,
            "withdrawing consent clears diagnostics without deleting anonymous summaries"
        )

        let oldConsentDefaultsName = "LauncherTests.old-consent.\(UUID().uuidString)"
        guard let oldConsentDefaults = UserDefaults(suiteName: oldConsentDefaultsName) else {
            throw TestFailure("old consent UserDefaults suite")
        }
        defer { oldConsentDefaults.removePersistentDomain(forName: oldConsentDefaultsName) }
        oldConsentDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        oldConsentDefaults.set("granted", forKey: "telemetry.extendedConsent.state.v1")
        oldConsentDefaults.set(0, forKey: "telemetry.extendedConsent.version.v1")
        oldConsentDefaults.set(true, forKey: "telemetry.noticeShown.v2")
        oldConsentDefaults.set(Data("[]".utf8), forKey: "telemetry.extended.pendingEvents.v2")
        let oldConsentService = LauncherTelemetryService(
            defaults: oldConsentDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            loader: TelemetryLoaderStub().load
        )
        try expect(
            oldConsentService.shouldShowNotice
                && !oldConsentService.isExtendedDiagnosticsEnabled
                && oldConsentDefaults.data(forKey: "telemetry.extended.pendingEvents.v2") == nil,
            "a consent-version change stops diagnostics and requests consent again"
        )

        let duplicateDefaultsName = "LauncherTests.duplicate.\(UUID().uuidString)"
        guard let duplicateDefaults = UserDefaults(suiteName: duplicateDefaultsName) else {
            throw TestFailure("duplicate UserDefaults suite")
        }
        defer { duplicateDefaults.removePersistentDomain(forName: duplicateDefaultsName) }
        duplicateDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        let duplicateLoader = TelemetryLoaderStub()
        duplicateDefaults.set(true, forKey: "telemetry.activationSnapshot.completed.v1")
        let duplicateService = LauncherTelemetryService(
            defaults: duplicateDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            loader: duplicateLoader.load
        )
        duplicateService.completeNotice(extendedDiagnostics: false)
        duplicateService.recordGameSession(
            durationSeconds: 600,
            launcherSettings: telemetrySettings
        )
        try waitFor("duplicate telemetry request") { duplicateLoader.requestCount == 1 }
        duplicateLoader.completeFirst(statusCode: 409)
        try waitFor("duplicate telemetry acknowledgement") {
            duplicateDefaults.bool(forKey: "telemetry.firstSession.completed.v2")
                && duplicateDefaults.data(forKey: "telemetry.firstSession.pending.v2") == nil
        }

        let staleDefaultsName = "LauncherTests.stale.\(UUID().uuidString)"
        guard let staleDefaults = UserDefaults(suiteName: staleDefaultsName) else {
            throw TestFailure("stale UserDefaults suite")
        }
        defer { staleDefaults.removePersistentDomain(forName: staleDefaultsName) }
        staleDefaults.set(
            currentUTCDay,
            forKey: "telemetry.dailyActive.lastCreatedDay.v1"
        )
        let staleLoader = TelemetryLoaderStub()
        staleDefaults.set(true, forKey: "telemetry.activationSnapshot.completed.v1")
        let staleService = LauncherTelemetryService(
            defaults: staleDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            loader: staleLoader.load
        )
        staleService.completeNotice(extendedDiagnostics: false)
        staleService.recordGameSession(
            durationSeconds: 600,
            launcherSettings: telemetrySettings
        )
        guard let staleData = staleDefaults.data(forKey: "telemetry.firstSession.pending.v2"),
              var staleWrapper = try JSONSerialization.jsonObject(with: staleData)
                as? [String: Any] else {
            throw TestFailure("stale first-session payload")
        }
        staleWrapper["created_at"] = "2020-01-01T00:00:00Z"
        staleDefaults.set(
            try JSONSerialization.data(withJSONObject: staleWrapper),
            forKey: "telemetry.firstSession.pending.v2"
        )
        let staleRetryLoader = TelemetryLoaderStub()
        let staleRetryService = LauncherTelemetryService(
            defaults: staleDefaults,
            apiBaseURL: URL(string: "https://127.0.0.1:1/")!,
            loader: staleRetryLoader.load
        )
        staleRetryService.recordGameSession(
            durationSeconds: 900,
            launcherSettings: telemetrySettings
        )
        try waitFor("anonymous summary survives stale first-session expiry") {
            staleRetryLoader.requestCount == 1
        }
        try expect(
            staleDefaults.bool(forKey: "telemetry.firstSession.completed.v2")
                && staleDefaults.data(forKey: "telemetry.firstSession.pending.v2") == nil
                && staleRetryLoader.event(at: 0)?["event"] as? String
                    == "game_session_summary",
            "a stale first-session event is discarded without deleting session summaries"
        )
        let messageURL = LauncherTelemetryService.messageURL(
            apiBaseURL: URL(string: "https://sergeinaumov.dev/mactician/api/")!,
            trigger: .gameClosed,
            launcherVersion: "1.0.0"
        )
        try expect(
            messageURL?.absoluteString
                == "https://sergeinaumov.dev/mactician/api/v1/messages?trigger=game_closed&version=1.0.0",
            "message endpoint query encoding"
        )
        let gameStoppedEvent = try JSONDecoder().decode(
            RuntimeEvent.self,
            from: Data(#"{"event":"game_stopped","code":0}"#.utf8)
        )
        try expect(
            gameStoppedEvent.event == .gameStopped,
            "runtime game-closed event decoding"
        )
        let deviceReadyEvent = try JSONDecoder().decode(
            RuntimeEvent.self,
            from: Data(#"{"event":"device_ready","serial":"emulator-5582"}"#.utf8)
        )
        try expect(
            deviceReadyEvent.event == .deviceReady
                && deviceReadyEvent.serial == "emulator-5582",
            "Google Play device-ready event decoding"
        )
        let vietnamReadyEvent = try JSONDecoder().decode(
            RuntimeEvent.self,
            from: Data(
                #"{"event":"ready","package":"com.riotgames.league.teamfighttacticsvn"}"#.utf8
            )
        )
        try expect(
            vietnamReadyEvent.package == GameRelease.vietnamPackageName,
            "Vietnam runtime package event decoding"
        )
        let gameActivityOutput = """
            Display #0:
              topResumedActivity=ActivityRecord{abc123 u0 com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity t42}
            """
        let loginActivityOutput = """
            mResumedActivity: ActivityRecord{old u0 com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity t41}
            topResumedActivity=ActivityRecord{def456 u0 com.riotgames.league.teamfighttactics/com.riotgames.platformui.MobileFREWebViewActivity t42}
            """
        try expect(
            BridgeAndroidActivityClassifier.classify(dumpsysOutput: gameActivityOutput) == .gameplay
                && BridgeAndroidActivityClassifier.classify(dumpsysOutput: loginActivityOutput)
                == .nonGameplay
                && BridgeAndroidActivityClassifier.classify(
                    dumpsysOutput: "topResumedActivity=null"
                ) == .unknown,
            "input bridge foreground activity classification"
        )
        try expect(
            BridgeKeyboardEventPolicy.disposition(
                for: 44,
                activity: .gameplay,
                modifierFlags: []
            ) == .consume
                && BridgeKeyboardEventPolicy.disposition(
                    for: BridgeKeyboardBinding.shop,
                    activity: .gameplay,
                    modifierFlags: [.shift]
                ) == .hotkey
                && BridgeKeyboardEventPolicy.disposition(
                    for: 44,
                    activity: .gameplay,
                    modifierFlags: [.command]
                ) == .passThrough
                && BridgeKeyboardEventPolicy.disposition(
                    for: 44,
                    activity: .gameplay,
                    modifierFlags: [.control]
                ) == .passThrough
                && BridgeKeyboardEventPolicy.disposition(
                    for: 44,
                    activity: .gameplay,
                    modifierFlags: [.option]
                ) == .passThrough
                && BridgeKeyboardEventPolicy.disposition(
                    for: 44,
                    activity: .nonGameplay,
                    modifierFlags: []
                ) == .passThrough
                && BridgeKeyboardEventPolicy.disposition(
                    for: 44,
                    activity: .unknown,
                    modifierFlags: []
                ) == .passThrough,
            "input bridge keyboard event policy"
        )
        var bridgeSessionGeneration = BridgeSessionGeneration()
        let stoppedGeneration = bridgeSessionGeneration.advance()
        let activeGeneration = bridgeSessionGeneration.advance()
        try expect(
            !bridgeSessionGeneration.accepts(stoppedGeneration)
                && bridgeSessionGeneration.accepts(activeGeneration),
            "stale input bridge session status is rejected"
        )
        var audioRecoveryPolicy = EmulatorAudioRecoveryPolicy(
            startupDelay: 100,
            settleDelay: 0.75,
            cooldown: 2
        )
        let initialWindowSize = EmulatorWindowSize(width: 1_920, height: 1_120)
        let resizedWindowSize = EmulatorWindowSize(width: 1_600, height: 940)
        let finalWindowSize = EmulatorWindowSize(width: 1_440, height: 850)
        try expect(
            audioRecoveryPolicy.observe(size: initialWindowSize, at: 10) == nil
                && audioRecoveryPolicy.observe(size: resizedWindowSize, at: 10.1) == nil
                && audioRecoveryPolicy.observe(size: finalWindowSize, at: 10.5) == nil
                && audioRecoveryPolicy.observe(size: finalWindowSize, at: 11.24) == nil
                && audioRecoveryPolicy.observe(size: finalWindowSize, at: 11.25) == .windowResize
                && audioRecoveryPolicy.observe(size: finalWindowSize, at: 12) == nil,
            "audio recovery is debounced until window resizing settles"
        )
        try expect(
            audioRecoveryPolicy.observe(size: resizedWindowSize, at: 12.5) == nil
                && audioRecoveryPolicy.observe(size: resizedWindowSize, at: 13.24) == nil
                && audioRecoveryPolicy.observe(size: initialWindowSize, at: 13.5) == nil
                && audioRecoveryPolicy.observe(size: initialWindowSize, at: 14.25) == .windowResize,
            "audio recovery cooldown defers repeated window changes"
        )
        var startupAudioRecoveryPolicy = EmulatorAudioRecoveryPolicy(
            startupDelay: 1.5,
            settleDelay: 0.75,
            cooldown: 2
        )
        try expect(
            startupAudioRecoveryPolicy.observe(size: initialWindowSize, at: 20) == nil
                && startupAudioRecoveryPolicy.observe(size: initialWindowSize, at: 21.49) == nil
                && startupAudioRecoveryPolicy.observe(size: initialWindowSize, at: 21.5) == .startup
                && startupAudioRecoveryPolicy.observe(size: initialWindowSize, at: 24) == nil,
            "audio recovery runs once after game startup"
        )
        var halFailureRecoveryPolicy = EmulatorAudioRecoveryPolicy(
            startupDelay: 100,
            settleDelay: 0.75,
            cooldown: 2,
            failureThreshold: 3,
            failureWindow: 0.5
        )
        try expect(
            halFailureRecoveryPolicy.observeHALWriteFailure(at: 30) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 30.2) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 30.4) == .halWriteFailure
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 30.6) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 30.8) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 31) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 32.4) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 32.55) == nil
                && halFailureRecoveryPolicy.observeHALWriteFailure(at: 32.7) == .halWriteFailure,
            "repeated Audio HAL failures trigger recovery with cooldown"
        )
        try expect(
            EmulatorAudioFailureClassifier.isHALWriteFailure(
                "E/android.hardware.audio@7.1-impl.ranchu: pcmWrite:260 failure: -1"
            )
                && EmulatorAudioFailureClassifier.isHALWriteFailure(
                    "pcm_writei failed with 'cannot read/write stream data: I/O error' (-1)"
                )
                && !EmulatorAudioFailureClassifier.isHALWriteFailure(
                    "AudioSystem: AudioFlinger server died!"
                ),
            "Audio HAL write failure classification"
        )

        let infoPlistData = try Data(contentsOf: sourceRoot.appendingPathComponent("Info.plist"))
        guard let infoPlist = try PropertyListSerialization.propertyList(from: infoPlistData, format: nil)
            as? [String: Any] else {
            throw TestFailure("invalid Info.plist")
        }
        try expect(infoPlist["CFBundleDevelopmentRegion"] as? String == "en", "launcher language")
        try expect(
            infoPlist["CFBundleLocalizations"] as? [String] == ["en", "ru"],
            "launcher localizations"
        )
        try expect(infoPlist["CFBundleDisplayName"] as? String == "Mactician", "app display name")
        try expect(infoPlist["CFBundleName"] as? String == "Mactician", "app bundle name")
        try expect(infoPlist["CFBundleExecutable"] as? String == "Mactician", "app executable")
        try expect(
            infoPlist["CFBundleIdentifier"] as? String == MacticianIdentity.bundleIdentifier,
            "app bundle identifier"
        )
        try expect(infoPlist["CFBundleIconFile"] as? String == "Mactician.icns", "launcher icon name")
        try expect(infoPlist["CFBundleShortVersionString"] as? String == "1.1.3", "launcher version")
        try expect(infoPlist["CFBundleVersion"] as? String == "48", "launcher build")
        try expect(
            infoPlist["SUFeedURL"] as? String == "https://sergeinaumov.dev/mactician/updates/appcast.xml",
            "Sparkle appcast URL"
        )
        try expect(
            infoPlist["SUPublicEDKey"] as? String == "77t8YuvP4mvvP/3oMpVR/TqGRMCcUlrpWFIZGcWqokY=",
            "Sparkle public key"
        )
        try expect(
            infoPlist["SUEnableAutomaticChecks"] as? Bool == true
                && infoPlist["SUAllowsAutomaticUpdates"] as? Bool == true
                && infoPlist["SUAutomaticallyUpdate"] as? Bool == false
                && infoPlist["SUScheduledCheckInterval"] as? Int == 86_400,
            "Sparkle automatic check policy"
        )
        try expect(
            infoPlist["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
            "Sparkle pre-extraction verification policy"
        )
        let updateControllerSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/LauncherUpdateController.swift"),
            encoding: .utf8
        )
        try expect(
            updateControllerSource.contains("updaterController.updater.automaticallyChecksForUpdates")
                && updateControllerSource.contains("updaterController.updater.checkForUpdatesInBackground()"),
            "Sparkle update check on every launch"
        )
        let appTransportSecurity = infoPlist["NSAppTransportSecurity"] as? [String: Any]
        try expect(
            appTransportSecurity?["NSAllowsLocalNetworking"] as? Bool == true,
            "local WebView DevTools networking"
        )
        try expect(
            FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent("Resources/Mactician.icns").path
            ),
            "launcher icon resource"
        )
        try expect(
            FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent("Resources/EmulatorIcon.icns").path
            ),
            "emulator icon resource"
        )
        let launcherIcon = try Data(
            contentsOf: sourceRoot.appendingPathComponent("Resources/Mactician.icns")
        )
        let emulatorIcon = try Data(
            contentsOf: sourceRoot.appendingPathComponent("Resources/EmulatorIcon.icns")
        )
        try expect(
            launcherIcon != emulatorIcon
                && FileManager.default.fileExists(
                    atPath: sourceRoot.appendingPathComponent(
                        "Resources/EmulatorIcon-1024.png"
                    ).path
                ),
            "active game icon is distinct from the launcher icon"
        )
        try expect(
            FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent("Resources/QEMU-Hypervisor.entitlements").path
            ),
            "QEMU hypervisor entitlement resource"
        )
        try expect(
            EmulatorBrandingPatch.iconInstructionOffset == 0x5af688,
            "QEMU icon patch offset"
        )
        try expect(
            EmulatorBrandingPatch.sourceIconInstruction == Data([0xf4, 0xbf, 0x4d, 0x94])
                && EmulatorBrandingPatch.patchedIconInstruction == Data([0x1f, 0x20, 0x03, 0xd5]),
            "QEMU icon patch instructions"
        )
        try expect(
            EmulatorBrandingPatch.titleFormatOffset == 0x1a1e891
                && EmulatorBrandingPatch.sourceTitleFormat
                    == Data("%s Emulator - %s:%d\0".utf8)
                && EmulatorBrandingPatch.patchedTitleFormat
                    == Data("Mactician: TFT\0\0\0\0\0\0".utf8),
            "QEMU window title patch"
        )
        let emulatorHostData = try Data(
            contentsOf: sourceRoot.appendingPathComponent("Resources/EmulatorHost-Info.plist")
        )
        guard let emulatorHostInfo = try PropertyListSerialization.propertyList(
            from: emulatorHostData,
            format: nil
        ) as? [String: Any] else {
            throw TestFailure("invalid emulator host Info.plist")
        }
        try expect(
            emulatorHostInfo["CFBundleIconFile"] as? String == "EmulatorIcon.icns",
            "emulator host icon name"
        )
        try expect(
            emulatorHostInfo["CFBundleShortVersionString"] as? String == "1.1.3",
            "emulator host version"
        )
        try expect(emulatorHostInfo["CFBundleVersion"] as? String == "48", "emulator host build")
        try expect(
            emulatorHostInfo["CFBundleIdentifier"] as? String
                == "dev.sergeinaumov.mactician.game-host",
            "game host bundle identifier"
        )
        try expect(MacticianIdentity.appName == "Mactician", "application name")
        try expect(
            MacticianIdentity.userDefaultsDomain == "dev.sergeinaumov.mactician",
            "UserDefaults domain"
        )
        try expect(
            MacticianIdentity.keychainService == "dev.sergeinaumov.mactician",
            "Keychain service"
        )
        try expect(
            MacticianIdentity.loggingSubsystem == "dev.sergeinaumov.mactician",
            "logging subsystem"
        )
        let supportRoot = LauncherPaths.defaultRoot(
            applicationSupport: URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        )
        try expect(
            supportRoot.path == "/tmp/Application Support/Mactician",
            "fresh Application Support root"
        )

        try expect(HostSizing.guestCPUCores(logicalCPUCount: 4) == 4, "minimum CPU count")
        try expect(HostSizing.guestCPUCores(logicalCPUCount: 8) == 6, "M1 CPU count")
        try expect(HostSizing.guestCPUCores(logicalCPUCount: 12) == 6, "maximum CPU count")
        try expect(HostSizing.guestCPUList(logicalCPUCount: 8) == "0-5", "CPU list")
        try expect(HostSizing.guestCPUMask(logicalCPUCount: 8) == "3f", "CPU mask")
        try expect(
            GuestResourceOptions.memoryMB(physicalMemoryBytes: 16 * 1024 * 1024 * 1024)
                == [4096, 6144, 8192, 10240, 12288],
            "16 GB host RAM choices"
        )
        try expect(
            GuestResourceOptions.installationMemoryMB(physicalMemoryBytes: 8 * 1024 * 1024 * 1024) == 4096
                && GuestResourceOptions.installationMemoryMB(
                    physicalMemoryBytes: 16 * 1024 * 1024 * 1024
                ) == 6144,
            "host-sized installation RAM"
        )
        try expect(
            GuestResourceOptions.memoryMB(physicalMemoryBytes: 32 * 1024 * 1024 * 1024).last == 16384,
            "guest RAM cap"
        )
        try expect(
            GuestResourceOptions.cpuCores(logicalCPUCount: 8) == Array(2 ... 8),
            "8-core host vCPU choices"
        )
        try expect(
            GuestResourceOptions.selection(saved: 8, options: [4, 6, 8], fallback: 6) == 8
                && GuestResourceOptions.selection(saved: 12, options: [4, 6, 8], fallback: 6) == 6,
            "saved guest resource validation"
        )
        try expect(
            InterfaceScaleOptions.percentages == [100, 125, 150, 175, 200]
                && InterfaceScaleOptions.selection(saved: 175) == 175
                && InterfaceScaleOptions.selection(saved: 225) == 100,
            "UI scale choices and saved selection validation"
        )
        try expect(
            InterfaceScaleOptions.runtimeValue(percent: 175) == "1.75"
                && InterfaceScaleOptions.runtimeValue(percent: 200) == "2.0"
                && InterfaceScaleOptions.runtimeValue(percent: 225) == nil,
            "UI scale runtime value"
        )
        try expect(
            GuestResourceOptions.recommended(
                physicalMemoryBytes: 32 * 1024 * 1024 * 1024,
                logicalCPUCount: 10
            ) == GuestResourceConfiguration(memoryMB: 8192, cpuCores: 6),
            "M1 Max resource recommendation"
        )
        try expect(
            GuestResourceOptions.recommended(
                physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
                logicalCPUCount: 8
            ) == GuestResourceConfiguration(memoryMB: 6144, cpuCores: 6),
            "16 GB resource recommendation"
        )
        try expect(GameLanguage.supported.count == 23, "supported game language count")
        try expect(GameLanguage.language(withID: "ru-RU").title == "Russian", "Russian game language")
        try expect(GameLanguage.language(withID: "unsupported") == .english, "language fallback")
        try expect(
            LauncherMetadata.gameDisplayVersion(from: manifest.game.version) == "18.1",
            "manifest-derived game display version"
        )
        try expect(
            LauncherMetadata.totalDownloadBytes(in: manifest)
                == manifest.components.reduce(Int64(0)) { $0 + $1.size },
            "manifest-derived download size"
        )
        try expect(
            !LauncherMetadata.byteCount(LauncherMetadata.totalDownloadBytes(in: manifest)).isEmpty,
            "download size formatting"
        )
        try expect(
            LauncherMetadata.androidAPILevel(in: manifest) == "36"
                && LauncherMetadata.componentVersion("emulator", in: manifest) == "37.1.11",
            "manifest-derived component metadata"
        )
        try expect(
            LauncherFailurePresentation.recoveryAction(for: .installation) == .retryInstallation
                && LauncherFailurePresentation.recoveryAction(for: .launch) == .tryLaunchAgain
                && LauncherFailurePresentation.recoveryAction(for: .runtime) == .restartGame
                && LauncherFailurePresentation.recoveryAction(for: .validation) == .repairInstallation
                && LauncherFailurePresentation.recoveryAction(for: .reset) == .none,
            "failure recovery mapping"
        )
        try expect(
            InstallerCompletionPresentation.isUserCancellation(
                requested: true,
                error: LauncherError.process("late completion")
            )
                && InstallerCompletionPresentation.isUserCancellation(
                    requested: false,
                    error: LauncherError.cancelled
                )
                && !InstallerCompletionPresentation.isUserCancellation(
                    requested: false,
                    error: LauncherError.process("failed")
                ),
            "user cancellation completion mapping"
        )
        try expect(
            LauncherHotkeyPresentation.status(for: .init(
                accessibilityTrusted: false,
                eventTapActive: false,
                eventTapAttemptFailed: false
            )) == .permissionRequired
                && LauncherHotkeyPresentation.status(for: .init(
                    accessibilityTrusted: false,
                    eventTapActive: true,
                    eventTapAttemptFailed: false
                )) == .active
                && LauncherHotkeyPresentation.status(for: .init(
                    accessibilityTrusted: true,
                    eventTapActive: false,
                    eventTapAttemptFailed: false
                )) == .ready
                && LauncherHotkeyPresentation.status(for: .init(
                    accessibilityTrusted: true,
                    eventTapActive: true,
                    eventTapAttemptFailed: false
                )) == .active
                && LauncherHotkeyPresentation.status(for: .init(
                    accessibilityTrusted: true,
                    eventTapActive: false,
                    eventTapAttemptFailed: true
                )) == .unavailable,
            "hotkey permission presentation mapping"
        )
        try expect(
            InstallerService.unrealCommandLine(for: GameLanguage.language(withID: "ru-RU"))
                .contains("-culture=ru-RU"),
            "Unreal culture argument"
        )
        try expect(
            InstallerService.adbArguments(["devices"]) == ["-P", "5038", "devices"],
            "isolated ADB server arguments"
        )
        let gameInstallArguments = InstallerService.gameInstallArguments(apkPaths: ["base.apk", "split.apk"])
        try expect(
            gameInstallArguments == [
                "-P", "5038", "-s", "emulator-5582", "install-multiple",
                "--no-streaming", "-r", "-g", "base.apk", "split.apk"
            ],
            "persistent split APK installation"
        )
        try expect(
            InstallerService.emulatorArguments(
                initializeData: true,
                logicalCPUCount: 8,
                memoryMB: 4096
            ).contains("-wipe-data"),
            "first boot initializes userdata"
        )
        let provisioningArguments = InstallerService.emulatorArguments(
            initializeData: false,
            logicalCPUCount: 8,
            memoryMB: 4096
        )
        try expect(
            provisioningArguments.contains("-dns-server")
                && provisioningArguments.contains("1.1.1.1,8.8.8.8"),
            "public DNS avoids local network access"
        )
        try expect(
            provisioningArguments.contains("GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts")
                && provisioningArguments.contains("androidboot.opengles.version=196610")
                && provisioningArguments.contains("androidboot.mactician.graphics_profile=osft"),
            "Google Play provisioning exposes TFT's required OpenGL ES 3.2 profile"
        )
        try expect(
            provisioningArguments.joined(separator: " ").contains("-memory 4096"),
            "low-memory provisioning"
        )
        try expect(
            !InstallerService.emulatorArguments(
                initializeData: false,
                logicalCPUCount: 8,
                memoryMB: 4096
            ).contains("-wipe-data"),
            "normal boot preserves userdata"
        )

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("tft-launcher-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try runNativeIPadRuntimeTests(in: temporary, sourceRoot: sourceRoot)
        let abc = temporary.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: abc)
        try expect(
            try SystemServices.sha256(of: abc) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "streaming SHA-256"
        )

        let overlaySourceRoot = temporary.appendingPathComponent("overlay-source", isDirectory: true)
        let overlayAssets = overlaySourceRoot.appendingPathComponent("assets", isDirectory: true)
        let overlaySource = temporary.appendingPathComponent("base-fixture.apk")
        let overlayDestination = temporary.appendingPathComponent("base-overlay.apk")
        let overlayStaging = temporary.appendingPathComponent("overlay-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: overlayAssets, withIntermediateDirectories: true)
        try Data("original\n".utf8).write(to: overlayAssets.appendingPathComponent("UECommandLine.txt"))
        try Data("fixture".utf8).write(to: overlaySourceRoot.appendingPathComponent("payload.bin"))
        try SystemServices.run(
            URL(fileURLWithPath: "/usr/bin/zip"),
            ["-q", "-r", overlaySource.path, "assets", "payload.bin"],
            currentDirectory: overlaySourceRoot
        )
        let overlayHash = try InstallerService.prepareOverlay(
            source: overlaySource,
            expectedSourceSHA256: try SystemServices.sha256(of: overlaySource),
            destination: overlayDestination,
            stagingRoot: overlayStaging,
            language: GameLanguage.language(withID: "ru-RU")
        )
        try expect(
            overlayHash == SystemServices.sha256(of: overlayDestination),
            "prepared overlay hash"
        )
        try expect(
            try SystemServices.run(
                URL(fileURLWithPath: "/usr/bin/unzip"),
                ["-p", overlayDestination.path, "assets/UECommandLine.txt"]
            ) == InstallerService.unrealCommandLine(for: GameLanguage.language(withID: "ru-RU")),
            "prepared overlay culture"
        )

        var state = InstallState()
        state.stage = .avdCreated
        state.installedComponents = ["emulator": "37.1.11"]
        state.gamePackageName = GameRelease.vietnamPackageName
        let stateURL = temporary.appendingPathComponent("install-state.json")
        try SystemServices.saveState(state, to: stateURL)
        let restored = SystemServices.loadState(from: stateURL)
        try expect(restored.stage == .avdCreated, "state stage")
        try expect(restored.installedComponents == state.installedComponents, "state components")
        try expect(
            restored.gamePackageName == GameRelease.vietnamPackageName,
            "Vietnam package state persistence"
        )
        try Data("truncated".utf8).write(to: stateURL, options: .atomic)
        try expect(SystemServices.loadState(from: stateURL).stage == .empty, "corrupt state fallback")

        let preparedRoot = temporary.appendingPathComponent("prepared-data", isDirectory: true)
        let preparedPaths = try LauncherPaths(
            root: preparedRoot,
            resources: sourceRoot.appendingPathComponent("Resources", isDirectory: true)
        )
        try InstallerService.prepareDirectories(at: preparedPaths)
        try expect(
            FileManager.default.fileExists(atPath: preparedPaths.avdHome.path),
            "AVD parent directory"
        )
        try expect(
            FileManager.default.fileExists(atPath: preparedPaths.staging.path),
            "staging directory"
        )

        let runtimeResources = temporary.appendingPathComponent("runtime-resources", isDirectory: true)
        let runtimeTemplate = runtimeResources.appendingPathComponent("RuntimeTemplate", isDirectory: true)
        let emulatorHostTemplate = runtimeResources.deletingLastPathComponent().appendingPathComponent(
            "Helpers/Mactician Game Host.app",
            isDirectory: true
        )
        let runtimeRoot = temporary.appendingPathComponent("runtime-data", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeTemplate, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emulatorHostTemplate, withIntermediateDirectories: true)
        try Data("new runtime".utf8).write(to: runtimeTemplate.appendingPathComponent("marker.txt"))
        try Data("signed host".utf8).write(to: emulatorHostTemplate.appendingPathComponent("marker.txt"))
        let runtimePaths = try LauncherPaths(root: runtimeRoot, resources: runtimeResources)
        try FileManager.default.createDirectory(at: runtimePaths.runtimeProject, withIntermediateDirectories: true)
        try Data("old runtime".utf8).write(to: runtimePaths.runtimeProject.appendingPathComponent("old.txt"))
        try InstallerService.refreshRuntimeProject(at: runtimePaths)
        try expect(
            try String(
                contentsOf: runtimePaths.runtimeProject.appendingPathComponent("marker.txt"),
                encoding: .utf8
            ) == "new runtime",
            "runtime refresh installs the bundled template"
        )
        try expect(
            !FileManager.default.fileExists(atPath: runtimePaths.runtimeProject.appendingPathComponent("old.txt").path),
            "runtime refresh replaces the previous template"
        )
        try expect(
            try String(
                contentsOf: runtimePaths.runtimeProject.appendingPathComponent(
                    "Mactician Game Host.app/marker.txt"
                ),
                encoding: .utf8
            ) == "signed host",
            "runtime refresh installs the signed game host from Contents/Helpers"
        )

        let rootRuntimeScript = try String(
            contentsOf: sourceRoot.deletingLastPathComponent().appendingPathComponent("run-tft-root-affinity.command"),
            encoding: .utf8
        )
        let googlePlayRuntimeScript = try String(
            contentsOf: sourceRoot.deletingLastPathComponent().appendingPathComponent("run-tft-google-play.command"),
            encoding: .utf8
        )
        try expect(
            googlePlayRuntimeScript.contains("androidboot.opengles.version=$OPENGL_ES_VERSION")
                && googlePlayRuntimeScript.contains("feature:reqGlEsVersion=0x30002")
                && googlePlayRuntimeScript.contains("angle_gl_driver_selection_pkgs")
                && googlePlayRuntimeScript.contains("exposeES32ForTesting"),
            "Google Play runtime preserves TFT's OpenGL ES 3.2 catalog and ANGLE requirements"
        )
        try expect(
            rootRuntimeScript.contains("Empty TFT streaming manifest detected")
                && rootRuntimeScript.contains("rm -rf \"$STREAMING_INSTALL_DIR\""),
            "empty streaming manifest self-heal"
        )
        try expect(
            rootRuntimeScript.contains("ApplicationScale=\" scale")
                && rootRuntimeScript.contains("TFT_UI_SCALE"),
            "Unreal UI scale launch configuration"
        )
        let runtimeControllerSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/RuntimeController.swift"),
            encoding: .utf8
        )
        try expect(
            rootRuntimeScript.contains("GameUserSettings.ini")
                && rootRuntimeScript.contains("TFT_PERFORMANCE_MODE")
                && rootRuntimeScript.contains("update-tft-performance-mode.command")
                && runtimeControllerSource.contains(
                    "\"TFT_PERFORMANCE_MODE\": effectsQuality == .maximum ? \"1\" : \"0\""
                ),
            "Riot Performance Mode follows the Maximum FPS preset"
        )

        let component = manifest.components[0]
        let partial = temporary.appendingPathComponent("partial.zip")
        let curlArguments = InstallerService.curlArguments(component: component, destination: partial)
        try expect(curlArguments.contains("--continue-at"), "resumable curl option")
        try expect(curlArguments.contains("-"), "resume from current byte")
        try expect(curlArguments.last == partial.path, "download destination")

        let archiveSource = temporary.appendingPathComponent("archive-source", isDirectory: true)
        let archiveDestination = temporary.appendingPathComponent("archive-destination", isDirectory: true)
        let archive = temporary.appendingPathComponent("fixture.zip")
        try FileManager.default.createDirectory(at: archiveSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveDestination, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: archiveSource.appendingPathComponent("payload.txt"))
        try SystemServices.run(
            URL(fileURLWithPath: "/usr/bin/zip"),
            ["-q", archive.path, "payload.txt"],
            currentDirectory: archiveSource
        )
        try InstallerService.extractArchive(archive, to: archiveDestination)
        try expect(
            String(contentsOf: archiveDestination.appendingPathComponent("payload.txt"), encoding: .utf8) == "payload",
            "ZIP extraction"
        )

        let unsafe = SDKComponent(
            id: "unsafe",
            version: "1",
            url: URL(string: "https://example.com/file.zip")!,
            size: 1,
            sha256: String(repeating: "0", count: 64),
            archiveRoot: "../escape",
            installPath: "/tmp/escape"
        )
        do {
            try unsafe.validate()
            throw TestFailure("unsafe component accepted")
        } catch is LauncherError {
            // Expected.
        }

        let sourceFiles = try recursiveFiles(at: sourceRoot)
        for localization in ["en", "ru"] {
            let strings = sourceRoot.appendingPathComponent(
                "Resources/\(localization).lproj/Localizable.strings"
            )
            try expect(
                FileManager.default.fileExists(atPath: strings.path),
                "\(localization) localization resource"
            )
            guard let localizedValues = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: strings),
                format: nil
            ) as? [String: String] else {
                throw TestFailure("invalid \(localization) localization")
            }
            let descriptor = localizedValues["about.descriptor"] ?? ""
            try expect(!descriptor.isEmpty, "\(localization) Mactician descriptor")
            if localization == "en" {
                try expect(
                    descriptor == "TFT launcher for Apple Silicon",
                    "English Mactician descriptor"
                )
            }
        }
        let localizationDirectories = try FileManager.default.contentsOfDirectory(
            at: sourceRoot.appendingPathComponent("Resources"),
            includingPropertiesForKeys: nil
        ).filter {
            $0.pathExtension == "lproj"
        }.map {
            $0.deletingPathExtension().lastPathComponent
        }.sorted()
        try expect(
            localizationDirectories == ["en", "ru"],
            "Mactician localization resources"
        )
        let telemetryNoticeSource = try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "Sources/LauncherTelemetryNoticeView.swift"
            ),
            encoding: .utf8
        )
        try expect(
            telemetryNoticeSource.contains("telemetry.dont_send")
                && telemetryNoticeSource.contains("extendedDiagnostics: false")
                && telemetryNoticeSource.contains("telemetry.send")
                && telemetryNoticeSource.contains("extendedDiagnostics: true")
                && !telemetryNoticeSource.contains("Toggle("),
            "telemetry notice presents explicit unselected diagnostics choices"
        )
        let launcherModelSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/LauncherModel.swift"),
            encoding: .utf8
        )
        for defaultsKey in [
            "launchProfile", "effectsQuality", "gameLanguage", "androidMemoryMB",
            "androidCPUCores", "uiScalePercent"
        ] {
            try expect(launcherModelSource.contains("\"\(defaultsKey)\""), "UserDefaults key \(defaultsKey)")
        }
        let appSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/MacticianApp.swift"),
            encoding: .utf8
        )
        for aboutText in [
            "Mactician",
            "Free and open source.",
            "Built for two tacticians. Shared with everyone.",
            "Website",
            "GitHub",
            "Technical story",
            "Report an issue"
        ] {
            try expect(appSource.contains(aboutText), "About content: \(aboutText)")
        }
        let buildScript = try String(
            contentsOf: sourceRoot.deletingLastPathComponent()
                .appendingPathComponent("scripts/build-mactician.command"),
            encoding: .utf8
        )
        try expect(
            buildScript.contains("Mactician.app")
                && buildScript.contains("Mactician-$VERSION.dmg")
                && buildScript.contains("-volname \"Mactician\"")
                && buildScript.contains("Contents/Helpers/Mactician Game Host.app")
                && buildScript.contains("-framework AppKit")
                && buildScript.contains("Android_Codex.DeviceProfiles.effects-high.ini")
                && buildScript.contains("Android_Codex.DeviceProfiles.effects-performance.ini")
                && buildScript.contains("Android_Codex.DeviceProfiles.performance-max.ini"),
            "release artifact naming"
        )
        let emulatorHostSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("EmulatorHost/main.c"),
            encoding: .utf8
        )
        let iconRegistration = emulatorHostSource.range(of: "prepare_application_identity();")
        let emulatorExec = emulatorHostSource.range(of: "execv(emulator, argv);")
        try expect(
            emulatorHostSource.contains("[NSApplication sharedApplication]")
                && emulatorHostSource.contains("setApplicationIconImage")
                && iconRegistration != nil
                && emulatorExec != nil
                && iconRegistration!.lowerBound < emulatorExec!.lowerBound,
            "game host registers its Dock icon before replacing itself with QEMU"
        )
        let artifactsRoot = sourceRoot.deletingLastPathComponent()
            .appendingPathComponent("artifacts", isDirectory: true)
        let profileRoot = try FileManager.default.contentsOfDirectory(
            at: artifactsRoot,
            includingPropertiesForKeys: nil
        ).first { candidate in
            FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent(
                    "Android_Codex.DeviceProfiles.effects-high.ini"
                ).path
            )
        }
        guard let profileRoot else {
            throw TestFailure("effects profile artifacts were not found")
        }
        let highEffectsProfile = try String(
            contentsOf: profileRoot.appendingPathComponent(
                "Android_Codex.DeviceProfiles.effects-high.ini"
            ),
            encoding: .utf8
        )
        let performanceEffectsProfile = try String(
            contentsOf: profileRoot.appendingPathComponent(
                "Android_Codex.DeviceProfiles.effects-performance.ini"
            ),
            encoding: .utf8
        )
        let maximumFPSProfile = try String(
            contentsOf: profileRoot.appendingPathComponent(
                "Android_Codex.DeviceProfiles.performance-max.ini"
            ),
            encoding: .utf8
        )
        let maximumFPSEntrypoint = try String(
            contentsOf: sourceRoot.deletingLastPathComponent().appendingPathComponent(
                "run-tft-performance-max.command"
            ),
            encoding: .utf8
        )
        for profileText in [highEffectsProfile, performanceEffectsProfile] {
            try expect(
                profileText.contains("CVars=sg.ResolutionQuality=100")
                    && profileText.contains("CVars=r.ScreenPercentage=100"),
                "effects profiles preserve selected resolution"
            )
            try expect(
                profileText.contains("CVars=Android.OpenGL.NumRemoteProgramCompileServices=4"),
                "effects profiles preserve asynchronous OpenGL PSO compilation"
            )
        }
        try expect(
            performanceEffectsProfile.contains("CVars=sg.EffectsQuality=0")
                && performanceEffectsProfile.contains("CVars=r.ParticleLODBias=2"),
            "performance effects profile reduces effects and LOD"
        )
        try expect(
            maximumFPSProfile.contains("CVars=sg.ResolutionQuality=67")
                && maximumFPSProfile.contains("CVars=r.ScreenPercentage=67")
                && maximumFPSProfile.contains("CVars=Android.OpenGL.NumRemoteProgramCompileServices=4")
                && maximumFPSEntrypoint.contains("export TFT_PERFORMANCE_MODE=1"),
            "maximum FPS profile combines lower 3D scale with asynchronous PSO compilation"
        )
        let keychainScript = try String(
            contentsOf: sourceRoot.deletingLastPathComponent()
                .appendingPathComponent("scripts/login-tft-from-keychain.command"),
            encoding: .utf8
        )
        try expect(
            keychainScript.contains(
                "MACTICIAN_KEYCHAIN_SERVICE:-dev.sergeinaumov.mactician"
            ),
            "Keychain service script"
        )
        let cyrillicRange = "[\(UnicodeScalar(0x0400)!)-\(UnicodeScalar(0x04FF)!)]"
        for file in sourceFiles where ["swift", "command", "json", "plist"].contains(file.pathExtension) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let developerPath = "/Users/" + "example-developer"
            try expect(!text.contains(developerPath), "developer path in \(file.lastPathComponent)")
            try expect(
                text.range(of: cyrillicRange, options: .regularExpression) == nil,
                "non-English text in \(file.lastPathComponent)"
            )
        }

        print("Mactician tests: OK")
    }

    private static func runNativeIPadRuntimeTests(in temporary: URL, sourceRoot: URL) throws {
        let defaultsName = "LauncherTests.native-feature.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw TestFailure("native feature UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        try expect(
            !ExperimentalFeatures.nativeIPadRuntimeEnabled(
                environment: [:], defaults: defaults, debugBuild: false
            ),
            "native runtime feature defaults to off in production"
        )
        try expect(
            ExperimentalFeatures.nativeIPadRuntimeEnabled(
                environment: ["MACTICIAN_ENABLE_NATIVE_IPAD_RUNTIME": "1"],
                defaults: defaults,
                debugBuild: false
            ),
            "native runtime environment feature gate"
        )
        defaults.set(true, forKey: ExperimentalFeatures.nativeIPadRuntimeDefaultsKey)
        try expect(
            ExperimentalFeatures.nativeIPadRuntimeEnabled(
                environment: [:], defaults: defaults, debugBuild: false
            ),
            "native runtime internal defaults feature gate"
        )
        try expect(
            GameRuntimeSelection.restoredKind(savedValue: nil, nativeEnabled: true) == .androidEmulator
                && GameRuntimeSelection.restoredKind(
                    savedValue: GameRuntimeKind.nativeIPadExperimental.rawValue,
                    nativeEnabled: false
                ) == .androidEmulator
                && GameRuntimeSelection.restoredKind(
                    savedValue: GameRuntimeKind.nativeIPadExperimental.rawValue,
                    nativeEnabled: true
                ) == .nativeIPadExperimental,
            "Android remains the default and disabled native selection is ignored"
        )
        for locked in [true] {
            try expect(
                !GameRuntimeSelection.canSelect(
                    .nativeIPadExperimental,
                    nativeEnabled: true,
                    stateMachineLocked: locked,
                    androidRunning: false,
                    nativeRunning: false
                ),
                "runtime selection is locked while launching, playing, or stopping"
            )
        }
        try expect(
            !GameRuntimeSelection.canSelect(
                .nativeIPadExperimental,
                nativeEnabled: false,
                stateMachineLocked: false,
                androidRunning: false,
                nativeRunning: false
            )
                && !GameRuntimeSelection.canSelect(
                    .nativeIPadExperimental,
                    nativeEnabled: true,
                    stateMachineLocked: false,
                    androidRunning: true,
                    nativeRunning: false
                )
                && !GameRuntimeSelection.canSelect(
                    .androidEmulator,
                    nativeEnabled: true,
                    stateMachineLocked: false,
                    androidRunning: false,
                    nativeRunning: true
                ),
            "runtime selection rejects disabled or concurrently active backends"
        )

        let fixtureRoot = temporary.appendingPathComponent("native-ipad", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        let ownApp = try makeFakeApplication(in: fixtureRoot, name: "Mactician")
        let preparedApp = try makeFakeApplication(in: fixtureRoot, name: "PreparedTFT")
        let validator = NativeIPadRuntimeValidator(
            architectureInspector: NativeArchitectureInspectorStub(architectures: ["arm64"]),
            signatureInspector: NativeSignatureInspectorStub(kind: .adHoc),
            hostArchitecture: { "arm64" },
            macticianBundleURL: { ownApp }
        )
        let descriptor = try validator.validate(preparedApp)
        try expect(
            descriptor.bundleIdentifier == "dev.example.PreparedTFT"
                && descriptor.displayName == "PreparedTFT"
                && descriptor.shortVersion == "1.2.3"
                && descriptor.buildVersion == "45"
                && descriptor.architectures == ["arm64"]
                && descriptor.signatureKind == .adHoc
                && descriptor.canonicalURL == preparedApp.standardizedFileURL.resolvingSymlinksInPath(),
            "valid prepared application descriptor"
        )
        let systemBookmark = try NativeIPadBookmarking.system.create(preparedApp)
        let systemResolvedBookmark = try NativeIPadBookmarking.system.resolve(systemBookmark)
        try expect(
            !systemResolvedBookmark.stale
                && systemResolvedBookmark.url.standardizedFileURL.resolvingSymlinksInPath()
                    == descriptor.canonicalURL,
            "system bookmark resolves the selected application across launches"
        )
        let iOSLayoutApp = try makeFakeApplication(
            in: fixtureRoot,
            name: "IOSLayout",
            iOSBundleLayout: true
        )
        try expect(
            try validator.validate(iOSLayoutApp).executableName == "IOSLayout",
            "iOS-style application bundle layout"
        )
        let fakeHome = URL(fileURLWithPath: "/Users/example")
        try expect(
            NativeIPadDiagnostics.displayPath(
                URL(fileURLWithPath: "/Users/example/Applications/Game.app"),
                homeDirectory: fakeHome
            ) == "~/Applications/Game.app"
                && NativeIPadDiagnostics.displayMessage(
                    "Failed at /Users/example/Applications/Game.app",
                    homeDirectory: fakeHome
                ) == "Failed at ~/Applications/Game.app",
            "native diagnostics abbreviate the home directory"
        )

        let missingInfo = try makeFakeApplication(in: fixtureRoot, name: "MissingInfo")
        try FileManager.default.removeItem(
            at: missingInfo.appendingPathComponent("Contents/Info.plist")
        )
        try expectValidationFailure(validator, url: missingInfo, contains: "Info.plist")

        let missingIdentifier = try makeFakeApplication(
            in: fixtureRoot,
            name: "MissingIdentifier",
            infoOverrides: ["CFBundleIdentifier": ""]
        )
        try expectValidationFailure(validator, url: missingIdentifier, contains: "CFBundleIdentifier")

        let missingExecutable = try makeFakeApplication(
            in: fixtureRoot,
            name: "MissingExecutable",
            createExecutable: false
        )
        try expectValidationFailure(validator, url: missingExecutable, contains: "executable is missing")

        let nonIPadApplication = try makeFakeApplication(
            in: fixtureRoot,
            name: "NonIPad",
            infoOverrides: ["UIDeviceFamily": [1]]
        )
        try expectValidationFailure(
            validator,
            url: nonIPadApplication,
            contains: "iPad compatibility"
        )

        let intelValidator = NativeIPadRuntimeValidator(
            architectureInspector: NativeArchitectureInspectorStub(architectures: ["x86_64"]),
            signatureInspector: NativeSignatureInspectorStub(kind: .developerID),
            hostArchitecture: { "arm64" },
            macticianBundleURL: { ownApp }
        )
        try expectValidationFailure(intelValidator, url: preparedApp, contains: "no arm64 slice")
        try expectValidationFailure(
            validator,
            url: fixtureRoot.appendingPathComponent("not-an-app"),
            contains: ".app extension"
        )
        try expectValidationFailure(validator, url: ownApp, contains: "cannot be selected")

        let nestedOwnApp = try makeFakeApplication(
            in: ownApp.appendingPathComponent("Contents", isDirectory: true),
            name: "Nested"
        )
        try expectValidationFailure(validator, url: nestedOwnApp, contains: "cannot be selected")

        let emptyVersionApp = try makeFakeApplication(
            in: fixtureRoot,
            name: "EmptyVersion",
            infoOverrides: ["CFBundleShortVersionString": "", "CFBundleVersion": " "]
        )
        let emptyVersionDescriptor = try validator.validate(emptyVersionApp)
        try expect(
            emptyVersionDescriptor.shortVersion == nil && emptyVersionDescriptor.buildVersion == nil,
            "empty application versions are optional"
        )

        let symlink = fixtureRoot.appendingPathComponent("PreparedLink.app")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: preparedApp)
        try expect(
            try validator.validate(symlink).canonicalURL == preparedApp.standardizedFileURL,
            "top-level application symlink is canonicalized"
        )

        let corruptSignatureValidator = NativeIPadRuntimeValidator(
            architectureInspector: NativeArchitectureInspectorStub(architectures: ["arm64"]),
            signatureInspector: NativeSignatureInspectorStub(kind: .otherValid, shouldFail: true),
            hostArchitecture: { "arm64" },
            macticianBundleURL: { ownApp }
        )
        try expectValidationFailure(
            corruptSignatureValidator,
            url: preparedApp,
            contains: "invalid code signature"
        )

        var lipoExecutable: URL?
        var lipoArguments: [String] = []
        let systemArchitectureInspector = SystemNativeIPadArchitectureInspector { executable, arguments in
            lipoExecutable = executable
            lipoArguments = arguments
            return "arm64 x86_64\n"
        }
        let shellLikePath = URL(fileURLWithPath: "/tmp/game; touch never-executed")
        try expect(
            try systemArchitectureInspector.architectures(of: shellLikePath) == ["arm64", "x86_64"]
                && lipoExecutable?.path == "/usr/bin/lipo"
                && lipoArguments == ["-archs", shellLikePath.path],
            "architecture inspection uses fixed lipo arguments without a shell"
        )

        let stateURL = fixtureRoot.appendingPathComponent("state/native-ipad-state.json")
        let bookmarking = NativeIPadBookmarking(
            create: { Data($0.path.utf8) },
            resolve: { data in
                guard let path = String(data: data, encoding: .utf8) else {
                    throw TestFailure("bookmark encoding")
                }
                return (URL(fileURLWithPath: path), false)
            }
        )
        let stateStore = NativeIPadRuntimeStateStore(stateURL: stateURL, bookmarking: bookmarking)
        let validatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try stateStore.save(descriptor: descriptor, validatedAt: validatedAt)
        guard case let .loaded(savedState, savedURL) = stateStore.load() else {
            throw TestFailure("saved native state load")
        }
        try expect(
            savedState.schemaVersion == 1
                && savedState.descriptor == descriptor
                && savedState.lastValidatedAt == validatedAt
                && savedState.sourceKind == .userSelectedApplicationBundle
                && savedURL == descriptor.canonicalURL,
            "native state round trip and canonical path"
        )
        try stateStore.save(
            descriptor: descriptor,
            lastError: "local validation error",
            validatedAt: validatedAt
        )
        guard case let .loaded(errorState, _) = stateStore.load() else {
            throw TestFailure("native state local error load")
        }
        try expect(
            errorState.lastError == "local validation error",
            "native state stores a local-only validation error"
        )

        let staleStore = NativeIPadRuntimeStateStore(
            stateURL: stateURL,
            bookmarking: NativeIPadBookmarking(
                create: bookmarking.create,
                resolve: { _ in (descriptor.canonicalURL, true) }
            )
        )
        guard case let .invalid(staleMessage) = staleStore.load() else {
            throw TestFailure("stale bookmark rejection")
        }
        try expect(staleMessage.contains("stale"), "stale bookmark diagnostic")

        var stateObject = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL))
            as? [String: Any] ?? [:]
        stateObject["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: stateObject).write(to: stateURL, options: .atomic)
        guard case let .invalid(schemaMessage) = stateStore.load() else {
            throw TestFailure("unknown native state schema rejection")
        }
        try expect(schemaMessage.contains("Unsupported"), "unknown native state schema diagnostic")

        try Data("truncated".utf8).write(to: stateURL, options: .atomic)
        guard case .invalid = stateStore.load() else {
            throw TestFailure("corrupt native state rejection")
        }
        var androidState = InstallState()
        androidState.stage = .ready
        androidState.gameVersion = "android-state"
        let androidStateURL = fixtureRoot.appendingPathComponent("android-install-state.json")
        try SystemServices.saveState(androidState, to: androidStateURL)
        try expect(
            SystemServices.loadState(from: androidStateURL).gameVersion == "android-state",
            "corrupt native state does not modify Android install state"
        )

        try stateStore.save(descriptor: descriptor, validatedAt: validatedAt)
        let externalContainer = fixtureRoot.appendingPathComponent("external-container", isDirectory: true)
        try FileManager.default.createDirectory(at: externalContainer, withIntermediateDirectories: true)
        let androidAVDMarker = fixtureRoot.appendingPathComponent("avd/TftPBE.avd/config.ini")
        try FileManager.default.createDirectory(
            at: androidAVDMarker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("android avd".utf8).write(to: androidAVDMarker)
        let appExecutable = preparedApp.appendingPathComponent("Contents/MacOS/PreparedTFT")
        let executableBeforeRepair = try Data(contentsOf: appExecutable)
        _ = try validator.validate(preparedApp)
        try expect(
            try Data(contentsOf: appExecutable) == executableBeforeRepair,
            "native repair only revalidates the external bundle"
        )
        try stateStore.reset()
        try expect(
            !FileManager.default.fileExists(atPath: stateURL.path)
                && FileManager.default.fileExists(atPath: preparedApp.path)
                && FileManager.default.fileExists(atPath: externalContainer.path)
                && FileManager.default.fileExists(atPath: androidAVDMarker.path)
                && SystemServices.loadState(from: androidStateURL).gameVersion == "android-state",
            "native reset removes only native state"
        )

        let deletedApp = try makeFakeApplication(in: fixtureRoot, name: "DeletedAfterSave")
        let deletedDescriptor = try validator.validate(deletedApp)
        try stateStore.save(descriptor: deletedDescriptor)
        try FileManager.default.removeItem(at: deletedApp)
        try expectValidationFailure(validator, url: deletedDescriptor.canonicalURL, contains: "no longer exists")

        try runNativeLifecycleTests(
            descriptor: descriptor,
            validator: validator
        )

        let settingsSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/LauncherSettingsView.swift"),
            encoding: .utf8
        )
        let stateViewsSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/LauncherStateViews.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/LauncherModel.swift"),
            encoding: .utf8
        )
        try expect(
            settingsSource.contains("if model.nativeIPadRuntimeEnabled")
                && settingsSource.contains("if !model.isNativeIPadRuntimeSelected")
                && stateViewsSource.contains("model.nativeIPadDescriptor == nil")
                && stateViewsSource.contains("LauncherNativeIPadRequiredView")
                && modelSource.contains("guard selectedRuntimeKind == .androidEmulator else { return }")
                && modelSource.contains("guard activeRuntimeKind == .androidEmulator else { return }"),
            "native UI is feature-gated, Android controls are hidden, and native telemetry is skipped"
        )

        for localization in ["en", "ru"] {
            let stringsURL = sourceRoot.appendingPathComponent(
                "Resources/\(localization).lproj/Localizable.strings"
            )
            guard let values = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: stringsURL),
                format: nil
            ) as? [String: String] else {
                throw TestFailure("native \(localization) localization")
            }
            for key in [
                "experimental.title", "experimental.runtime.android",
                "experimental.runtime.native_ipad", "native_ipad.choose",
                "native_ipad.not_selected.title", "native_ipad.ready.title",
                "native_ipad.disclaimer"
            ] {
                try expect(values[key]?.isEmpty == false, "native localization key \(localization): \(key)")
            }
        }
    }

    private static func runNativeLifecycleTests(
        descriptor: NativeIPadAppDescriptor,
        validator: NativeIPadRuntimeValidator
    ) throws {
        let launchedApplication = WorkspaceRunningApplicationStub(
            pid: 4_242,
            bundleIdentifier: descriptor.bundleIdentifier,
            bundleURL: descriptor.canonicalURL
        )
        let workspace = WorkspaceApplicationLauncherStub()
        workspace.openResult = .success(launchedApplication)
        let controller = NativeIPadRuntimeController(
            workspace: workspace,
            validator: validator,
            stopTimeout: 0.01
        )
        var events: [RuntimeEvent] = []
        try controller.launch(configuration: .nativeIPad(descriptor)) { events.append($0) }
        try expect(
            events.last?.event == .ready
                && events.last?.pid == 4_242
                && workspace.openCount == 1
                && workspace.lastOpenedURL == descriptor.canonicalURL
                && workspace.lastActivates == true
                && controller.isRunning,
            "successful native launch tracks the exact returned process"
        )
        workspace.emitTermination(launchedApplication)
        workspace.emitTermination(launchedApplication)
        try expect(
            events.filter { $0.event == .stopped }.count == 1
                && workspace.removeObserverCount == 1
                && !controller.isRunning,
            "native termination is delivered once and observer is cleaned up"
        )

        launchedApplication.isTerminatedValue = false
        try controller.launch(configuration: .nativeIPad(descriptor)) { events.append($0) }
        controller.shutdown()
        try expect(
            launchedApplication.terminateCount == 1,
            "shutdown terminates an application launched by Mactician"
        )

        let attachedApplication = WorkspaceRunningApplicationStub(
            pid: 4_243,
            bundleIdentifier: descriptor.bundleIdentifier,
            bundleURL: descriptor.canonicalURL
        )
        let attachedWorkspace = WorkspaceApplicationLauncherStub()
        attachedWorkspace.existingApplications = [attachedApplication]
        let attachedController = NativeIPadRuntimeController(
            workspace: attachedWorkspace,
            validator: validator,
            stopTimeout: 0.01
        )
        var attachedEvents: [RuntimeEvent] = []
        try attachedController.launch(configuration: .nativeIPad(descriptor)) {
            attachedEvents.append($0)
        }
        try expect(
            attachedEvents.last?.event == .ready
                && attachedWorkspace.openCount == 0
                && attachedApplication.activateCount == 1,
            "already running exact application is activated without a second launch"
        )
        attachedController.shutdown()
        try expect(
            attachedApplication.terminateCount == 0
                && attachedWorkspace.removeObserverCount == 1,
            "shutdown leaves an attached pre-existing application running"
        )

        let gracefulApplication = WorkspaceRunningApplicationStub(
            pid: 4_244,
            bundleIdentifier: descriptor.bundleIdentifier,
            bundleURL: descriptor.canonicalURL,
            terminateImmediately: true
        )
        let gracefulWorkspace = WorkspaceApplicationLauncherStub()
        gracefulWorkspace.openResult = .success(gracefulApplication)
        let gracefulController = NativeIPadRuntimeController(
            workspace: gracefulWorkspace,
            validator: validator,
            stopTimeout: 0.01
        )
        var gracefulEvents: [RuntimeEvent] = []
        try gracefulController.launch(configuration: .nativeIPad(descriptor)) {
            gracefulEvents.append($0)
        }
        gracefulController.stop()
        try waitForRunLoop("graceful native stop") {
            gracefulEvents.contains(where: { $0.event == .stopped })
        }
        try expect(
            gracefulApplication.terminateCount == 1
                && gracefulApplication.forceTerminateCount == 0,
            "native stop prefers graceful termination"
        )

        let stubbornApplication = WorkspaceRunningApplicationStub(
            pid: 4_245,
            bundleIdentifier: descriptor.bundleIdentifier,
            bundleURL: descriptor.canonicalURL,
            terminateImmediately: false,
            forceTerminates: true
        )
        let unrelatedApplication = WorkspaceRunningApplicationStub(
            pid: 9_999,
            bundleIdentifier: descriptor.bundleIdentifier,
            bundleURL: descriptor.canonicalURL
        )
        let stubbornWorkspace = WorkspaceApplicationLauncherStub()
        stubbornWorkspace.openResult = .success(stubbornApplication)
        let stubbornController = NativeIPadRuntimeController(
            workspace: stubbornWorkspace,
            validator: validator,
            stopTimeout: 0.01
        )
        var stubbornEvents: [RuntimeEvent] = []
        try stubbornController.launch(configuration: .nativeIPad(descriptor)) {
            stubbornEvents.append($0)
        }
        stubbornController.stop()
        try waitForRunLoop("forced exact native stop") {
            stubbornEvents.contains(where: { $0.event == .stopped })
        }
        try expect(
            stubbornApplication.terminateCount == 1
                && stubbornApplication.forceTerminateCount == 1
                && unrelatedApplication.terminateCount == 0
                && unrelatedApplication.forceTerminateCount == 0,
            "force termination targets only the exact tracked process after timeout"
        )

        let failureWorkspace = WorkspaceApplicationLauncherStub()
        failureWorkspace.openResult = .failure(TestFailure("open failed"))
        let failureController = NativeIPadRuntimeController(
            workspace: failureWorkspace,
            validator: validator,
            stopTimeout: 0.01
        )
        var failureEvents: [RuntimeEvent] = []
        try failureController.launch(configuration: .nativeIPad(descriptor)) {
            failureEvents.append($0)
        }
        try expect(
            failureEvents.last?.event == .error
                && failureWorkspace.removeObserverCount == 1
                && !failureController.isRunning,
            "native launch failure cleans up its observer"
        )
    }

    private static func makeFakeApplication(
        in root: URL,
        name: String,
        infoOverrides: [String: Any] = [:],
        createExecutable: Bool = true,
        iOSBundleLayout: Bool = false
    ) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = iOSBundleLayout
            ? app
            : contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )
        var info: [String: Any] = [
            "CFBundleIdentifier": "dev.example.\(name)",
            "CFBundleDisplayName": name,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "UIDeviceFamily": [1, 2],
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "45"
        ]
        for (key, value) in infoOverrides { info[key] = value }
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        ).write(
            to: (iOSBundleLayout ? app : contents).appendingPathComponent("Info.plist"),
            options: .atomic
        )
        if createExecutable {
            try Data("fixture executable".utf8).write(
                to: executableDirectory.appendingPathComponent(name),
                options: .atomic
            )
        }
        return app
    }

    private static func expectValidationFailure(
        _ validator: NativeIPadRuntimeValidator,
        url: URL,
        contains expected: String
    ) throws {
        do {
            _ = try validator.validate(url)
            throw TestFailure("validation unexpectedly accepted \(url.lastPathComponent)")
        } catch {
            try expect(
                error.localizedDescription.localizedCaseInsensitiveContains(expected),
                "validation failure for \(url.lastPathComponent): \(expected)"
            )
        }
    }

    private static func waitForRunLoop(
        _ message: String,
        timeout: TimeInterval = 1,
        condition: () -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try expect(condition(), message)
    }

    private static func recursiveFiles(at root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw TestFailure(message) }
    }

    private static func waitFor(
        _ message: String,
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        try expect(condition(), message)
    }
}

private struct NativeArchitectureInspectorStub: NativeIPadArchitectureInspecting {
    let architectures: [String]

    func architectures(of _: URL) throws -> [String] {
        architectures
    }
}

private struct NativeSignatureInspectorStub: NativeIPadSignatureInspecting {
    let kind: NativeIPadSignatureKind
    var shouldFail = false

    func signatureKind(of _: URL) throws -> NativeIPadSignatureKind {
        if shouldFail {
            throw LauncherError.integrity("The selected application has an invalid code signature")
        }
        return kind
    }
}

private final class WorkspaceRunningApplicationStub: WorkspaceRunningApplication {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let bundleURL: URL?
    var isTerminatedValue = false
    var activateCount = 0
    var terminateCount = 0
    var forceTerminateCount = 0
    let terminateImmediately: Bool
    let forceTerminates: Bool

    init(
        pid: pid_t,
        bundleIdentifier: String?,
        bundleURL: URL?,
        terminateImmediately: Bool = false,
        forceTerminates: Bool = true
    ) {
        processIdentifier = pid
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.terminateImmediately = terminateImmediately
        self.forceTerminates = forceTerminates
    }

    var isTerminated: Bool { isTerminatedValue }

    func activate(options _: NSApplication.ActivationOptions) -> Bool {
        activateCount += 1
        return true
    }

    func terminate() -> Bool {
        terminateCount += 1
        if terminateImmediately { isTerminatedValue = true }
        return true
    }

    func forceTerminate() -> Bool {
        forceTerminateCount += 1
        if forceTerminates { isTerminatedValue = true }
        return true
    }
}

private final class WorkspaceApplicationLauncherStub: WorkspaceApplicationLaunching {
    var existingApplications: [any WorkspaceRunningApplication] = []
    var openResult: Result<any WorkspaceRunningApplication, Error>?
    var openCount = 0
    var lastOpenedURL: URL?
    var lastActivates: Bool?
    var removeObserverCount = 0
    private var terminationHandler: ((any WorkspaceRunningApplication) -> Void)?

    func runningApplications(
        withBundleIdentifier bundleIdentifier: String
    ) -> [any WorkspaceRunningApplication] {
        existingApplications.filter { $0.bundleIdentifier == bundleIdentifier }
    }

    func openApplication(
        at applicationURL: URL,
        activates: Bool,
        completion: @escaping (Result<any WorkspaceRunningApplication, Error>) -> Void
    ) {
        openCount += 1
        lastOpenedURL = applicationURL
        lastActivates = activates
        completion(openResult ?? .failure(TestFailure("missing open result")))
    }

    func observeTerminations(
        _ handler: @escaping (any WorkspaceRunningApplication) -> Void
    ) -> Any {
        terminationHandler = handler
        return NSObject()
    }

    func removeTerminationObserver(_: Any) {
        removeObserverCount += 1
        terminationHandler = nil
    }

    func emitTermination(_ application: any WorkspaceRunningApplication) {
        terminationHandler?(application)
    }
}

private final class TelemetryLoaderStub {
    typealias Completion = (Result<(Data, HTTPURLResponse), Error>) -> Void

    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var completions: [Completion] = []

    var requestCount: Int {
        lock.withLock { requests.count }
    }

    var firstEventID: String? {
        event(at: 0)?["event_id"] as? String
    }

    func event(at index: Int) -> [String: Any]? {
        lock.withLock {
            guard requests.indices.contains(index),
                  let body = requests[index].httpBody else {
                return nil
            }
            return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
    }

    func load(
        _ request: URLRequest,
        _ maximumBytes: Int,
        _ completion: @escaping Completion
    ) {
        lock.withLock {
            requests.append(request)
            completions.append(completion)
        }
    }

    func completeFirst(statusCode: Int) {
        let completion: Completion? = lock.withLock {
            guard !completions.isEmpty else { return nil }
            return completions.removeFirst()
        }
        guard let completion,
              let response = HTTPURLResponse(
                url: URL(string: "https://127.0.0.1:1/v1/events")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else { return }
        completion(.success((Data(), response)))
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
