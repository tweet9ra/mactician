import Foundation
import CryptoKit

struct PerformanceRuntime: Codable, Equatable {
    let edition: String
    let gameVersion: String
    let gameVersionCode: Int64
    let gameSHA256: String
    let runtimeRevision: String
    let profileSHA256: String
    var cacheState = "unknown"

    enum CodingKeys: String, CodingKey {
        case edition
        case gameVersion = "game_version", gameVersionCode = "game_version_code"
        case gameSHA256 = "game_sha256", runtimeRevision = "runtime_revision"
        case profileSHA256 = "profile_sha256", cacheState = "cache_state"
    }

    static func current(paths: LauncherPaths, edition: GameEdition, game: GameRelease, effects: EffectsQuality) -> Self {
        let profile = paths.runtimeTemplate.appendingPathComponent("artifacts/tft-18.1-angle-opengl/\(effects.profileFilename)")
        let revision = paths.bundleResources.appendingPathComponent("performance-runtime.sha256")
        let value = (try? String(contentsOf: revision, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Older manifests omit versionCode; zero explicitly means unknown.
        return Self(edition: edition.rawValue, gameVersion: game.version, gameVersionCode: Int64(game.versionCode ?? 0),
                    gameSHA256: game.baseSHA256, runtimeRevision: validHash(value) ? value : "unknown",
                    profileSHA256: (try? Data(contentsOf: profile)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "unknown")
    }

    static func validHash(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

struct PerformanceSegment: Codable, Equatable {
    let scene: String
    let stageBand: String
    let ageBand: String
    var windows: Int64 = 0
    var sampledMS: Int64 = 0
    var histogram = [Int64](repeating: 0, count: SurfaceFlingerTimeStats.buckets.count)
    enum CodingKeys: String, CodingKey {
        case scene, windows, histogram
        case stageBand = "stage_band", ageBand = "age_band", sampledMS = "sampled_ms"
    }
}

struct PerformanceSnapshot: Codable, Equatable {
    var revision: Int64 = 1
    var status = "starting"
    var elapsedMS: Int64 = 0
    var readyMS: Int64?
    let collector = "sf-timestats-sampled-v1"
    var classifier = "game-log-bracket-v1"
    var runtime: PerformanceRuntime
    var windowsAttempted: Int64 = 0
    var windowsMissing: Int64 = 0
    var backgroundSkipped: Int64 = 0
    var collectorMS: Int64 = 0
    var peakResidentMB: Int64 = 0
    var thermalSamples: [Int64] = [0, 0, 0, 0]
    var segments: [PerformanceSegment] = []
    var diagnostics: PerformanceDiagnostics?

    var terminal: Bool { status != "starting" && status != "running" }
    enum CodingKeys: String, CodingKey {
        case revision, status, collector, classifier, runtime, segments, diagnostics
        case elapsedMS = "elapsed_ms", readyMS = "ready_ms"
        case windowsAttempted = "windows_attempted", windowsMissing = "windows_missing"
        case backgroundSkipped = "background_skipped", collectorMS = "collector_ms"
        case peakResidentMB = "peak_resident_mb", thermalSamples = "thermal_samples"
    }

    mutating func record(_ sample: PerformanceSample) {
        var outcome = sample.missingReason
        var context: String?
        defer { diagnostics?.record(sample, measurement: outcome, context: context) }
        collectorMS += sample.collectorMS
        peakResidentMB = max(peakResidentMB, sample.residentMB)
        if (0..<4).contains(sample.thermalState) { thermalSamples[sample.thermalState] += 1 }
        if runtime.cacheState == "unknown", sample.cacheState != "unknown" { runtime.cacheState = sample.cacheState }
        if sample.background { backgroundSkipped += 1; return }
        windowsAttempted += 1
        guard let histogram = sample.histogram else { windowsMissing += 1; return }
        guard sample.durationMS >= 1000, sample.durationMS <= 10000 else {
            outcome = "invalid_duration"; windowsMissing += 1; return
        }
        guard histogram.count == SurfaceFlingerTimeStats.buckets.count,
              histogram.allSatisfy({ $0 >= 0 && $0 <= sample.durationMS }),
              histogram.reduce(0, +) > 0, histogram.reduce(0, +) <= sample.durationMS else {
            outcome = "invalid_histogram"; windowsMissing += 1; return
        }
        let age = max(0, elapsedMS - (readyMS ?? elapsedMS))
        let band = age < 60000 ? "warmup" : age < 1_200_000 ? "early" : "sustained"
        let scene = sample.scene
        let index: Int
        if let existing = segments.firstIndex(where: { $0.scene == scene.scene && $0.stageBand == scene.stageBand && $0.ageBand == band }) {
            index = existing
        } else {
            guard segments.count < 24 else { outcome = "segment_limit"; windowsMissing += 1; return }
            index = segments.count
            segments.append(PerformanceSegment(scene: scene.scene, stageBand: scene.stageBand, ageBand: band))
        }
        outcome = "sampled"
        context = sample.contextReason ?? (["planning", "combat"].contains(scene.scene) ? "gameplay" : scene.scene == "lobby" ? "lobby" : "both_unknown")
        segments[index].windows += 1
        segments[index].sampledMS += sample.durationMS
        for i in histogram.indices { segments[index].histogram[i] += histogram[i] }
    }
}

struct PerformanceScene: Equatable {
    var scene = "unknown"
    var stage = ""
    var stageBand: String {
        guard scene == "planning" || scene == "combat", let round = Int(stage.split(separator: "-").first ?? "") else { return "unknown" }
        return round >= 4 ? "late" : "early"
    }
    static func decode(_ data: Data) -> Self {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? String else { return Self() }
        if ["lobby", "trials_lobby", "mode_select"].contains(state) { return Self(scene: "lobby") }
        guard state == "battle", let stage = json["stage"] as? String,
              stage.range(of: "^[1-9]-[1-9][0-9]?$", options: .regularExpression) != nil,
              let phase = json["phase"] as? String, ["planning", "combat"].contains(phase) else { return Self() }
        return Self(scene: phase, stage: stage)
    }
    static func bracket(_ before: Self, _ after: Self) -> Self { before == after ? before : Self() }
}

struct PerformanceSample {
    var histogram: [Int64]?
    var durationMS: Int64 = 0
    var scene = PerformanceScene()
    var background = false
    var collectorMS: Int64 = 0
    var residentMB: Int64 = 0
    var thermalState = -1
    var cacheState = "unknown"
    var missingReason = "measurement_failed"
    var endpoints: [PerformanceEndpoint] = []
    var contextReason: String?
    var timings: [String: [Int64]] = [:]
    var backoff = false
    var logBefore = GameLogObservation(outcome: "read_failed")
    var gameLog = GameLogObservation(outcome: "read_failed")

    mutating func observe(_ key: String, since began: TimeInterval) {
        PerformanceDiagnostics.observe(key, milliseconds: Int64((ProcessInfo.processInfo.systemUptime - began) * 1000), in: &timings)
    }
}

enum SurfaceFlingerTimeStats {
    static let buckets: [Int64] = Array(0...34) + Array(stride(from: 36, through: 50, by: 2))
        + Array(stride(from: 54, through: 150, by: 4)) + Array(stride(from: 200, through: 1000, by: 50))

    struct Layer: Equatable {
        let name: String
        let histogram: [Int64]
    }

    static func parse(_ text: String, package: String) -> Layer? {
        let needle = "SurfaceView[\(package)/com.epicgames.unreal.GameActivity](BLAST)"
        var matches: [Layer] = []
        var layer: String?
        var expectingHistogram = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("layerName = ") {
                layer = line.contains(needle) ? String(line.dropFirst(12)) : nil
                expectingHistogram = false
            } else if layer != nil, line == "present2present histogram is as below:" {
                expectingHistogram = true
            } else if expectingHistogram, let layer {
                expectingHistogram = false
                let pairs = line.split(separator: " ")
                guard pairs.count == buckets.count else { return nil }
                var histogram: [Int64] = []
                for (index, pair) in pairs.enumerated() {
                    let parts = pair.components(separatedBy: "ms=")
                    guard parts.count == 2, Int64(parts[0]) == buckets[index], let count = Int64(parts[1]), count >= 0, count <= 10_000_000 else { return nil }
                    histogram.append(count)
                }
                matches.append(Layer(name: layer, histogram: histogram))
            }
        }
        return matches.count == 1 ? matches.first : nil
    }

    static func delta(before: Layer, after: Layer) -> [Int64]? {
        guard before.name == after.name, before.histogram.count == buckets.count, after.histogram.count == buckets.count else { return nil }
        let result = zip(before.histogram, after.histogram).map { $1 - $0 }
        guard result.allSatisfy({ $0 >= 0 }), result.reduce(0, +) > 0 else { return nil }
        return result
    }
}
