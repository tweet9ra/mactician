import AppKit
import ApplicationServices
import Darwin
import Foundation

private struct BridgeConfiguration {
    let targetPID: pid_t
    let packageName: String
    let targetBundleID: String
    let adb: URL
    let width: Int
    let height: Int
}

private enum BridgeAction {
    case shop
    case reroll
    case buyXP
    case sellUnit
    case toggleItemsAndTraits
    case togglePlayersAndDamage
}

struct BridgeRelativePoint: Equatable {
    let x: Double
    let y: Double

    func pixels(width: Int, height: Int) -> (x: Int, y: Int) {
        (
            min(width - 1, max(0, Int((Double(width) * x).rounded()))),
            min(height - 1, max(0, Int((Double(height) * y).rounded())))
        )
    }
}

enum BridgeHotkeyTarget {
    static let shop = BridgeRelativePoint(x: 0.96, y: 0.93)
    static let reroll = BridgeRelativePoint(x: 0.955, y: 0.79)
    static let buyXP = BridgeRelativePoint(x: 0.032, y: 0.925)
    static let traits = BridgeRelativePoint(x: 0.029, y: 0.04)
    static let items = BridgeRelativePoint(x: 0.059, y: 0.04)
    static let damage = BridgeRelativePoint(x: 0.947, y: 0.04)
    static let players = BridgeRelativePoint(x: 0.975, y: 0.04)
    static let sellLeft = BridgeRelativePoint(x: 0.025, y: 0.94)
    static let sellRight = BridgeRelativePoint(x: 0.975, y: 0.94)
}

enum BridgeUnitSale {
    static func source(cursor: CGPoint, window: CGRect, width: Int, height: Int) -> BridgeRelativePoint? {
        guard width > 0, height > 0, window.width > 0 else { return nil }
        // The emulator keeps the guest aspect ratio, with its title bar above the image.
        let imageHeight = window.width * CGFloat(height) / CGFloat(width)
        let titleHeight = window.height - imageHeight
        guard titleHeight >= -1, titleHeight <= 80 else { return nil }
        let image = CGRect(x: window.minX, y: window.maxY - imageHeight,
                           width: window.width, height: imageHeight)
        guard image.contains(cursor) else { return nil }
        return BridgeRelativePoint(x: (cursor.x - image.minX) / image.width,
                                   y: (cursor.y - image.minY) / image.height)
    }

    static func target(from source: BridgeRelativePoint) -> BridgeRelativePoint {
        source.x <= 0.5 ? BridgeHotkeyTarget.sellLeft : BridgeHotkeyTarget.sellRight
    }

    static func command(from source: BridgeRelativePoint, width: Int, height: Int) -> String {
        let start = source.pixels(width: width, height: height)
        let end = target(from: source).pixels(width: width, height: height)
        return "input motionevent DOWN \(start.x) \(start.y); sleep 0.08; "
            + "input motionevent MOVE \(end.x) \(end.y); "
            + "input motionevent UP \(end.x) \(end.y)\n"
    }
}

enum BridgeKeyboardBinding {
    static let reroll: UInt16 = 2
    static let buyXP: UInt16 = 3
    static let sellUnit: UInt16 = 14
    static let playersAndDamage: UInt16 = 9
    static let tab: UInt16 = 48
    static let shop: UInt16 = 49

    fileprivate static func action(for keyCode: UInt16) -> BridgeAction? {
        switch keyCode {
        case shop: return .shop
        case reroll: return .reroll
        case buyXP: return .buyXP
        case sellUnit: return .sellUnit
        case playersAndDamage: return .togglePlayersAndDamage
        case tab: return .toggleItemsAndTraits
        default: return nil
        }
    }

    static func isActionKey(_ keyCode: UInt16) -> Bool {
        action(for: keyCode) != nil
    }
}

enum BridgeForegroundActivityState: Equatable {
    case unknown
    case gameplay
    case nonGameplay
}

enum BridgeAndroidActivityClassifier {
    private static let gameplayActivity = "com.epicgames.unreal.GameActivity"

    static func classify(dumpsysOutput: String, packageName: String = GameEdition.global.packageName) -> BridgeForegroundActivityState {
        guard let line = dumpsysOutput.split(separator: "\n").first(where: {
            $0.contains("topResumedActivity=")
        }),
        let marker = line.range(of: "topResumedActivity=") else {
            return .unknown
        }

        let payload = line[marker.upperBound...]
        for rawToken in payload.split(whereSeparator: { $0.isWhitespace }) {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "{}(),"))
            guard let slash = token.firstIndex(of: "/") else { continue }
            let activity = String(token[token.index(after: slash)...])
            guard !activity.isEmpty else { return .unknown }
            let package = String(token[..<slash])
            return package == packageName && activity == gameplayActivity ? .gameplay : .nonGameplay
        }
        return .unknown
    }
}

