import AppKit
import CoreGraphics
import Foundation

struct SurfaceFlingerFPSResult: Equatable {
    let framesPerSecond: Double
    let newestTimestamp: UInt64
}

enum SurfaceFlingerFPS {
    private static let maximumTimestamp: UInt64 = 9_000_000_000_000_000_000
    private static let initialWindowNanoseconds: UInt64 = 1_250_000_000
    private static let maximumFrameNanoseconds: UInt64 = 1_000_000_000

    static func gameLayer(from output: String, package: String) -> String? {
        let needle = "SurfaceView[\(package)/com.epicgames.unreal.GameActivity](BLAST)"
        for rawLine in output.split(separator: "\n").reversed() {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.contains(needle) else { continue }
            guard line.hasPrefix("RequestedLayerState{") else { return line }

            var payload = String(line.dropFirst("RequestedLayerState{".count))
            if let parentRange = payload.range(of: " parentId=", options: .backwards) {
                payload = String(payload[..<parentRange.lowerBound])
            } else if payload.hasSuffix("}") {
                payload.removeLast()
            }
            return payload.isEmpty ? nil : payload
        }
        return nil
    }

    static func presentationTimestamps(from output: String) -> [UInt64] {
        output.split(separator: "\n").compactMap { line in
            let columns = line.split(whereSeparator: { $0.isWhitespace })
            guard columns.count >= 2,
                  let timestamp = UInt64(columns[1]),
                  timestamp > 0,
                  timestamp < maximumTimestamp else {
                return nil
            }
            return timestamp
        }
    }

    static func estimate(
        timestamps: [UInt64],
        after previousTimestamp: UInt64?
    ) -> SurfaceFlingerFPSResult? {
        let ordered = Array(Set(timestamps)).sorted()
        guard let newest = ordered.last,
              previousTimestamp.map({ newest > $0 }) ?? true else {
            return nil
        }

        let initialFloor = newest > initialWindowNanoseconds
            ? newest - initialWindowNanoseconds
            : 0
        var anchors = ordered.filter { timestamp in
            if let previousTimestamp { return timestamp > previousTimestamp }
            return timestamp >= initialFloor
        }
        if let previousTimestamp,
           newest - previousTimestamp <= maximumFrameNanoseconds,
           anchors.first.map({ previousTimestamp < $0 }) ?? false {
            anchors.insert(previousTimestamp, at: 0)
        }
        guard anchors.count >= 3 else { return nil }

        var total: UInt64 = 0
        var count = 0
        for index in 1 ..< anchors.count {
            let delta = anchors[index] - anchors[index - 1]
            guard delta > 0, delta <= maximumFrameNanoseconds else { continue }
            total += delta
            count += 1
        }
        guard count >= 2 else { return nil }

        let meanNanoseconds = Double(total) / Double(count)
        let fps = 1_000_000_000 / meanNanoseconds
        guard fps >= 1, fps <= 240 else { return nil }
        return SurfaceFlingerFPSResult(framesPerSecond: fps, newestTimestamp: newest)
    }
}

private struct FPSOverlayUpdate {
    let fps: Int?
    let emulatorWindow: CGRect?
}

private final class FPSOverlayView: NSView {
    var value = "— FPS" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.42).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        background.lineWidth = 1
        background.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.78)
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(
            at: NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            ),
            withAttributes: attributes
        )
    }
}

private final class FPSOverlayPanel {
    private static let size = NSSize(width: 62, height: 20)
    private let panel: NSPanel
    private let content: FPSOverlayView

    init() {
        _ = NSApplication.shared
        content = FPSOverlayView(frame: NSRect(origin: .zero, size: Self.size))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = content
    }

    func update(_ update: FPSOverlayUpdate, targetPID: pid_t) {
        guard let window = update.emulatorWindow,
              NSRunningApplication(processIdentifier: targetPID)?.isActive == true,
              let origin = Self.panelOrigin(for: window) else {
            hide()
            return
        }

        content.value = update.fps.map { "\($0) FPS" } ?? "— FPS"
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    private static func panelOrigin(for quartzWindow: CGRect) -> NSPoint? {
        var selected: (screen: NSScreen, quartz: CGRect, area: CGFloat)?
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else { continue }
            let quartzScreen = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let intersection = quartzScreen.intersection(quartzWindow)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if selected.map({ area > $0.area }) ?? true {
                selected = (screen, quartzScreen, area)
            }
        }
        guard let selected else { return nil }

        let left = selected.screen.frame.minX + quartzWindow.minX - selected.quartz.minX
        let top = selected.screen.frame.maxY - quartzWindow.minY + selected.quartz.minY
        return NSPoint(
            x: left + quartzWindow.width - Self.size.width - 10,
            y: top - Self.size.height - 5
        )
    }
}

