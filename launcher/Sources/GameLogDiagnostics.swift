import Foundation

// Allowlisted log evidence. Departure events describe recent match activity,
// never a current planning/combat phase or an exact round.
struct GameLogObservation: Codable, Equatable {
    var outcome: String
    var lifecycle = "none"
    var lifecycleAge = "none"
    var phaseEvent = "none"
    var phaseAge = "none"

    // Local bracket metadata is deliberately excluded from Codable/telemetry.
    var context = "unknown"
    var identity: String?
    var capturedAt: Double?
    var fileSize: Int64?
    enum CodingKeys: String, CodingKey { case outcome, lifecycle, lifecycleAge, phaseEvent, phaseAge }

    static func bracket(_ before: Self, _ after: Self) -> (scene: String, reason: String) {
        guard before.outcome == "observed", after.outcome == "observed" else { return ("unknown", "endpoint_failed") }
        guard let identity = before.identity, identity == after.identity,
              let firstSize = before.fileSize, let lastSize = after.fileSize, lastSize >= firstSize,
              let first = before.capturedAt, let last = after.capturedAt, last > first, last-first <= 15 else {
            return ("unknown", "log_discontinuity")
        }
        guard before.context == after.context else { return ("unknown", "state_changed") }
        return (before.context, before.context == "unknown" ? "both_unknown" : before.context)
    }

    static let maximumLogBytes = 65536
    static let maximumResponseBytes = maximumLogBytes + 4096

    static func command(package: String) -> String? {
        guard ["com.riotgames.league.teamfighttactics", "com.riotgames.league.teamfighttacticsvn"].contains(package) else { return nil }
        // No root, log-level changes, writes, or process attachment. Snapshot the
        // process and file on both sides so replacement/truncation fails closed.
        return """
        p=$(pidof \(package)); case "$p" in ''|*[!0-9]*) echo game_not_running; exit 0;; esac
        f=/sdcard/Android/data/\(package)/files/UnrealGame/TFT/TFT/Saved/Logs/TFT.log
        [ -r "$f" ] || { echo log_unavailable; exit 0; }
        echo snapshot
        date +%s
        cat /proc/uptime
        getconf CLK_TCK
        cat /proc/$p/stat
        stat -c '%i %s' "$f"
        tail -c \(maximumLogBytes) "$f"
        printf '\\nMACTICIAN_LOG_END\\n'
        stat -c '%i %s' "$f"
        cat /proc/$p/stat
        """
    }

