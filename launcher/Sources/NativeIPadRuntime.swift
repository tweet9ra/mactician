import AppKit
import Foundation
import Security

enum GameRuntimeKind: String, Codable, CaseIterable, Identifiable {
    case androidEmulator
    case nativeIPadExperimental

    var id: String { rawValue }
}

enum ExperimentalFeatures {
    static let nativeIPadRuntimeDefaultsKey = "experimental.nativeIPadRuntime.enabled"
    static let selectedRuntimeDefaultsKey = "selectedGameRuntime"

    static var nativeIPadRuntimeEnabled: Bool {
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        return nativeIPadRuntimeEnabled(
            environment: ProcessInfo.processInfo.environment,
            defaults: .standard,
            debugBuild: debugBuild
        )
    }

    static func nativeIPadRuntimeEnabled(
        environment: [String: String],
        defaults: UserDefaults,
        debugBuild: Bool
    ) -> Bool {
        debugBuild
            || environment["MACTICIAN_ENABLE_NATIVE_IPAD_RUNTIME"] == "1"
            || defaults.bool(forKey: nativeIPadRuntimeDefaultsKey)
    }
}

enum GameRuntimeSelection {
    static func restoredKind(savedValue: String?, nativeEnabled: Bool) -> GameRuntimeKind {
        guard nativeEnabled,
              savedValue == GameRuntimeKind.nativeIPadExperimental.rawValue else {
            return .androidEmulator
        }
        return .nativeIPadExperimental
    }

    static func canSelect(
        _ kind: GameRuntimeKind,
        nativeEnabled: Bool,
        stateMachineLocked: Bool,
        androidRunning: Bool,
        nativeRunning: Bool
    ) -> Bool {
        !stateMachineLocked
            && !androidRunning
            && !nativeRunning
            && (kind != .nativeIPadExperimental || nativeEnabled)
    }
}

enum NativeIPadSignatureKind: String, Codable, Equatable {
    case adHoc = "ad-hoc"
    case developerID = "developer-id"
    case appStore = "app-store"
    case appleDevelopment = "apple-development"
    case otherValid = "other-valid"
}

enum NativeIPadRuntimeSourceKind: String, Codable, Equatable {
    case userSelectedApplicationBundle = "user-selected-application-bundle"
}

struct NativeIPadAppDescriptor: Codable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let shortVersion: String?
    let buildVersion: String?
    let executableName: String
    let architectures: [String]
    let signatureKind: NativeIPadSignatureKind
    let canonicalURL: URL
}

struct NativeIPadRuntimeState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    let bookmark: Data
    let descriptor: NativeIPadAppDescriptor
    let lastValidatedAt: Date
    let lastError: String?
    let sourceKind: NativeIPadRuntimeSourceKind
}

enum NativeIPadRuntimeStateLoadResult: Equatable {
    case missing
    case loaded(NativeIPadRuntimeState, URL)
    case invalid(String)
}

struct NativeIPadBookmarking {
    let create: (URL) throws -> Data
    let resolve: (Data) throws -> (url: URL, stale: Bool)

    static let system = NativeIPadBookmarking(
        create: { url in
            try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        },
        resolve: { data in
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        }
    )
}

final class NativeIPadRuntimeStateStore {
    private let stateURL: URL
    private let bookmarking: NativeIPadBookmarking

    init(stateURL: URL, bookmarking: NativeIPadBookmarking = .system) {
        self.stateURL = stateURL
        self.bookmarking = bookmarking
    }