private struct FPSOverlayConfiguration {
    let targetPID: pid_t
    let adb: URL
    let package: String
}

private final class FPSOverlaySession {
    private static let pollInterval: TimeInterval = 2

    private let configuration: FPSOverlayConfiguration
    private let publish: (FPSOverlayUpdate) -> Void
    private let queue = DispatchQueue(label: "dev.sergeinaumov.mactician.fps-overlay")
    private let lock = NSLock()
    private var stopped = false
    private var timer: DispatchSourceTimer?
    private var process: Process?
    private var layer: String?
    private var previousTimestamp: UInt64?

    init(configuration: FPSOverlayConfiguration, publish: @escaping (FPSOverlayUpdate) -> Void) {
        self.configuration = configuration
        self.publish = publish
    }

    func start() {
        queue.async { [self] in installTimer() }
    }

    func stop() {
        let (timer, process) = withLock {
            stopped = true
            let timer = self.timer
            self.timer = nil
            let process = self.process
            self.process = nil
            return (timer, process)
        }
        timer?.setEventHandler {}
        timer?.cancel()
        if process?.isRunning == true { process?.terminate() }
    }

    private func installTimer() {
        guard !isStopped else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(150))
        timer.resume()
        let installed = withLock {
            guard !stopped else { return false }
            self.timer = timer
            return true
        }
        if !installed { timer.cancel() }
    }

    private func poll() {
        guard !isStopped else { return }
        let window = Self.mainWindowBounds(for: configuration.targetPID)
        guard window != nil else {
            publish(FPSOverlayUpdate(fps: nil, emulatorWindow: nil))
            return
        }

        if layer == nil {
            layer = queryLayer()
            previousTimestamp = nil
        }
        guard let layer else {
            publish(FPSOverlayUpdate(fps: nil, emulatorWindow: nil))
            return
        }
        guard let output = runADB(["shell", "dumpsys SurfaceFlinger --latency \(Self.shellQuote(layer))"]) else {
            publish(FPSOverlayUpdate(fps: nil, emulatorWindow: window))
            return
        }

        let timestamps = SurfaceFlingerFPS.presentationTimestamps(from: output)
        guard !timestamps.isEmpty else {
            self.layer = nil
            previousTimestamp = nil
            publish(FPSOverlayUpdate(fps: nil, emulatorWindow: nil))
            return
        }
        if let result = SurfaceFlingerFPS.estimate(
            timestamps: timestamps,
            after: previousTimestamp
        ) {
            previousTimestamp = result.newestTimestamp
            publish(FPSOverlayUpdate(
                fps: Int(result.framesPerSecond.rounded()),
                emulatorWindow: window
            ))
        } else {
            publish(FPSOverlayUpdate(fps: nil, emulatorWindow: window))
        }
    }

    private func queryLayer() -> String? {
        guard let output = runADB(["shell", "dumpsys SurfaceFlinger --list"]) else { return nil }
        return SurfaceFlingerFPS.gameLayer(from: output, package: configuration.package)
    }

    private func runADB(_ arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = configuration.adb
        process.arguments = ["-P", "5038", "-s", "emulator-5582"] + arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.merging([
            "ANDROID_ADB_SERVER_PORT": "5038",
            "ADB_MDNS_AUTO_CONNECT": ""
        ]) { _, new in new }

        let registered = withLock {
            guard !stopped else { return false }
            self.process = process
            return true
        }
        guard registered else { return nil }
        defer {
            withLock {
                if self.process === process { self.process = nil }
            }
        }

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !isStopped, process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var isStopped: Bool { withLock { stopped } }

    private static func mainWindowBounds(for targetPID: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(kCGNullWindowID)
        ) as? [[CFString: Any]] else { return nil }

        var best: (bounds: CGRect, area: CGFloat)?
        for window in windows {
            guard (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value == targetPID,
                  (window[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let rawBounds = window[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds),
                  bounds.width >= 500,
                  bounds.height >= 300,
                  bounds.width > bounds.height else {
                continue
            }
            let area = bounds.width * bounds.height
            if best.map({ area > $0.area }) ?? true { best = (bounds, area) }
        }
        return best?.bounds
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class FPSOverlayService {
    private let panel = FPSOverlayPanel()
    private var session: FPSOverlaySession?

    deinit {
        stop()
    }

    func start(targetPID: pid_t, adb: URL, package: String) {
        stop()
        let session = FPSOverlaySession(
            configuration: FPSOverlayConfiguration(targetPID: targetPID, adb: adb, package: package)
        ) { [weak self] update in
            DispatchQueue.main.async {
                self?.panel.update(update, targetPID: targetPID)
            }
        }
        self.session = session
        session.start()
    }

    func stop() {
        session?.stop()
        session = nil
        panel.hide()
    }
}
