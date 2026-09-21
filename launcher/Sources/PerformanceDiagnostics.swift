import Foundation

// Cumulative, bounded metadata only. These counters do not change scene labels.
struct PerformanceDiagnostics: Codable, Equatable {
    var version = 3
    var implementation = "game-log-context-v1"
    var language: String
    var measurements: [String: Int64] = [:]
    var endpoints: [String: Int64] = [:]
    var states: [String: Int64] = [:]
    var signals: [String: Int64] = [:]
    var dimensions: [String: Int64] = [:]
    var contexts: [String: Int64] = [:]
    var timings: [String: [Int64]] = [:]
    var backoffWindows: Int64 = 0
    var gameLog: GameLogDiagnostics? = GameLogDiagnostics()

    enum CodingKeys: String, CodingKey {
        case version, implementation, language, measurements, endpoints, states, signals, dimensions, contexts, timings
        case backoffWindows = "backoff_windows"
        case gameLog = "game_log"
    }

    // Noncumulative upper bounds in milliseconds; the final bucket is overflow.
    static let timingBounds: [Int64] = [100, 500, 1000, 2500, 5000, 10000, 30000, 60000, 180000, 600000, Int64.max]

    static func observe(_ key: String, milliseconds: Int64, in timings: inout [String: [Int64]]) {
        let bucket = timingBounds.firstIndex(where: { max(0, milliseconds) <= $0 })!
        timings[key, default: [Int64](repeating: 0, count: timingBounds.count)][bucket] += 1
    }

    mutating func record(_ sample: PerformanceSample, measurement: String, context: String?) {
        if !sample.background { measurements[measurement, default: 0] += 1 }
        if let context { contexts[context, default: 0] += 1 }
        for endpoint in sample.endpoints {
            endpoints[endpoint.reason, default: 0] += 1
            if !endpoint.state.isEmpty { states[endpoint.state, default: 0] += 1 }
            if !endpoint.dimensions.isEmpty { dimensions[endpoint.dimensions, default: 0] += 1 }
            if endpoint.stageRead { signals["stage_read", default: 0] += 1 }
            if !endpoint.phase.isEmpty { signals["phase_read", default: 0] += 1 }
            if let matches = endpoint.dimensionMatch {
                signals[matches ? "dimensions_match" : "dimensions_mismatch", default: 0] += 1
            }
        }
        for (key, counts) in sample.timings {
            for i in counts.indices { timings[key, default: [Int64](repeating: 0, count: Self.timingBounds.count)][i] += counts[i] }
        }
        if sample.backoff { backoffWindows += 1 }
        if !sample.background {
            if version >= 3 { gameLog?.record(sample.logBefore, context: nil) }
            gameLog?.record(sample.gameLog, context: context)
        }
    }
}

struct PerformanceEndpoint {
    static let states = Set(["patch_available", "patch_ready", "patching", "cosmetic_notice", "lobby", "mode_select",
        "trials_lobby", "match_found", "match_accepted", "trial_ended", "settings", "surrender_confirm", "trial_results",
        "login_service_error", "battle", "trial_choice", "disconnected", "login", "error", "unknown"])
    static let dimensions = Set(["1920x1080", "2560x1440", "2880x1620", "3200x1800", "3840x2160", "other"])
    static let helperErrors = Set(["unsupported_dimensions", "invalid_image", "ocr_failed", "helper_failed"])

    var scene = PerformanceScene()
    var reason: String
    var state = ""
    var stage = ""
    var phase = ""
    var stageRead = false
    var dimensions = ""
    var dimensionMatch: Bool?
    // Capture start is a conservative timestamp: ADB does not expose the exact capture instant.
    var capturedAt: TimeInterval?

    static func decode(_ data: Data, expectedDimensions: String) -> Self {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["diagnostics_version"] as? Int == 1 else { return Self(reason: "invalid_response") }
        let dimensions = json["dimensions"] as? String ?? ""
        if let error = json["error"] as? String {
            guard helperErrors.contains(error), dimensions.isEmpty || Self.dimensions.contains(dimensions) else {
                return Self(reason: "invalid_response")
            }
            return Self(reason: error, dimensions: dimensions,
                dimensionMatch: dimensions.isEmpty ? nil : dimensions == expectedDimensions)
        }
        guard let state = json["state"] as? String, Self.states.contains(state), Self.dimensions.contains(dimensions),
              let stageRead = json["stage_read"] as? Bool, let hud = json["battle_hud"] as? Bool else {
            return Self(reason: "invalid_response")
        }
        let stage = json["observed_stage"] as? String ?? ""
        let phase = json["phase"] as? String ?? ""
        guard (stage.isEmpty || stage.range(of: "^[1-9]-[1-9][0-9]?$", options: .regularExpression) != nil),
              ["", "planning", "combat", "post_combat"].contains(phase), stageRead == !stage.isEmpty else {
            return Self(reason: "invalid_response")
        }
        let scene = PerformanceScene.decode(data)
        let reason: String
        if scene.scene == "combat" || scene.scene == "planning" { reason = "gameplay" }
        else if scene.scene == "lobby" { reason = "lobby" }
        else if state != "unknown" && state != "battle" { reason = "non_gameplay" }
        else if !stageRead && (hud || state == "battle") { reason = "stage_unreadable" }
        else if state == "battle" { reason = "phase_unrecognized" }
        else { reason = "insufficient_evidence" }
        return Self(scene: scene, reason: reason, state: state, stage: stage, phase: phase, stageRead: stageRead,
            dimensions: dimensions, dimensionMatch: dimensions == expectedDimensions)
    }

    static func context(_ before: Self, _ after: Self) -> String {
        let scene = PerformanceScene.bracket(before.scene, after.scene).scene
        if scene == "combat" || scene == "planning" { return "gameplay" }
        if scene == "lobby" { return "lobby" }
        if before.state.isEmpty || after.state.isEmpty { return "endpoint_failed" }
        if before.state != after.state { return "state_changed" }
        if !before.stage.isEmpty, !after.stage.isEmpty, before.stage != after.stage { return "round_changed" }
        if !before.phase.isEmpty, !after.phase.isEmpty, before.phase != after.phase { return "phase_changed" }
        if before.reason == "non_gameplay", after.reason == "non_gameplay" { return "non_gameplay" }
        return (before.scene.scene == "unknown") == (after.scene.scene == "unknown") ? "both_unknown" : "one_unknown"
    }
}