    func load() -> NativeIPadRuntimeStateLoadResult {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: stateURL)
            let state = try Self.decoder.decode(NativeIPadRuntimeState.self, from: data)
            guard state.schemaVersion == NativeIPadRuntimeState.currentSchemaVersion else {
                return .invalid("Unsupported Native iPad state schema: \(state.schemaVersion)")
            }
            let resolved = try bookmarking.resolve(state.bookmark)
            guard !resolved.stale else {
                return .invalid("The saved application bookmark is stale. Choose the app again.")
            }
            let canonicalURL = resolved.url.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalURL == state.descriptor.canonicalURL else {
                return .invalid("The saved application location changed. Choose the app again.")
            }
            return .loaded(state, canonicalURL)
        } catch {
            return .invalid("The saved Native iPad state is invalid. Choose the app again.")
        }
    }

    func save(
        descriptor: NativeIPadAppDescriptor,
        sourceKind: NativeIPadRuntimeSourceKind = .userSelectedApplicationBundle,
        lastError: String? = nil,
        validatedAt: Date = Date()
    ) throws {
        let state = NativeIPadRuntimeState(
            bookmark: try bookmarking.create(descriptor.canonicalURL),
            descriptor: descriptor,
            lastValidatedAt: validatedAt,
            lastError: lastError,
            sourceKind: sourceKind
        )
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    func reset() throws {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

protocol NativeIPadArchitectureInspecting {
    func architectures(of executableURL: URL) throws -> [String]
}

struct SystemNativeIPadArchitectureInspector: NativeIPadArchitectureInspecting {
    private let runner: (URL, [String]) throws -> String

    init(runner: @escaping (URL, [String]) throws -> String = { executable, arguments in
        try SystemServices.run(executable, arguments)
    }) {
        self.runner = runner
    }

    func architectures(of executableURL: URL) throws -> [String] {
        let output = try runner(
            URL(fileURLWithPath: "/usr/bin/lipo"),
            ["-archs", executableURL.path]
        )
        let architectures = output.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !architectures.isEmpty else {
            throw LauncherError.integrity("The selected application executable is not a Mach-O binary")
        }
        return architectures
    }
}

protocol NativeIPadSignatureInspecting {
    func signatureKind(of applicationURL: URL) throws -> NativeIPadSignatureKind
}

struct SystemNativeIPadSignatureInspector: NativeIPadSignatureInspecting {
    func signatureKind(of applicationURL: URL) throws -> NativeIPadSignatureKind {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            applicationURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            throw LauncherError.integrity("Code signature inspection failed (OSStatus \(createStatus))")
        }

        let validationFlags = SecCSFlags(
            rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        )
        let validationStatus = SecStaticCodeCheckValidity(staticCode, validationFlags, nil)
        guard validationStatus == errSecSuccess else {
            throw LauncherError.integrity("The selected application has an invalid code signature (OSStatus \(validationStatus))")
        }

        var information: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &information
        )
        guard informationStatus == errSecSuccess,
              let values = information as NSDictionary? else {
            throw LauncherError.integrity("Code signature metadata is unavailable (OSStatus \(informationStatus))")
        }

        let signatureFlags = (values[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
        // Security exposes the flag in C headers but not in every Swift SDK overlay.
        let adHocSignatureFlag = UInt32(0x0002)
        if signatureFlags & adHocSignatureFlag != 0 {
            return .adHoc
        }
        if ["Contents/_MASReceipt/receipt", "_MASReceipt/receipt"].contains(where: {
            FileManager.default.fileExists(atPath: applicationURL.appendingPathComponent($0).path)
        }) {
            return .appStore
        }
        let certificateNames = (values[kSecCodeInfoCertificates] as? [SecCertificate] ?? [])
            .compactMap { SecCertificateCopySubjectSummary($0) as String? }
        if certificateNames.contains(where: { $0.hasPrefix("Developer ID Application:") }) {
            return .developerID
        }
        if certificateNames.contains(where: {
            $0.hasPrefix("Apple Development:") || $0.hasPrefix("Mac Developer:")
        }) {
            return .appleDevelopment
        }
        return .otherValid
    }
}

struct NativeIPadRuntimeValidator {
    private let fileManager: FileManager
    private let architectureInspector: any NativeIPadArchitectureInspecting
    private let signatureInspector: any NativeIPadSignatureInspecting
    private let hostArchitecture: () -> String
    private let macticianBundleURL: () -> URL?

    init(
        fileManager: FileManager = .default,
        architectureInspector: any NativeIPadArchitectureInspecting = SystemNativeIPadArchitectureInspector(),
        signatureInspector: any NativeIPadSignatureInspecting = SystemNativeIPadSignatureInspector(),
        hostArchitecture: @escaping () -> String = {
            #if arch(arm64)
            "arm64"
            #else
            "unsupported"
            #endif
        },
        macticianBundleURL: @escaping () -> URL? = { Bundle.main.bundleURL }
    ) {
        self.fileManager = fileManager
        self.architectureInspector = architectureInspector
        self.signatureInspector = signatureInspector
        self.hostArchitecture = hostArchitecture
        self.macticianBundleURL = macticianBundleURL
    }

    func validate(_ selectedURL: URL) throws -> NativeIPadAppDescriptor {
        guard hostArchitecture() == "arm64" else {
            throw LauncherError.preflight("Native iPad Runtime requires an Apple Silicon Mac")
        }
        guard selectedURL.isFileURL, selectedURL.pathExtension.lowercased() == "app" else {
            throw LauncherError.integrity("Choose a macOS application bundle with the .app extension")
        }

        let canonicalURL = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard canonicalURL.pathExtension.lowercased() == "app" else {
            throw LauncherError.integrity("The selected path does not resolve to an .app bundle")
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LauncherError.integrity("The selected application no longer exists")
        }

        if let ownURL = macticianBundleURL()?.standardizedFileURL.resolvingSymlinksInPath() {
            let ownPath = ownURL.path.hasSuffix("/") ? ownURL.path : ownURL.path + "/"
            guard canonicalURL != ownURL, !canonicalURL.path.hasPrefix(ownPath) else {
                throw LauncherError.integrity("Mactician cannot be selected as the Native iPad application")
            }
        }

        guard let bundle = Bundle(url: canonicalURL) else {
            throw LauncherError.integrity("The selected directory is not a readable application bundle")
        }
        let infoURLs = [
            canonicalURL.appendingPathComponent("Contents/Info.plist"),
            canonicalURL.appendingPathComponent("Info.plist")
        ]
        guard let infoURL = infoURLs.first(where: { fileManager.fileExists(atPath: $0.path) }),
              let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil)
                as? [String: Any] else {
            throw LauncherError.integrity("The selected application has no readable Info.plist")
        }
        guard let bundleIdentifier = nonEmptyString(info["CFBundleIdentifier"]) else {
            throw LauncherError.integrity("The selected application has no CFBundleIdentifier")
        }
        guard let executableName = nonEmptyString(info["CFBundleExecutable"]) else {
            throw LauncherError.integrity("The selected application has no CFBundleExecutable")
        }
        if let packageType = nonEmptyString(info["CFBundlePackageType"]), packageType != "APPL" {
            throw LauncherError.integrity("The selected bundle is not an application")
        }
        let deviceFamilies = (info["UIDeviceFamily"] as? [NSNumber] ?? []).map(\.intValue)
        guard deviceFamilies.contains(2) else {
            throw LauncherError.integrity("The selected application does not declare iPad compatibility")
        }
        let executableCandidates = [
            bundle.executableURL,
            canonicalURL.appendingPathComponent("Contents/MacOS/\(executableName)"),
            canonicalURL.appendingPathComponent(executableName)
        ].compactMap { $0 }
        let executableURL = executableCandidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) ?? executableCandidates[0]
        var executableIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: executableURL.path, isDirectory: &executableIsDirectory),
              !executableIsDirectory.boolValue,
              (try? executableURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw LauncherError.integrity("The selected application executable is missing")
        }
        let architectures = try architectureInspector.architectures(of: executableURL)
        guard architectures.contains("arm64") else {
            throw LauncherError.integrity("The selected application executable has no arm64 slice")
        }
        let signatureKind = try signatureInspector.signatureKind(of: canonicalURL)

        return NativeIPadAppDescriptor(
            bundleIdentifier: bundleIdentifier,
            displayName: nonEmptyString(info["CFBundleDisplayName"])
                ?? nonEmptyString(info["CFBundleName"])
                ?? canonicalURL.deletingPathExtension().lastPathComponent,
            shortVersion: nonEmptyString(info["CFBundleShortVersionString"]),
            buildVersion: nonEmptyString(info["CFBundleVersion"]),
            executableName: executableName,
            architectures: Array(Set(architectures)).sorted(),
            signatureKind: signatureKind,
            canonicalURL: canonicalURL
        )
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum RuntimeProbeResult: Equatable {
    case ready
    case unavailable(String)
}

struct AndroidRuntimeLaunchConfiguration {
    let profile: LaunchProfile
    let effectsQuality: EffectsQuality
    let language: GameLanguage
    let cpuCores: Int
    let memoryMB: Int
    let uiScalePercent: Int
    let state: InstallState
    let gameRelease: GameRelease
    let gameResources: URL
}

enum RuntimeLaunchConfiguration {
    case android(AndroidRuntimeLaunchConfiguration)
    case nativeIPad(NativeIPadAppDescriptor)
}

protocol GameRuntimeSessionControlling: AnyObject {
    var kind: GameRuntimeKind { get }
    var isRunning: Bool { get }
    func probe(configuration: RuntimeLaunchConfiguration) -> RuntimeProbeResult
    func launch(
        configuration: RuntimeLaunchConfiguration,
        eventHandler: @escaping (RuntimeEvent) -> Void
    ) throws
    func stop()
    func shutdown()
}

final class AndroidRuntimeControllerAdapter: GameRuntimeSessionControlling {
    let kind = GameRuntimeKind.androidEmulator
    private let runtime: RuntimeController

    init(runtime: RuntimeController) {
        self.runtime = runtime
    }

    var isRunning: Bool { runtime.isRunning }

    func probe(configuration: RuntimeLaunchConfiguration) -> RuntimeProbeResult {
        guard case let .android(configuration) = configuration else {
            return .unavailable("Invalid Android runtime configuration")
        }
        guard configuration.state.isReady,
              configuration.state.gamePackageName.map({
                  $0 == configuration.gameRelease.packageName
              }) ?? true,
              configuration.state.gameVersion == configuration.gameRelease.version,
              configuration.state.gameBaseSHA256 == configuration.gameRelease.baseSHA256,
              configuration.state.overlaySHA256 != nil else {
            return .unavailable("The installed TFT version is not supported by this launcher build")
        }
        return .ready
    }

    func launch(
        configuration: RuntimeLaunchConfiguration,
        eventHandler: @escaping (RuntimeEvent) -> Void
    ) throws {
        guard case let .android(configuration) = configuration else {
            throw LauncherError.process("Invalid Android runtime configuration")
        }
        try runtime.start(
            profile: configuration.profile,
            effectsQuality: configuration.effectsQuality,
            language: configuration.language,
            cpuCores: configuration.cpuCores,
            memoryMB: configuration.memoryMB,
            uiScalePercent: configuration.uiScalePercent,
            state: configuration.state,
            gameRelease: configuration.gameRelease,
            gameResources: configuration.gameResources,
            events: eventHandler
        )
    }

    func stop() { runtime.stop() }
    func shutdown() { runtime.stop() }
}

protocol WorkspaceRunningApplication: AnyObject {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var bundleURL: URL? { get }
    var isTerminated: Bool { get }
    @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

extension NSRunningApplication: WorkspaceRunningApplication {}

protocol WorkspaceApplicationLaunching: AnyObject {
    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [any WorkspaceRunningApplication]
    func openApplication(
        at applicationURL: URL,
        activates: Bool,
        completion: @escaping (Result<any WorkspaceRunningApplication, Error>) -> Void
    )
    func observeTerminations(
        _ handler: @escaping (any WorkspaceRunningApplication) -> Void
    ) -> Any
    func removeTerminationObserver(_ observer: Any)
}

final class SystemWorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func runningApplications(
        withBundleIdentifier bundleIdentifier: String
    ) -> [any WorkspaceRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(
        at applicationURL: URL,
        activates: Bool,
        completion: @escaping (Result<any WorkspaceRunningApplication, Error>) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        workspace.openApplication(at: applicationURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                if let application {
                    completion(.success(application))
                } else {
                    completion(.failure(
                        error ?? LauncherError.process("macOS did not return the launched application")
                    ))
                }
            }
        }
    }

    func observeTerminations(
        _ handler: @escaping (any WorkspaceRunningApplication) -> Void
    ) -> Any {
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            handler(application)
        }
    }

    func removeTerminationObserver(_ observer: Any) {
        guard let observer = observer as? NSObjectProtocol else { return }
        workspace.notificationCenter.removeObserver(observer)
    }
}

