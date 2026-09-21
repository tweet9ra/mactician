import AppKit
import Darwin
import Foundation

// Short foreground samples bracket frame measurements with bounded passive log reads.
// Recent lifecycle/activity is not a current combat phase or numeric round.
// Raw logs, timestamps, file identity and PIDs never enter telemetry.
final class PerformanceCollector {
    private let queue = DispatchQueue(label: "dev.sergeinaumov.mactician.performance", qos: .utility)
    private let lock = NSLock()
    private let adb: URL
    private let package: String
    private let targetPID: pid_t
    private var lastSampleAt: TimeInterval?
    private let publish: (PerformanceSample) -> Void
    private var stopped = false
    private var process: Process?
    private var enabledTimeStats = false
    private var exposure = "unknown"

    init(adb: URL, package: String, targetPID: pid_t, publish: @escaping (PerformanceSample) -> Void) {
        self.adb = adb; self.package = package
        self.targetPID = targetPID; self.publish = publish
    }

    func start() {
        queue.asyncAfter(deadline: .now() + Double.random(in: 5...15)) { [weak self] in self?.sample() }
    }

    func stop() {
        lock.lock(); stopped = true; let running = process; lock.unlock()
        if running?.isRunning == true { running?.terminate() }
        queue.async { [self] in disableTimeStats() }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private func foreground() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else { return false }
        return windows.contains { row in
            (row[kCGWindowOwnerPID] as? NSNumber)?.int32Value == targetPID &&
                (row[kCGWindowLayer] as? NSNumber)?.intValue == 0
        }
    }