enum BridgeKeyboardEventDisposition: Equatable {
    case passThrough
    case consume
    case hotkey
}

enum BridgeKeyboardEventPolicy {
    private static let passthroughModifiers: NSEvent.ModifierFlags = [
        .command, .control, .option
    ]

    static func disposition(
        for keyCode: UInt16,
        activity: BridgeForegroundActivityState,
        modifierFlags: NSEvent.ModifierFlags
    ) -> BridgeKeyboardEventDisposition {
        guard activity == .gameplay,
              modifierFlags.intersection(passthroughModifiers).isEmpty else {
            return .passThrough
        }
        return BridgeKeyboardBinding.isActionKey(keyCode) ? .hotkey : .consume
    }
}

private final class BridgeAndroidActivityMonitor {
    private static let pollInterval: TimeInterval = 1
    private static let stateMaxAge: TimeInterval = 3

    private let configuration: BridgeConfiguration
    private let queue = DispatchQueue(label: "dev.sergeinaumov.mactician.input-bridge.activity")
    private let lock = NSLock()
    private var state = BridgeForegroundActivityState.unknown
    private var stateUpdatedAt: TimeInterval = 0
    private var stopped = true
    private var process: Process?

    init(configuration: BridgeConfiguration) {
        self.configuration = configuration
    }

    func start() {
        let shouldStart = withLock {
            guard stopped else { return false }
            stopped = false
            return true
        }
        guard shouldStart else { return }
        queue.async { [self] in poll() }
    }

    func stop() {
        let process = withLock {
            stopped = true
            state = .unknown
            stateUpdatedAt = ProcessInfo.processInfo.systemUptime
            let process = self.process
            self.process = nil
            return process
        }
        if process?.isRunning == true { process?.terminate() }
    }

    var currentState: BridgeForegroundActivityState {
        // The event-tap callback must never wait for ADB. Fail open while a
        // poll is publishing a new activity state.
        guard lock.try() else { return .unknown }
        defer { lock.unlock() }
        let stateAge = ProcessInfo.processInfo.systemUptime - stateUpdatedAt
        return stateAge <= Self.stateMaxAge ? state : .unknown
    }

    private var isStopped: Bool { withLock { stopped } }

    private func poll() {
        guard !isStopped else { return }

        let newState = queryState()
        guard !isStopped else { return }
        publish(newState)
        queue.asyncAfter(deadline: .now() + Self.pollInterval) { [self] in poll() }
    }

    private func queryState() -> BridgeForegroundActivityState {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = configuration.adb
        process.arguments = [
            "-P", "5038", "-s", "emulator-5582",
            "shell", "dumpsys activity activities 2>/dev/null | grep -m 1 'topResumedActivity='"
        ]
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
        guard registered else { return .unknown }
        defer {
            withLock {
                if self.process === process { self.process = nil }
            }
        }

        do {
            try process.run()
        } catch {
            return .unknown
        }
        if isStopped {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            return .unknown
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return .unknown
        }
        return BridgeAndroidActivityClassifier.classify(dumpsysOutput: output, packageName: configuration.packageName)
    }