final class NativeIPadRuntimeController: GameRuntimeSessionControlling {
    let kind = GameRuntimeKind.nativeIPadExperimental

    private let workspace: any WorkspaceApplicationLaunching
    private let validator: NativeIPadRuntimeValidator
    private let stopTimeout: TimeInterval
    private var application: (any WorkspaceRunningApplication)?
    private var applicationURL: URL?
    private var eventHandler: ((RuntimeEvent) -> Void)?
    private var terminationObserver: Any?
    private var stopWorkItem: DispatchWorkItem?
    private var launchPending = false
    private var ownsApplication = false
    private var stopRequested = false
    private var sessionEnded = true
    private var generation = UUID()

    init(
        workspace: any WorkspaceApplicationLaunching = SystemWorkspaceApplicationLauncher(),
        validator: NativeIPadRuntimeValidator = NativeIPadRuntimeValidator(),
        stopTimeout: TimeInterval = 5
    ) {
        self.workspace = workspace
        self.validator = validator
        self.stopTimeout = stopTimeout
    }

    var isRunning: Bool {
        launchPending || application?.isTerminated == false
    }

    func probe(configuration: RuntimeLaunchConfiguration) -> RuntimeProbeResult {
        guard case let .nativeIPad(descriptor) = configuration else {
            return .unavailable("Invalid Native iPad runtime configuration")
        }
        do {
            _ = try validator.validate(descriptor.canonicalURL)
            return .ready
        } catch {
            return .unavailable(NativeIPadDiagnostics.displayMessage(error.localizedDescription))
        }
    }

