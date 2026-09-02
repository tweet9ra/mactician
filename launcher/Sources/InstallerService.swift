import Darwin
import Foundation

struct InstallerProgress {
    enum Phase: Equatable {
        case checking
        case downloading
        case extracting
        case creatingAVD
        case installingGame
        case finished
        case paused
    }

    let phase: Phase
    let message: String
    let fraction: Double
}

struct GameUpdateResult {
    let state: InstallState
    let release: GameRelease
    let changed: Bool
}

struct GameUpdateAvailability {
    let release: GameRelease
    let isAvailable: Bool
}

final class InstallerService {
    typealias ProgressHandler = (InstallerProgress) -> Void
    typealias CompletionHandler = (Result<InstallState, Error>) -> Void

    private let paths: LauncherPaths
    private let manifest: ReleaseManifest
    private let queue = DispatchQueue(label: "dev.sergeinaumov.mactician.installer", qos: .userInitiated)
    private let lock = NSLock()
    private var activeProcess: Process?
    private var cancelled = false
    private var paused = false

    init(paths: LauncherPaths, manifest: ReleaseManifest) {
        self.paths = paths
        self.manifest = manifest
    }

    static func curlArguments(component: SDKComponent, destination: URL) -> [String] {
        [
            "-fL", "--retry", "3", "--retry-delay", "2", "--continue-at", "-",
            component.url.absoluteString, "-o", destination.path
        ]
    }

    static func hostedDownloadArguments(url: URL, destination: URL) -> [String] {
        [
            "-fL", "--retry", "3", "--retry-delay", "2", "--continue-at", "-",
            "--proto", "=https", "--tlsv1.2", url.absoluteString, "-o", destination.path
        ]
    }

    static func extractArchive(_ archive: URL, to destination: URL) throws {
        // ditto rejects the valid ZIP64 Android system-image archive with a
        // "Couldn't read pkzip signature" error. The macOS unzip utility
        // handles all pinned Android SDK archives and preserves their modes.
        try SystemServices.run(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            ["-q", archive.path, "-d", destination.path]
        )
    }

    static func adbArguments(_ arguments: [String]) -> [String] {
        ["-P", "5038"] + arguments
    }

    static func gameInstallArguments(apkPaths: [String]) -> [String] {
        adbArguments([
            "-s", "emulator-5582", "install-multiple", "--no-streaming", "-r", "-g"
        ] + apkPaths)
    }

    static func emulatorArguments(initializeData: Bool, logicalCPUCount: Int, memoryMB: Int) -> [String] {
        var arguments = [
            "@TftPlay", "-id", "TFT-TftPlay", "-port", "5582", "-gpu", "host",
            "-feature", "GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts",
            "-append-userspace-opt", "androidboot.opengles.version=196610",
            "-append-userspace-opt", "androidboot.mactician.graphics_profile=osft",
            "-skin", "1920x1080", "-vsync-rate", "60",
            "-dns-server", "1.1.1.1,8.8.8.8",
            "-cores", "\(HostSizing.guestCPUCores(logicalCPUCount: logicalCPUCount))",
            "-memory", "\(memoryMB)", "-no-snapshot", "-no-metrics", "-no-boot-anim",
            "-no-window", "-no-audio", "-crash-report-mode", "disabled"
        ]
        if initializeData {
            // A newly created QCOW2 disk is intentionally empty. The emulator
            // must format and seed it before adbd can complete its first boot.
            arguments.append("-wipe-data")
        }
        return arguments
    }