    private func sample() {
        guard !isStopped else { return }
        let began = ProcessInfo.processInfo.systemUptime
        var result = PerformanceSample()
        result.thermalState = ProcessInfo.processInfo.thermalState.rawValue
        if !foreground() {
            result.background = true
        } else {
            if let previous = lastSampleAt { result.observe("interval", since: previous) }
            lastSampleAt = began
            if let data = run(URL(fileURLWithPath: "/bin/ps"), ["-o", "rss=", "-p", String(targetPID)], maximumBytes: 128),
               let text = String(data: data, encoding: .utf8), let kb = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                result.residentMB = min(1_048_576, max(0, kb / 1024))
            }
            if exposure == "unknown" { exposure = cacheExposure() }
            result.cacheState = exposure
            result.logBefore = logContext(sample: &result)
            // Cleanup is required even if the guest enabled TimeStats but its response was lost.
            enabledTimeStats = true
            result.missingReason = "timestats_failed"
            let enableBegan = ProcessInfo.processInfo.systemUptime
            let enabled = shell("dumpsys SurfaceFlinger --timestats -clear -enable") != nil
            result.observe("timestats", since: enableBegan)
            if enabled {
                pause(0.25)
                if let before = timeStats(sample: &result), !isStopped {
                    if foreground() {
                        let measuredAt = ProcessInfo.processInfo.systemUptime
                        var focused = true
                        for _ in 0..<20 {
                            if isStopped { break }
                            Thread.sleep(forTimeInterval: 0.1)
                            if !foreground() { focused = false }
                        }
                        if !isStopped, let after = timeStats(sample: &result) {
                            let measuredUntil = ProcessInfo.processInfo.systemUptime
                            result.durationMS = Int64((measuredUntil - measuredAt) * 1000)
                            if focused, foreground() {
                                result.histogram = SurfaceFlingerTimeStats.delta(before: before, after: after)
                                if result.histogram == nil {
                                    result.missingReason = before.name != after.name ? "layer_changed"
                                        : zip(before.histogram, after.histogram).contains(where: { $1 < $0 }) ? "counter_reset" : "no_frames"
                                }
                            } else { result.missingReason = "lost_focus" }
                        }
                    } else { result.missingReason = "lost_focus" }
                }
            }
            let disableBegan = ProcessInfo.processInfo.systemUptime
            disableTimeStats()
            result.observe("timestats", since: disableBegan)
            result.gameLog = logContext(sample: &result)
            let context = GameLogObservation.bracket(result.logBefore, result.gameLog)
            result.scene = PerformanceScene(scene: context.scene)
            result.contextReason = context.reason
            if !foreground() { result.histogram = nil; result.missingReason = "lost_focus" }
        }
        let totalMS = Int64((ProcessInfo.processInfo.systemUptime - began) * 1000)
        result.collectorMS = max(0, totalMS - (result.durationMS > 0 ? 2000 : 0))
        result.observe("cycle", since: began)
        guard !isStopped else { return }
        // Preserve the randomized cadence and existing wall-time budget.
        let scheduledDelay = Double.random(in: 45...75)
        let delay = max(scheduledDelay, Double(result.collectorMS) / 10)
        result.backoff = !result.background && delay > scheduledDelay
        publish(result)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sample() }
    }

    private func pause(_ seconds: Double) {
        let until = ProcessInfo.processInfo.systemUptime + seconds
        while !isStopped, ProcessInfo.processInfo.systemUptime < until { Thread.sleep(forTimeInterval: 0.05) }
    }

    private func logContext(sample: inout PerformanceSample) -> GameLogObservation {
        guard !isStopped, let command = GameLogObservation.command(package: package) else { return GameLogObservation(outcome: "read_failed") }
        let began = ProcessInfo.processInfo.systemUptime
        defer { sample.observe("game_log", since: began) }
        let data = run(adb, ["-P", "5038", "-s", "emulator-5582", "shell", command],
                       maximumBytes: GameLogObservation.maximumResponseBytes, timeoutSeconds: 2)
        return GameLogObservation.decode(data)
    }

    private func timeStats(sample: inout PerformanceSample) -> SurfaceFlingerTimeStats.Layer? {
        let began = ProcessInfo.processInfo.systemUptime
        defer { sample.observe("timestats", since: began) }
        guard let data = shell("dumpsys SurfaceFlinger --timestats -dump"), let text = String(data: data, encoding: .utf8) else {
            sample.missingReason = "timestats_failed"; return nil
        }
        guard let layer = SurfaceFlingerTimeStats.parse(text, package: package) else {
            sample.missingReason = text.contains("SurfaceView[\(package)/com.epicgames.unreal.GameActivity](BLAST)")
                ? "invalid_histogram" : "layer_not_found"
            return nil
        }
        return layer
    }

    private func cacheExposure() -> String {
        // Fixed allowlisted packages only; never evaluate data received from the server.
        guard [GameEdition.global.packageName, GameEdition.vietnam.packageName].contains(package) else { return "unknown" }
        let command = "p=$(pidof \(package)); [ -n \"$p\" ] && [ -r /proc/$p/maps ] || exit 1; v=$(getprop debug.mactician.vk_view_cache); if grep -q libVkLayer_Mactician_buffer_view_cache.so /proc/$p/maps; then [ \"$v\" = 1 ] && echo enabled || echo unknown; elif [ \"$v\" != 1 ]; then echo disabled; else echo unknown; fi"
        guard let data = shell(command), let text = String(data: data, encoding: .utf8) else { return "unknown" }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["enabled", "disabled"].contains(value) ? value : "unknown"
    }

    private func disableTimeStats() {
        guard enabledTimeStats else { return }
        _ = runADB(["shell", "dumpsys SurfaceFlinger --timestats -disable"], maximumBytes: 1024, allowStopped: true)
        enabledTimeStats = false
    }

    private func shell(_ command: String) -> Data? { runADB(["shell", command], maximumBytes: 2*1024*1024) }

    private func runADB(_ arguments: [String], maximumBytes: Int, allowStopped: Bool = false) -> Data? {
        run(adb, ["-P", "5038", "-s", "emulator-5582"] + arguments, maximumBytes: maximumBytes, allowStopped: allowStopped)
    }

    private func run(_ executable: URL, _ arguments: [String], maximumBytes: Int, allowStopped: Bool = false, timeoutSeconds: Double = 10) -> Data? {
        let child = Process(), output = Pipe()
        child.executableURL = executable; child.arguments = arguments
        child.standardOutput = output; child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        child.environment = ProcessInfo.processInfo.environment.merging([
            "ANDROID_ADB_SERVER_PORT": "5038", "ADB_MDNS_AUTO_CONNECT": ""
        ]) { _,new in new }
        lock.lock()
        guard !stopped || allowStopped else { lock.unlock(); return nil }
        do { try child.run(); process = child; lock.unlock() } catch { lock.unlock(); return nil }
        let deadline = CommandDeadline()
        let timeout = DispatchWorkItem { deadline.terminate(child) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        defer {
            timeout.cancel()
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
            try? output.fileHandleForReading.close()
            lock.lock(); if process === child { process = nil }; lock.unlock()
        }
        var data = Data()
        while let chunk = try? output.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            guard data.count + chunk.count <= maximumBytes else { return nil }
            data.append(chunk)
        }
        child.waitUntilExit()
        return !deadline.expired && child.terminationStatus == 0 ? data : nil
    }
}

// The deadline fires on another queue; keep its diagnostic flag synchronized.
private final class CommandDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var expired: Bool { lock.lock(); defer { lock.unlock() }; return fired }
    func terminate(_ child: Process) {
        lock.lock(); defer { lock.unlock() }
        if child.isRunning { fired = true; kill(child.processIdentifier, SIGKILL) }
    }
}