    func launch(
        configuration: RuntimeLaunchConfiguration,
        eventHandler: @escaping (RuntimeEvent) -> Void
    ) throws {
        guard !isRunning else {
            throw LauncherError.process("A Native iPad application is already launching or running")
        }
        guard case let .nativeIPad(savedDescriptor) = configuration else {
            throw LauncherError.process("Invalid Native iPad runtime configuration")
        }
        let descriptor = try validator.validate(savedDescriptor.canonicalURL)
        guard descriptor.bundleIdentifier == savedDescriptor.bundleIdentifier,
              descriptor.executableName == savedDescriptor.executableName,
              descriptor.canonicalURL == savedDescriptor.canonicalURL else {
            throw LauncherError.integrity("The selected application metadata changed. Revalidate it before launch.")
        }

        let token = UUID()
        generation = token
        self.eventHandler = eventHandler
        applicationURL = descriptor.canonicalURL
        launchPending = true
        ownsApplication = false
        stopRequested = false
        sessionEnded = false
        installTerminationObserver(generation: token)

        if let existing = workspace.runningApplications(
            withBundleIdentifier: descriptor.bundleIdentifier
        ).first(where: { exactMatch($0, descriptor: descriptor) && !$0.isTerminated }) {
            launchPending = false
            application = existing
            guard existing.activate(options: [.activateAllWindows]) else {
                failLaunch("The already running application could not be activated", generation: token)
                return
            }
            eventHandler(RuntimeEvent(event: .ready, pid: existing.processIdentifier))
            return
        }

        workspace.openApplication(at: descriptor.canonicalURL, activates: true) { [weak self] result in
            guard let self, generation == token, !sessionEnded else { return }
            launchPending = false
            switch result {
            case let .success(application):
                guard exactMatch(application, descriptor: descriptor), !application.isTerminated else {
                    failLaunch("macOS returned an application that does not match the validated bundle", generation: token)
                    return
                }
                self.application = application
                ownsApplication = true
                if stopRequested {
                    beginTermination(of: application, generation: token)
                } else {
                    eventHandler(RuntimeEvent(event: .ready, pid: application.processIdentifier))
                }
            case let .failure(error):
                failLaunch(
                    "Native iPad application launch failed: "
                        + NativeIPadDiagnostics.displayMessage(error.localizedDescription),
                    generation: token
                )
            }
        }
    }