    static func decode(_ data: Data?) -> Self {
        guard let data else { return Self(outcome: "read_failed") }
        guard data.count <= maximumResponseBytes else {
            return Self(outcome: "invalid_snapshot")
        }
        let text = String(decoding: data, as: UTF8.self)
        let status = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["game_not_running", "log_unavailable"].contains(status) { return Self(outcome: status) }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 10, lines[0] == "snapshot", lines[lines.count-3] == "MACTICIAN_LOG_END",
              let now = Double(lines[1]), now.isFinite,
              let uptimeText = lines[2].split(separator: " ").first, let uptime = Double(uptimeText), uptime.isFinite, uptime > 0,
              let hz = Double(lines[3]), hz > 0, hz <= 10000,
              let process = processIdentity(lines[4]), let finalProcess = processIdentity(lines.last!),
              let file = fileIdentity(lines[5]), let finalFile = fileIdentity(lines[lines.count-2]) else {
            return Self(outcome: "invalid_snapshot")
        }
        guard process == finalProcess, file.inode == finalFile.inode, finalFile.size >= file.size else {
            return Self(outcome: "log_changed")
        }
        // Guest clock and /proc start ticks share the same boot. Add one second
        // for the integer date rounding; losing the first event is safer than
        // accepting the previous game's log. No state is carried between reads.
        let processStarted = now - uptime + Double(process.ticks) / hz + 1
        guard processStarted <= now + 1 else { return Self(outcome: "invalid_snapshot") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy.MM.dd-HH.mm.ss:SSS"
        formatter.isLenient = false
        var result = Self(outcome: "observed")
        result.identity = "\(process.pid):\(process.ticks):\(file.inode)"
        result.capturedAt = now
        result.fileSize = file.size
        var lifecycleTime = -Double.infinity, phaseTime = -Double.infinity
        var contextTime = -Double.infinity
        var contextPriority = -1
        func consider(_ context: String, at stamp: Double, priority: Int, maximumAge: Double = 60) {
            // Lifecycle messages for one change may arrive within the same second.
            // Prefer the more specific phase/game-state field over gameflow LOBBY.
            guard now-stamp <= maximumAge,
                  stamp > contextTime+1 || (stamp >= contextTime-1 && priority >= contextPriority) else { return }
            result.context = context; contextTime = stamp; contextPriority = priority
        }
        // Discard a possibly partial first line and an incomplete last line.
        // The command adds a newline before its trailer, so the penultimate
        // payload line is complete only if the original log ended in a newline.
        for line in lines.dropFirst(7).dropLast(4) {
            guard line.hasPrefix("["), line.count >= 25,
                  let close = line.firstIndex(of: "]"),
                  let stamp = formatter.date(from: String(line[line.index(after: line.startIndex)..<close]))?.timeIntervalSince1970,
                  stamp >= processStarted, stamp <= now else { continue }
            for evidence in lifecycleEvidence(line) {
                consider(evidence.context, at: stamp, priority: evidence.priority)
                if stamp >= lifecycleTime, evidence.value != "none" {
                    lifecycleTime = stamp; result.lifecycle = evidence.value; result.lifecycleAge = age(now-stamp)
                }
            }
            if stamp >= phaseTime, line.contains("TFTRuntimePerformanceSubsystem"), (line.contains("Scheduled phase garbage collection") || line.contains("Skipped scheduling garbage collection as it had been recently scheduled")) {
                for (raw, value) in [("PlanningDeparture", "planning_departure"), ("CombatDeparture", "combat_departure"), ("DraftDeparture", "draft_departure")] {
                    if line.contains("Phase[ETFTPhaseType::\(raw)]") {
                        phaseTime = stamp; result.phaseEvent = value; result.phaseAge = age(now-stamp)
                        consider("match_activity", at: stamp, priority: 2)
                    }
                }
            }
        }
        return result
    }

    private static let lifecyclePattern = try! NSRegularExpression(pattern: #""(gameflowPhase|phaseName|gameState)"\s*:\s*"([^"]*)""#)

    private static func lifecycleEvidence(_ line: String) -> [(value: String, context: String, priority: Int)] {
        // Inspect every field, including mixed-field records. A known generic
        // envelope must not hide a newer/unknown specific lifecycle value.
        let text = line as NSString
        return lifecyclePattern.matches(in: line, range: NSRange(location: 0, length: text.length)).map { match in
            switch (text.substring(with: match.range(at: 1)), text.substring(with: match.range(at: 2))) {
            case ("gameflowPhase", "LOBBY"): return ("gameflow_lobby", "lobby", 0)
            case ("phaseName", "MATCHMAKING"): return ("phase_matchmaking", "matchmaking", 1)
            case ("phaseName", "AFK_CHECK"): return ("phase_afk_check", "match_starting", 1)
            case ("phaseName", "CHAMPION_SELECT"): return ("phase_champion_select", "match_starting", 1)
            case ("gameState", "IN_PROGRESS"): return ("state_in_progress", "match_starting", 1)
            default: return ("none", "unknown", 3)
            }
        }
    }

    private static func age(_ seconds: Double) -> String {
        if seconds <= 10 { return "within_10s" }
        if seconds <= 60 { return "within_60s" }
        if seconds <= 300 { return "within_5m" }
        return "older"
    }

    private static func processIdentity(_ line: String) -> (pid: Int64, ticks: Int64)? {
        guard let end = line.lastIndex(of: ")"), let pidText = line.split(separator: " ").first,
              let pid = Int64(pidText), pid > 0 else { return nil }
        let fields = line[line.index(after: end)...].split(separator: " ")
        guard fields.count > 19, let ticks = Int64(fields[19]), ticks >= 0 else { return nil }
        return (pid, ticks)
    }

    private static func fileIdentity(_ line: String) -> (inode: Int64, size: Int64)? {
        let fields = line.split(separator: " ")
        guard fields.count == 2, let inode = Int64(fields[0]), let size = Int64(fields[1]), inode > 0, size >= 0 else { return nil }
        return (inode, size)
    }
}

struct GameLogDiagnostics: Codable, Equatable {
    var reads: [String: Int64] = [:]
    var lifecycle: [String: Int64] = [:]
    var lifecycleAge: [String: Int64] = [:]
    var phaseEvents: [String: Int64] = [:]
    var phaseAge: [String: Int64] = [:]
    var contextsNearEvent: [String: Int64] = [:]

    enum CodingKeys: String, CodingKey {
        case reads, lifecycle
        case lifecycleAge = "lifecycle_age", phaseEvents = "phase_events", phaseAge = "phase_age", contextsNearEvent = "contexts_near_event"
    }

    mutating func record(_ observation: GameLogObservation, context: String?) {
        reads[observation.outcome, default: 0] += 1
        guard observation.outcome == "observed" else { return }
        lifecycle[observation.lifecycle, default: 0] += 1
        lifecycleAge[observation.lifecycleAge, default: 0] += 1
        phaseEvents[observation.phaseEvent, default: 0] += 1
        phaseAge[observation.phaseAge, default: 0] += 1
        if observation.phaseAge == "within_10s", let context { contextsNearEvent[context, default: 0] += 1 }
    }
}