    private func publish(_ newState: BridgeForegroundActivityState) {
        withLock {
            guard !stopped else { return }
            state = newState
            stateUpdatedAt = ProcessInfo.processInfo.systemUptime
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class BridgeTapDispatcher {
    private let queue = DispatchQueue(label: "dev.sergeinaumov.mactician.adb-input")
    private let configuration: BridgeConfiguration
    private var shell: Process?
    private var input: FileHandle?
    private var stopped = false
    private var showTraitsNext = true
    private var showDamageNext = true

    init(configuration: BridgeConfiguration) {
        self.configuration = configuration
    }

    func warmUp() {
        queue.async { [weak self] in
            guard let self, !stopped else { return }
            do {
                try ensureShell(configuration)
            } catch {
                stopShell()
            }
        }
    }

    func send(_ action: BridgeAction, cursor: CGPoint) {
        queue.async { [weak self] in
            guard let self, !stopped else { return }
            let command: String
            if case .sellUnit = action {
                guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
                      let window = gameWindowBounds(),
                      let source = BridgeUnitSale.source(cursor: cursor, window: window,
                                                        width: configuration.width,
                                                        height: configuration.height) else { return }
                command = BridgeUnitSale.command(from: source, width: configuration.width,
                                                 height: configuration.height)
            } else {
                guard let target = target(for: action) else { return }
                let point = target.pixels(width: configuration.width, height: configuration.height)
                command = "input tap \(point.x) \(point.y)\n"
            }
            do {
                try ensureShell(configuration)
                try input?.write(contentsOf: Data(command.utf8))
            } catch {
                stopShell()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            stopShell()
        }
    }

    private func target(for action: BridgeAction) -> BridgeRelativePoint? {
        switch action {
        case .shop:
            return BridgeHotkeyTarget.shop
        case .reroll:
            return BridgeHotkeyTarget.reroll
        case .buyXP:
            return BridgeHotkeyTarget.buyXP
        case .sellUnit:
            return nil
        case .toggleItemsAndTraits:
            defer { showTraitsNext.toggle() }
            return showTraitsNext ? BridgeHotkeyTarget.traits : BridgeHotkeyTarget.items
        case .togglePlayersAndDamage:
            defer { showDamageNext.toggle() }
            return showDamageNext ? BridgeHotkeyTarget.damage : BridgeHotkeyTarget.players
        }
    }

    private func gameWindowBounds() -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }
        return windows.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value == configuration.targetPID,
                  (window[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let rawBounds = window[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds),
                  bounds.width >= 500, bounds.height >= 300, bounds.width > bounds.height else { return nil }
            return bounds
        }.max { $0.width * $0.height < $1.width * $1.height }
    }

    private func ensureShell(_ configuration: BridgeConfiguration) throws {
        if shell?.isRunning == true, input != nil { return }
        stopShell()
        let process = Process()
        let stdin = Pipe()
        process.executableURL = configuration.adb
        process.arguments = ["-P", "5038", "-s", "emulator-5582", "shell"]
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.merging([
            "ANDROID_ADB_SERVER_PORT": "5038",
            "ADB_MDNS_AUTO_CONNECT": ""
        ]) { _, new in new }
        try process.run()
        shell = process
        input = stdin.fileHandleForWriting
    }

    private func stopShell() {
        try? input?.close()
        input = nil
        if shell?.isRunning == true { shell?.terminate() }
        shell = nil
    }
}

struct BridgeSessionGeneration {
    private(set) var current: UInt64 = 0

    mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    func accepts(_ generation: UInt64) -> Bool {
        generation == current
    }
}

private struct BridgeEventTapResources {
    let tap: CFMachPort
    let source: CFRunLoopSource
    let runLoop: CFRunLoop
}

private final class BridgeEventTapSession {
    private weak var owner: InputBridgeService?
    private let generation: UInt64
    private let configuration: BridgeConfiguration
    private let dispatcher: BridgeTapDispatcher
    private let activityMonitor: BridgeAndroidActivityMonitor
    private let lock = NSLock()
    private var stopped = false
    private var resources: BridgeEventTapResources?

    init(
        owner: InputBridgeService,
        generation: UInt64,
        configuration: BridgeConfiguration
    ) {
        self.owner = owner
        self.generation = generation
        self.configuration = configuration
        dispatcher = BridgeTapDispatcher(configuration: configuration)
        activityMonitor = BridgeAndroidActivityMonitor(configuration: configuration)
    }

    func start() {
        activityMonitor.start()
        dispatcher.warmUp()
        Thread.detachNewThread { [self] in run() }
    }

    func stop() {
        let resources = withLock {
            stopped = true
            return takeResources()
        }
        activityMonitor.stop()
        dispatcher.stop()
        tearDown(resources, stopRunLoop: true)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = withLock({ resources?.tap }), CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard !isStopped,
              let frontmost = NSWorkspace.shared.frontmostApplication else {
            return Unmanaged.passUnretained(event)
        }
        let emulatorIsFrontmost = frontmost.processIdentifier == configuration.targetPID
            || frontmost.bundleIdentifier == configuration.targetBundleID
        guard emulatorIsFrontmost else { return Unmanaged.passUnretained(event) }
        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return nil
        case .keyDown, .keyUp:
            guard let cocoaEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }
            switch BridgeKeyboardEventPolicy.disposition(
                for: cocoaEvent.keyCode,
                activity: activityMonitor.currentState,
                modifierFlags: cocoaEvent.modifierFlags
            ) {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .consume:
                return nil
            case .hotkey:
                if let action = BridgeKeyboardBinding.action(for: cocoaEvent.keyCode),
                   type == .keyDown,
                   !cocoaEvent.isARepeat {
                    dispatcher.send(action, cursor: event.location)
                }
                return nil
            }
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func run() {
        while !isStopped {
            if installTap() {
                owner?.reportStatus(
                    generation: generation,
                    eventTapActive: true,
                    eventTapAttemptFailed: false
                )
                CFRunLoopRun()
                tearDownCurrentTap()
                owner?.reportStatus(
                    generation: generation,
                    eventTapActive: false,
                    eventTapAttemptFailed: false
                )
            } else if !isStopped {
                owner?.reportStatus(
                    generation: generation,
                    eventTapActive: false,
                    eventTapAttemptFailed: true
                )
            }
            if !isStopped { Thread.sleep(forTimeInterval: 2) }
        }
    }

    private var isStopped: Bool { withLock { stopped } }

    private func installTap() -> Bool {
        guard !isStopped else { return false }
        let types: [CGEventType] = [
            .keyDown, .keyUp,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: launcherBridgeCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        CGEvent.tapEnable(tap: tap, enable: false)
        guard let runLoop = CFRunLoopGetCurrent(),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        CFRunLoopAddSource(runLoop, source, .commonModes)
        let resources = BridgeEventTapResources(tap: tap, source: source, runLoop: runLoop)
        let installed = withLock {
            guard !stopped else { return false }
            self.resources = resources
            return true
        }
        guard installed else {
            tearDown(resources, stopRunLoop: false)
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        if isStopped {
            tearDownCurrentTap()
            return false
        }
        return true
    }

    private func tearDownCurrentTap() {
        let resources = withLock { takeResources() }
        tearDown(resources, stopRunLoop: false)
    }

    private func takeResources() -> BridgeEventTapResources? {
        defer { resources = nil }
        return resources
    }

    private func tearDown(_ resources: BridgeEventTapResources?, stopRunLoop: Bool) {
        guard let resources else { return }
        CGEvent.tapEnable(tap: resources.tap, enable: false)
        CFRunLoopRemoveSource(resources.runLoop, resources.source, .commonModes)
        CFMachPortInvalidate(resources.tap)
        if stopRunLoop { CFRunLoopStop(resources.runLoop) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class InputBridgeService {
    typealias StatusHandler = (_ eventTapActive: Bool, _ eventTapAttemptFailed: Bool) -> Void

    private let lock = NSLock()
    private var sessionGeneration = BridgeSessionGeneration()
    private var session: BridgeEventTapSession?
    private var statusHandler: StatusHandler?

    static func permissionFacts(
        eventTapActive: Bool,
        eventTapAttemptFailed: Bool
    ) -> LauncherHotkeyFacts {
        LauncherHotkeyFacts(
            accessibilityTrusted: AXIsProcessTrusted(),
            eventTapActive: eventTapActive,
            eventTapAttemptFailed: eventTapAttemptFailed
        )
    }

    func observeStatus(_ handler: @escaping StatusHandler) {
        withLock { statusHandler = handler }
    }

    func requestPermissions() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        guard !trusted,
              let settingsURL = URL(
                  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              ) else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    func start(targetPID: pid_t, adb: URL, width: Int, height: Int, packageName: String) {
        stop()
        let configuration = BridgeConfiguration(
            targetPID: targetPID,
            packageName: packageName,
            targetBundleID: "dev.sergeinaumov.mactician.game-host",
            adb: adb,
            width: width,
            height: height
        )
        let session = withLock {
            let generation = sessionGeneration.advance()
            let session = BridgeEventTapSession(
                owner: self,
                generation: generation,
                configuration: configuration
            )
            self.session = session
            return session
        }
        session.start()
    }

    func stop() {
        let (session, generation) = withLock {
            let session = self.session
            self.session = nil
            return (session, sessionGeneration.advance())
        }
        session?.stop()
        reportStatus(
            generation: generation,
            eventTapActive: false,
            eventTapAttemptFailed: false
        )
    }

    fileprivate func reportStatus(
        generation: UInt64,
        eventTapActive: Bool,
        eventTapAttemptFailed: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let handler: StatusHandler? = self.withLock {
                guard self.sessionGeneration.accepts(generation) else { return nil }
                return self.statusHandler
            }
            handler?(eventTapActive, eventTapAttemptFailed)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func launcherBridgeCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<BridgeEventTapSession>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}