    func stop() {
        guard !sessionEnded else { return }
        stopRequested = true
        guard let application else { return }
        beginTermination(of: application, generation: generation)
    }

    func shutdown() {
        if ownsApplication, let application, !application.isTerminated {
            _ = application.terminate()
        }
        cleanupSession()
    }

    private func beginTermination(
        of target: any WorkspaceRunningApplication,
        generation token: UUID
    ) {
        guard generation == token, sameApplication(target, application) else { return }
        _ = target.terminate()
        let workItem = DispatchWorkItem { [weak self, weak target] in
            guard let self, let target, generation == token, !sessionEnded,
                  sameApplication(target, application) else { return }
            if target.isTerminated {
                finishSession(generation: token)
                return
            }
            _ = target.forceTerminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + min(stopTimeout, 1)) { [weak self, weak target] in
                guard let self, let target, generation == token, !sessionEnded,
                      sameApplication(target, application) else { return }
                if target.isTerminated {
                    finishSession(generation: token)
                } else {
                    failLaunch("The exact Native iPad process did not terminate", generation: token)
                }
            }
        }
        stopWorkItem?.cancel()
        stopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + stopTimeout, execute: workItem)
    }

    private func installTerminationObserver(generation token: UUID) {
        terminationObserver = workspace.observeTerminations { [weak self] terminated in
            guard let self, generation == token,
                  sameApplication(terminated, application) else { return }
            finishSession(generation: token)
        }
    }

    private func exactMatch(
        _ application: any WorkspaceRunningApplication,
        descriptor: NativeIPadAppDescriptor
    ) -> Bool {
        guard application.bundleIdentifier == descriptor.bundleIdentifier,
              let bundleURL = application.bundleURL else { return false }
        return bundleURL.standardizedFileURL.resolvingSymlinksInPath() == descriptor.canonicalURL
    }

    private func sameApplication(
        _ lhs: (any WorkspaceRunningApplication)?,
        _ rhs: (any WorkspaceRunningApplication)?
    ) -> Bool {
        guard let lhs, let rhs,
              lhs.processIdentifier == rhs.processIdentifier,
              let lhsURL = lhs.bundleURL,
              let rhsURL = rhs.bundleURL else { return false }
        let lhsCanonicalURL = lhsURL.standardizedFileURL.resolvingSymlinksInPath()
        guard lhsCanonicalURL == rhsURL.standardizedFileURL.resolvingSymlinksInPath() else {
            return false
        }
        return applicationURL == nil || lhsCanonicalURL == applicationURL
    }

    private func finishSession(generation token: UUID) {
        guard generation == token, !sessionEnded else { return }
        sessionEnded = true
        let handler = eventHandler
        cleanupSession()
        handler?(RuntimeEvent(event: .stopped, code: 0))
    }

    private func failLaunch(_ message: String, generation token: UUID) {
        guard generation == token, !sessionEnded else { return }
        sessionEnded = true
        let handler = eventHandler
        cleanupSession()
        handler?(RuntimeEvent(event: .error, message: message))
    }

    private func cleanupSession() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        if let terminationObserver {
            workspace.removeTerminationObserver(terminationObserver)
        }
        terminationObserver = nil
        application = nil
        applicationURL = nil
        eventHandler = nil
        launchPending = false
        ownsApplication = false
        stopRequested = false
        sessionEnded = true
    }
}

enum NativeIPadDiagnostics {
    static func displayPath(_ url: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.path
        let home = homeDirectory.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func displayMessage(
        _ message: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        message.replacingOccurrences(of: homeDirectory.standardizedFileURL.path, with: "~")
    }
}