    func install(repair: Bool, progress: @escaping ProgressHandler, completion: @escaping CompletionHandler) {
        lock.lock()
        guard activeProcess == nil else {
            lock.unlock()
            completion(.failure(LauncherError.process("Installation is already in progress")))
            return
        }
        cancelled = false
        paused = false
        lock.unlock()

        queue.async { [self] in
            do {
                let state = try performInstall(repair: repair, progress: progress)
                DispatchQueue.main.async { completion(.success(state)) }
            } catch {
                SystemServices.appendLog("Installer error: \(error.localizedDescription)", to: paths.launcherLog)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func updateGame(
        currentState: InstallState,
        progress: @escaping ProgressHandler,
        completion: @escaping (Result<GameUpdateResult, Error>) -> Void
    ) {
        lock.lock()
        guard activeProcess == nil else {
            lock.unlock()
            completion(.failure(LauncherError.process("Installation is already in progress")))
            return
        }
        cancelled = false
        paused = false
        lock.unlock()

        queue.async { [self] in
            do {
                let result = try performGameUpdate(currentState: currentState, progress: progress)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                SystemServices.appendLog("Game updater error: \(error.localizedDescription)", to: paths.launcherLog)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func checkGameUpdateAvailability(
        currentState: InstallState,
        completion: @escaping (Result<GameUpdateAvailability, Error>) -> Void
    ) {
        lock.lock()
        guard activeProcess == nil else {
            lock.unlock()
            completion(.failure(LauncherError.process("Installation is already in progress")))
            return
        }
        cancelled = false
        paused = false
        lock.unlock()

        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(
                    at: paths.downloads,
                    withIntermediateDirectories: true
                )
                let hosted = try fetchHostedGameFeed(progress: { _ in })
                let release = hosted.feed.release
                let samePackage = currentState.gamePackageName.map {
                    $0 == release.packageName
                } ?? true
                if samePackage,
                   let installedVersionCode = currentState.gameVersionCode,
                   let remoteVersionCode = release.versionCode,
                   remoteVersionCode < installedVersionCode {
                    throw LauncherError.unsupportedGame(
                        "The hosted TFT release is older than the installed game"
                    )
                }
                let availability = GameUpdateAvailability(
                    release: release,
                    isAvailable: HostedGameUpdate.isNewer(release, than: currentState)
                )
                DispatchQueue.main.async { completion(.success(availability)) }
            } catch {
                SystemServices.appendLog(
                    "Game update availability check failed: \(error.localizedDescription)",
                    to: paths.launcherLog
                )
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard let process = activeProcess, process.isRunning, !paused else { return }
        Darwin.kill(process.processIdentifier, SIGSTOP)
        paused = true
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard let process = activeProcess, process.isRunning, paused else { return }
        Darwin.kill(process.processIdentifier, SIGCONT)
        paused = false
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process = activeProcess, process.isRunning {
            Darwin.kill(process.processIdentifier, SIGCONT)
            process.terminate()
        }
    }

    private func performInstall(repair: Bool, progress: @escaping ProgressHandler) throws -> InstallState {
        progressOnMain(progress, .init(phase: .checking, message: "Checking your Mac and files…", fraction: 0))
        try SystemServices.checkHost(minimumFreeBytes: manifest.minimumFreeBytes, root: paths.root)
        try Self.prepareDirectories(at: paths)

        let hosted: (data: Data, feed: HostedGameFeed)?
        do {
            hosted = try fetchHostedGameFeed(progress: progress)
        } catch {
            SystemServices.appendLog(
                "Hosted TFT feed unavailable, using bundled fallback: \(error.localizedDescription)",
                to: paths.launcherLog
            )
            hosted = nil
        }
        let gameRelease = hosted?.feed.release ?? manifest.game
        if hosted == nil {
            try verifyGame(release: gameRelease, in: paths.gameResources)
        }

        var state = SystemServices.loadState(from: paths.stateFile)
        state.stage = .downloading
        try SystemServices.saveState(state, to: paths.stateFile)

        let usesBundledGame = hosted?.feed.release.baseSHA256 == manifest.game.baseSHA256
        let gameDownloadBytes = usesBundledGame
            ? 0
            : hosted?.feed.release.apks.reduce(Int64(0)) { $0 + $1.size } ?? 0
        let totalBytes = manifest.components.reduce(Int64(0)) { $0 + $1.size } + gameDownloadBytes
        var completedBytes: Int64 = 0
        for component in manifest.components {
            try checkCancellation()
            let target = paths.root.appendingPathComponent(component.installPath, isDirectory: true)
            let isInstalled = componentLayoutIsValid(component, at: target)
            if !isInstalled {
                try installComponent(
                    component,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    progress: progress
                )
            }
            completedBytes += component.size
            state.installedComponents[component.id] = component.version
            try SystemServices.saveState(state, to: paths.stateFile)
        }

        let gameResources: URL
        if let hosted, !usesBundledGame {
            gameResources = try downloadHostedGame(
                hosted.feed.release,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                progress: progress
            )
        } else {
            gameResources = paths.gameResources
        }

        try verifySDKLayout()
        try EmulatorBrandingPatch.apply(
            at: paths.qemuSystem,
            entitlements: paths.qemuHypervisorEntitlements
        )
        state.stage = .sdkInstalled
        try SystemServices.saveState(state, to: paths.stateFile)

        progressOnMain(progress, .init(phase: .extracting, message: "Preparing secure runtime…", fraction: 0.88))
        try Self.refreshRuntimeProject(at: paths)
        let overlayHash = try buildOverlay(release: gameRelease, resources: gameResources)

        progressOnMain(progress, .init(phase: .creatingAVD, message: "Creating a clean Android device…", fraction: 0.91))
        let installationMemoryMB = GuestResourceOptions.installationMemoryMB(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
        try createAVDIfNeeded(memoryMB: installationMemoryMB)
        state.stage = .avdCreated
        state.overlaySHA256 = overlayHash
        try SystemServices.saveState(state, to: paths.stateFile)

        progressOnMain(progress, .init(phase: .installingGame, message: "Installing TFT…", fraction: 0.94))
        try provisionGame(release: gameRelease, resources: gameResources)
        state.stage = .ready
        state.gamePackageName = gameRelease.packageName
        state.gameVersion = gameRelease.version
        state.gameVersionCode = gameRelease.versionCode
        state.gameBaseSHA256 = gameRelease.baseSHA256
        state.overlaySHA256 = overlayHash
        try SystemServices.saveState(state, to: paths.stateFile)
        if let hosted {
            try saveHostedGameFeed(hosted.data)
        }
        try? FileManager.default.removeItem(at: paths.downloads)

        progressOnMain(progress, .init(phase: .finished, message: "Done", fraction: 1))
        return state
    }

    private func performGameUpdate(
        currentState: InstallState,
        progress: @escaping ProgressHandler
    ) throws -> GameUpdateResult {
        progressOnMain(progress, .init(
            phase: .checking,
            message: "Checking for TFT updates…",
            fraction: 0
        ))
        try Self.prepareDirectories(at: paths)
        let hosted = try fetchHostedGameFeed(progress: progress)
        let release = hosted.feed.release
        let samePackage = currentState.gamePackageName.map {
            $0 == release.packageName
        } ?? true
        if samePackage,
           let installedVersionCode = currentState.gameVersionCode,
           let remoteVersionCode = release.versionCode,
           remoteVersionCode < installedVersionCode {
            throw LauncherError.unsupportedGame("The hosted TFT release is older than the installed game")
        }

        if samePackage,
           currentState.gameVersion == release.version,
           currentState.gameBaseSHA256 == release.baseSHA256 {
            var state = currentState
            state.gamePackageName = release.packageName
            state.gameVersionCode = release.versionCode
            try SystemServices.saveState(state, to: paths.stateFile)
            try saveHostedGameFeed(hosted.data)
            progressOnMain(progress, .init(phase: .finished, message: "TFT is up to date", fraction: 1))
            return GameUpdateResult(state: state, release: release, changed: false)
        }

        let resources = try downloadHostedGame(
            release,
            completedBytes: 0,
            totalBytes: release.apks.reduce(Int64(0)) { $0 + $1.size },
            progress: progress
        )

        try verifySDKLayout()
        progressOnMain(progress, .init(
            phase: .extracting,
            message: "Preparing the new game version…",
            fraction: 0.88
        ))
        try Self.refreshRuntimeProject(at: paths)
        let overlayHash = try buildOverlay(release: release, resources: resources)
        progressOnMain(progress, .init(
            phase: .installingGame,
            message: "Updating TFT…",
            fraction: 0.94
        ))
        try provisionGame(release: release, resources: resources)

        var state = currentState
        state.stage = .ready
        state.gamePackageName = release.packageName
        state.gameVersion = release.version
        state.gameVersionCode = release.versionCode
        state.gameBaseSHA256 = release.baseSHA256
        state.overlaySHA256 = overlayHash
        try SystemServices.saveState(state, to: paths.stateFile)
        try saveHostedGameFeed(hosted.data)
        try? FileManager.default.removeItem(at: paths.downloads)
        progressOnMain(progress, .init(phase: .finished, message: "TFT updated", fraction: 1))
        return GameUpdateResult(state: state, release: release, changed: true)
    }

    static func prepareDirectories(at paths: LauncherPaths) throws {
        let fileManager = FileManager.default
        for directory in [paths.root, paths.downloads, paths.gameCache, paths.logDirectory, paths.avdHome] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: paths.staging.path) {
            try fileManager.removeItem(at: paths.staging)
        }
        try fileManager.createDirectory(at: paths.staging, withIntermediateDirectories: true)
    }

    private func verifyGame(release: GameRelease, in resources: URL) throws {
        for apk in release.apks {
            let url = resources.appendingPathComponent(apk.name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size == apk.size else {
                throw LauncherError.integrity("Invalid size for \(apk.name)")
            }
            let hash = try SystemServices.sha256(of: url)
            guard hash == apk.sha256 else {
                throw LauncherError.integrity("SHA-256 mismatch for \(apk.name)")
            }
        }
    }

    private func fetchHostedGameFeed(
        progress: @escaping ProgressHandler
    ) throws -> (data: Data, feed: HostedGameFeed) {
        let partial = paths.downloads.appendingPathComponent("hosted-game-feed.json.partial")
        try? FileManager.default.removeItem(at: partial)
        try downloadHostedFile(
            url: MacticianIdentity.gameUpdateURL,
            to: partial,
            displayName: "TFT update information",
            expectedSize: nil,
            completedBytes: 0,
            totalBytes: 1,
            progress: progress
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: partial.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard (1 ... 1_048_576).contains(size) else {
            throw LauncherError.integrity("The TFT update information is too large")
        }
        let data = try Data(contentsOf: partial)
        let feed = try HostedGameUpdate.decodeAndVerify(data)
        try? FileManager.default.removeItem(at: partial)
        return (data, feed)
    }

    private func downloadHostedGame(
        _ release: GameRelease,
        completedBytes: Int64,
        totalBytes: Int64,
        progress: @escaping ProgressHandler
    ) throws -> URL {
        let fileManager = FileManager.default
        let resources = paths.gameReleaseDirectory(baseSHA256: release.baseSHA256)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        var downloadedBeforeThisAPK = completedBytes

        for apk in release.apks {
            try checkCancellation()
            guard let sourceURL = apk.url else {
                throw LauncherError.invalidManifest("Hosted APK \(apk.name) has no URL")
            }
            let destination = resources.appendingPathComponent(apk.name)
            if fileManager.fileExists(atPath: destination.path) {
                let attributes = try fileManager.attributesOfItem(atPath: destination.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                if size == apk.size, try SystemServices.sha256(of: destination) == apk.sha256 {
                    downloadedBeforeThisAPK += apk.size
                    continue
                }
                try fileManager.removeItem(at: destination)
            }

            let partial = paths.downloads.appendingPathComponent("game-\(apk.sha256).partial")
            try downloadHostedFile(
                url: sourceURL,
                to: partial,
                displayName: apk.name,
                expectedSize: apk.size,
                completedBytes: downloadedBeforeThisAPK,
                totalBytes: max(totalBytes, 1),
                progress: progress
            )
            let attributes = try fileManager.attributesOfItem(atPath: partial.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size == apk.size else {
                try? fileManager.removeItem(at: partial)
                throw LauncherError.integrity("Invalid size for hosted APK \(apk.name)")
            }
            guard try SystemServices.sha256(of: partial) == apk.sha256 else {
                try? fileManager.removeItem(at: partial)
                throw LauncherError.integrity("SHA-256 mismatch for hosted APK \(apk.name)")
            }
            try fileManager.moveItem(at: partial, to: destination)
            downloadedBeforeThisAPK += apk.size
        }
        try verifyGame(release: release, in: resources)
        return resources
    }

    private func saveHostedGameFeed(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: paths.hostedGameFeed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: paths.hostedGameFeed, options: .atomic)
    }

    private func downloadHostedFile(
        url: URL,
        to partial: URL,
        displayName: String,
        expectedSize: Int64?,
        completedBytes: Int64,
        totalBytes: Int64,
        progress: @escaping ProgressHandler
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = Self.hostedDownloadArguments(url: url, destination: partial)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = try SystemServices.appendHandle(for: paths.launcherLog)
        lock.lock()
        activeProcess = process
        lock.unlock()
        defer {
            lock.lock()
            activeProcess = nil
            paused = false
            lock.unlock()
        }
        try process.run()
        while process.isRunning {
            try checkCancellation()
            let downloaded = ((try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? NSNumber)?.int64Value ?? 0
            let boundedDownload = expectedSize.map { min(downloaded, $0) } ?? 0
            let overall = min(0.86, Double(completedBytes + boundedDownload) / Double(totalBytes) * 0.86)
            let isPaused = withLock { paused }
            progressOnMain(progress, .init(
                phase: isPaused ? .paused : .downloading,
                message: isPaused ? "Download paused" : "Downloading \(displayName)…",
                fraction: overall
            ))
            Thread.sleep(forTimeInterval: 0.25)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LauncherError.process("Could not download \(displayName). Check your connection and try again.")
        }
    }

    private func installComponent(
        _ component: SDKComponent,
        completedBytes: Int64,
        totalBytes: Int64,
        progress: @escaping ProgressHandler
    ) throws {
        let fileManager = FileManager.default
        let partial = paths.downloads.appendingPathComponent("\(component.id).zip.partial")
        let archive = paths.downloads.appendingPathComponent("\(component.id).zip")
        if fileManager.fileExists(atPath: archive.path),
           try SystemServices.sha256(of: archive) != component.sha256 {
            try fileManager.removeItem(at: archive)
        }

        if !fileManager.fileExists(atPath: archive.path) {
            try download(
                component,
                to: partial,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                progress: progress
            )
            let hash = try SystemServices.sha256(of: partial)
            guard hash == component.sha256 else {
                try? fileManager.removeItem(at: partial)
                throw LauncherError.integrity("SHA-256 mismatch for component \(component.id)")
            }
            try fileManager.moveItem(at: partial, to: archive)
        }

        let extractRoot = paths.staging.appendingPathComponent("\(component.id)-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: extractRoot) }
        try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        progressOnMain(progress, .init(
            phase: .extracting,
            message: "Extracting \(component.id)…",
            fraction: Double(completedBytes + component.size) / Double(totalBytes) * 0.86
        ))
        try Self.extractArchive(archive, to: extractRoot)
        let extracted = extractRoot.appendingPathComponent(component.archiveRoot, isDirectory: true)
        guard fileManager.fileExists(atPath: extracted.path) else {
            throw LauncherError.integrity("Archive \(component.id) does not contain \(component.archiveRoot)")
        }
        let target = paths.root.appendingPathComponent(component.installPath, isDirectory: true)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: extracted, to: target)
        try fileManager.removeItem(at: archive)
    }

    private func download(
        _ component: SDKComponent,
        to partial: URL,
        completedBytes: Int64,
        totalBytes: Int64,
        progress: @escaping ProgressHandler
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = Self.curlArguments(component: component, destination: partial)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = try SystemServices.appendHandle(for: paths.launcherLog)
        lock.lock()
        activeProcess = process
        lock.unlock()
        defer {
            lock.lock()
            activeProcess = nil
            paused = false
            lock.unlock()
        }
        try process.run()
        while process.isRunning {
            try checkCancellation()
            let downloaded = ((try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? NSNumber)?.int64Value ?? 0
            let overall = min(0.86, Double(completedBytes + min(downloaded, component.size)) / Double(totalBytes) * 0.86)
            let isPaused = withLock { paused }
            progressOnMain(progress, .init(
                phase: isPaused ? .paused : .downloading,
                message: isPaused ? "Download paused" : "Downloading \(component.id)…",
                fraction: overall
            ))
            Thread.sleep(forTimeInterval: 0.25)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LauncherError.process("Could not download \(component.id). Check your connection and press Retry.")
        }
    }

    private func verifySDKLayout() throws {
        for executable in [paths.adb, paths.emulator, paths.qemuImg] {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw LauncherError.integrity("Executable \(executable.lastPathComponent) was not found")
            }
        }
        guard FileManager.default.fileExists(atPath: paths.systemImage.appendingPathComponent("system.img").path) else {
            throw LauncherError.integrity("The Android system image was not fully extracted")
        }
        let output = try SystemServices.run(paths.emulator, ["-accel-check"])
        guard output.localizedCaseInsensitiveContains("installed and usable") || output.contains("accel:\n0") else {
            throw LauncherError.preflight("Android Emulator did not confirm hardware virtualization: \(output)")
        }
    }

    private func componentLayoutIsValid(_ component: SDKComponent, at target: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: target.path) else { return false }
        switch component.id {
        case "platform-tools":
            return fileManager.isExecutableFile(atPath: target.appendingPathComponent("adb").path)
                && sourceProperties(at: target).contains("Pkg.Revision=36.0.2")
        case "emulator":
            return fileManager.isExecutableFile(atPath: target.appendingPathComponent("emulator").path)
                && fileManager.isExecutableFile(atPath: target.appendingPathComponent("qemu-img").path)
                && sourceProperties(at: target).contains("Pkg.Revision=37.1.11")
                && EmulatorBrandingPatch.isSupportedOrPatched(
                    target.appendingPathComponent("qemu/darwin-aarch64/qemu-system-aarch64")
                )
        case "system-image":
            return fileManager.fileExists(atPath: target.appendingPathComponent("system.img").path)
                && fileManager.fileExists(atPath: target.appendingPathComponent("encryptionkey.img").path)
                && sourceProperties(at: target).contains("Pkg.Revision=7")
                && sourceProperties(at: target).contains("SystemImage.TagId=google_apis_playstore")
        default:
            return false
        }
    }

    private func sourceProperties(at directory: URL) -> String {
        (try? String(contentsOf: directory.appendingPathComponent("source.properties"), encoding: .utf8)) ?? ""
    }

    static func refreshRuntimeProject(at paths: LauncherPaths) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.staging, withIntermediateDirectories: true)
        let next = paths.staging.appendingPathComponent("runtime-project-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: next) }
        try fileManager.copyItem(at: paths.runtimeTemplate, to: next)
        try fileManager.copyItem(
            at: paths.emulatorHostTemplate,
            to: next.appendingPathComponent("Mactician Game Host.app", isDirectory: true)
        )

        guard fileManager.fileExists(atPath: paths.runtimeProject.path) else {
            try fileManager.moveItem(at: next, to: paths.runtimeProject)
            return
        }

        let previous = paths.staging.appendingPathComponent(
            "runtime-project-\(UUID().uuidString).previous",
            isDirectory: true
        )
        try fileManager.moveItem(at: paths.runtimeProject, to: previous)
        do {
            try fileManager.moveItem(at: next, to: paths.runtimeProject)
        } catch {
            try? fileManager.moveItem(at: previous, to: paths.runtimeProject)
            throw error
        }
        try fileManager.removeItem(at: previous)
    }

    static func unrealCommandLine(for language: GameLanguage) -> String {
        "-project=\"../../../TFT/TFT.uproject\" -opengl -novsync -ResX=1600 -ResY=900 DeviceProfile=Android_Codex -culture=\(language.id)\n"
    }

    static func prepareOverlay(
        source: URL,
        expectedSourceSHA256: String,
        destination: URL,
        stagingRoot: URL,
        language: GameLanguage
    ) throws -> String {
        let fileManager = FileManager.default
        let originalHash = try SystemServices.sha256(of: source)
        guard originalHash == expectedSourceSHA256 else {
            throw LauncherError.integrity("The source TFT base.apk failed verification")
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let candidate = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).next"
        )
        defer { try? fileManager.removeItem(at: candidate) }
        try fileManager.copyItem(at: source, to: candidate)
        try SystemServices.run(
            URL(fileURLWithPath: "/usr/bin/zip"),
            ["-q", "-d", candidate.path, "assets/UECommandLine.txt"]
        )

        let patchRoot = stagingRoot.appendingPathComponent("overlay-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: patchRoot) }
        let assets = patchRoot.appendingPathComponent("assets", isDirectory: true)
        try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
        let commandLine = unrealCommandLine(for: language)
        try Data(commandLine.utf8).write(to: assets.appendingPathComponent("UECommandLine.txt"), options: .atomic)
        try SystemServices.run(
            URL(fileURLWithPath: "/usr/bin/zip"),
            ["-q", "-9", candidate.path, "assets/UECommandLine.txt"],
            currentDirectory: patchRoot
        )
        let extracted = try SystemServices.run(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            ["-p", candidate.path, "assets/UECommandLine.txt"]
        )
        guard extracted == commandLine else {
            throw LauncherError.integrity("The ANGLE/OpenGL overlay contains an unexpected UECommandLine")
        }
        let hash = try SystemServices.sha256(of: candidate)
        try SystemServices.run(
            URL(fileURLWithPath: "/bin/mv"),
            ["-f", candidate.path, destination.path]
        )
        return hash
    }

    private func buildOverlay(release: GameRelease, resources: URL) throws -> String {
        try Self.prepareOverlay(
            source: resources.appendingPathComponent("base.apk"),
            expectedSourceSHA256: release.baseSHA256,
            destination: paths.overlayAPK,
            stagingRoot: paths.staging,
            language: .english
        )
    }

    private func createAVDIfNeeded(memoryMB: Int) throws {
        let fileManager = FileManager.default
        let essentials = [
            paths.avdDirectory.appendingPathComponent("config.ini"),
            paths.avdDirectory.appendingPathComponent("userdata-qemu.img"),
            paths.avdDirectory.appendingPathComponent("encryptionkey.img")
        ]
        if fileManager.fileExists(atPath: paths.avdINI.path),
           essentials.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) {
            return
        }
        if fileManager.fileExists(atPath: paths.avdINI.path) {
            throw LauncherError.integrity("The AVD is corrupted. Use Reset Data to create it again.")
        }
        if fileManager.fileExists(atPath: paths.avdDirectory.path) {
            try fileManager.removeItem(at: paths.avdDirectory)
        }
        let nextAVD = paths.staging.appendingPathComponent("Tft-\(UUID().uuidString).avd", isDirectory: true)
        defer { try? fileManager.removeItem(at: nextAVD) }
        try fileManager.createDirectory(at: nextAVD, withIntermediateDirectories: true)
        let config = """
        AvdId=TftPlay
        avd.ini.displayname=Mactician
        abi.type=arm64-v8a
        hw.cpu.arch=arm64
        hw.cpu.ncore=6
        hw.lcd.density=320
        hw.lcd.height=1080
        hw.lcd.width=1920
        hw.ramSize=\(memoryMB)
        hw.vmHeapSize=576
        hw.gpu.enabled=yes
        hw.gpu.mode=host
        hw.gltransport=pipe
        hw.keyboard=yes
        skin.name=1920x1080
        showDeviceFrame=no
        disk.dataPartition.size=12288M
        image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/
        tag.id=google_apis_playstore
        tag.display=Google Play
        PlayStore.enabled=true
        fastboot.forceColdBoot=yes
        fastboot.forceFastBoot=no
        avd.ini.encoding=UTF-8
        """
        try Data(config.utf8).write(to: nextAVD.appendingPathComponent("config.ini"), options: .atomic)
        let ini = """
        avd.ini.encoding=UTF-8
        path=\(paths.avdDirectory.path)
        path.rel=TftPlay.avd
        target=android-36
        """
        try SystemServices.run(paths.qemuImg, [
            "create", "-f", "qcow2",
            nextAVD.appendingPathComponent("userdata-qemu.img").path,
            "12G"
        ])
        try fileManager.copyItem(
            at: paths.systemImage.appendingPathComponent("encryptionkey.img"),
            to: nextAVD.appendingPathComponent("encryptionkey.img")
        )
        try fileManager.createDirectory(at: paths.avdHome, withIntermediateDirectories: true)
        try fileManager.moveItem(at: nextAVD, to: paths.avdDirectory)
        try Data(ini.utf8).write(to: paths.avdINI, options: .atomic)
    }

    private func provisionGame(release: GameRelease, resources: URL) throws {
        let environment = androidEnvironment()
        _ = try SystemServices.run(paths.adb, Self.adbArguments(["start-server"]), environment: environment)
        if (try? SystemServices.run(
            paths.adb,
            Self.adbArguments(["-s", "emulator-5582", "get-state"]),
            environment: environment
        )) != nil {
            throw LauncherError.process("The TFT emulator is already running. Close it and retry the installation.")
        }

        let emulator = Process()
        emulator.executableURL = paths.emulator
        let memoryMB = GuestResourceOptions.installationMemoryMB(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
        emulator.arguments = Self.emulatorArguments(
            initializeData: !FileManager.default.fileExists(atPath: paths.avdBootCompleted.path),
            logicalCPUCount: ProcessInfo.processInfo.processorCount,
            memoryMB: memoryMB
        )
        emulator.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let log = try SystemServices.appendHandle(for: paths.launcherLog)
        emulator.standardOutput = log
        emulator.standardError = log
        try emulator.run()
        lock.lock()
        activeProcess = emulator
        lock.unlock()
        defer {
            if emulator.isRunning { emulator.terminate() }
            lock.lock()
            if activeProcess === emulator { activeProcess = nil }
            lock.unlock()
            try? log.close()
        }

        try waitFor(timeout: 180, description: "ADB") {
            guard emulator.isRunning else { throw LauncherError.process("Android Emulator exited during provisioning") }
            return (try? SystemServices.run(
                self.paths.adb,
                Self.adbArguments(["-s", "emulator-5582", "get-state"]),
                environment: environment
            )) != nil
        }
        try waitFor(timeout: 180, description: "Android boot") {
            let value = try? SystemServices.run(
                self.paths.adb,
                Self.adbArguments(["-s", "emulator-5582", "shell", "getprop", "sys.boot_completed"]),
                environment: environment
            )
            return value?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }
        let apkPaths = release.apks.map { resources.appendingPathComponent($0.name).path }
        _ = try SystemServices.run(
            paths.adb,
            Self.gameInstallArguments(apkPaths: apkPaths),
            environment: environment
        )
        let packagePaths = try SystemServices.run(paths.adb, Self.adbArguments([
            "-s", "emulator-5582", "shell", "pm", "path", release.packageName
        ]), environment: environment)
        guard let basePath = packagePaths
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasSuffix("/base.apk") })?
            .replacingOccurrences(of: "package:", with: "") else {
            throw LauncherError.integrity("TFT base.apk was not found after installation")
        }
        let guestHash = try SystemServices.run(paths.adb, Self.adbArguments([
            "-s", "emulator-5582", "shell", "sha256sum", basePath
        ]), environment: environment).split(separator: " ").first.map(String.init)
        guard guestHash == release.baseSHA256 else {
            throw LauncherError.unsupportedGame("The installed TFT version does not match verified version \(release.version)")
        }
        // Android 16 can acknowledge a large split-APK install before all
        // /data/app extents reach the virtual disk. Stopping QEMU immediately
        // leaves PackageManager metadata behind while the APK files disappear
        // on the next cold boot. Flush the guest filesystem before emu kill.
        _ = try SystemServices.run(
            paths.adb,
            Self.adbArguments(["-s", "emulator-5582", "shell", "sync"]),
            environment: environment
        )
        Thread.sleep(forTimeInterval: 2)
        _ = try? SystemServices.run(
            paths.adb,
            Self.adbArguments(["-s", "emulator-5582", "emu", "kill"]),
            environment: environment
        )
        let deadline = Date().addingTimeInterval(30)
        while emulator.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
    }

    private func waitFor(timeout: TimeInterval, description: String, condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try checkCancellation()
            if try condition() { return }
            Thread.sleep(forTimeInterval: 1)
        }
        throw LauncherError.process("Timed out: \(description)")
    }

    private func androidEnvironment() -> [String: String] {
        [
            "ANDROID_SDK_ROOT": paths.sdk.path,
            "ANDROID_AVD_HOME": paths.avdHome.path,
            "ANDROID_ADB_SERVER_PORT": "5038",
            "ADB_MDNS_AUTO_CONNECT": ""
        ]
    }

    private func checkCancellation() throws {
        if withLock({ cancelled }) { throw LauncherError.cancelled }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func progressOnMain(_ handler: @escaping ProgressHandler, _ value: InstallerProgress) {
        DispatchQueue.main.async { handler(value) }
    }
}
