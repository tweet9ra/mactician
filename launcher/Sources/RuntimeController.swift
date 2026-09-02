import Foundation

final class RuntimeController {
    typealias EventHandler = (RuntimeEvent) -> Void

    private let paths: LauncherPaths
    private let parsingQueue = DispatchQueue(label: "dev.sergeinaumov.mactician.runtime-events")
    private var eventBuffer = Data()
    private var process: Process?
    private var outputPipe: Pipe?

    init(paths: LauncherPaths) {
        self.paths = paths
    }

    var isRunning: Bool { process?.isRunning == true }

    func start(
        profile: LaunchProfile,
        effectsQuality: EffectsQuality,
        language: GameLanguage,
        cpuCores: Int,
        memoryMB: Int,
        uiScalePercent: Int,
        state: InstallState,
        gameRelease: GameRelease,
        gameResources: URL,
        events: @escaping EventHandler
    ) throws {
        guard !isRunning else {
            throw LauncherError.process("TFT is already launching")
        }
        guard state.isReady,
              state.gamePackageName.map({ $0 == gameRelease.packageName }) ?? true,
              state.gameVersion == gameRelease.version,
              state.gameBaseSHA256 == gameRelease.baseSHA256,
              state.overlaySHA256 != nil else {
            throw LauncherError.unsupportedGame("The installed TFT version is not supported by this launcher build")
        }
        // QEMU replaces the wrapper application's Dock icon and exposes its
        // implementation name in the native title bar after Qt starts. Refresh
        // the verified branding patch before every launch so existing installs
        // are upgraded without requiring Repair.
        try EmulatorBrandingPatch.apply(
            at: paths.qemuSystem,
            entitlements: paths.qemuHypervisorEntitlements
        )
        // Refresh small launcher-owned scripts on every start so a launcher
        // update can repair an existing AVD without reinstalling Android or TFT.
        try InstallerService.refreshRuntimeProject(at: paths)
        let overlayHash = try InstallerService.prepareOverlay(
            source: gameResources.appendingPathComponent("base.apk"),
            expectedSourceSHA256: gameRelease.baseSHA256,
            destination: paths.overlayAPK,
            stagingRoot: paths.staging,
            language: language
        )
        let graphicsProfile = paths.effectsProfile(for: effectsQuality)
        let profileHash = try SystemServices.sha256(of: graphicsProfile)
        guard GuestResourceOptions.cpuCores(
            logicalCPUCount: ProcessInfo.processInfo.processorCount
        ).contains(cpuCores) else {
            throw LauncherError.preflight("The selected Android vCPU count is unavailable on this Mac")
        }
        guard GuestResourceOptions.memoryMB(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        ).contains(memoryMB) else {
            throw LauncherError.preflight("The selected Android RAM size is unavailable on this Mac")
        }
        guard let uiScale = InterfaceScaleOptions.runtimeValue(percent: uiScalePercent) else {
            throw LauncherError.preflight("The selected interface scale is unavailable")
        }
        let runtime = Process()
        let pipe = Pipe()
        runtime.executableURL = paths.runtimeHelper
        runtime.standardOutput = pipe
        runtime.standardError = try SystemServices.appendHandle(for: paths.launcherLog)
        runtime.environment = ProcessInfo.processInfo.environment.merging([
            "TFT_RUNTIME_PROJECT": paths.runtimeProject.path,
            "TFT_LAUNCH_LOG": paths.launcherLog.path,
            "TFT_ADB": paths.adb.path,
            "TFT_EMULATOR": paths.emulator.path,
            "TFT_ROOT_SDK": paths.sdk.path,
            "TFT_ROOT_AVD_HOME": paths.avdHome.path,
            "TFT_AVD_HOME": paths.avdHome.path,
            "TFT_AVD_NAME": "TftPlay",
            "TFT_SERIAL": "emulator-5582",
            "TFT_EMULATOR_PORT": "5582",
            "TFT_ADB_SERVER_PORT": "5038",
            "ANDROID_ADB_SERVER_PORT": "5038",
            "ADB_MDNS_AUTO_CONNECT": "",
            "TFT_LAUNCHER": paths.runtimeTemplate.appendingPathComponent("run-tft-google-play.command").path,
            "TFT_GLTRANSPORT": "virtio-gpu-asg",
            "TFT_EXPECTED_GLTRANSPORT_BASELINE": "pipe",
            "TFT_AUDIO_ENABLED": "1",
            "TFT_ASG_WRITE_STEP_SIZE": "16384",
            "TFT_DISPLAY_SIZE": profile.displaySize,
            "TFT_DISPLAY_DENSITY": "\(profile.density)",
            "TFT_GAME_LANGUAGE": language.id,
            "TFT_PACKAGE": GameRelease.vietnamPackageName,
            "TFT_FALLBACK_PACKAGE": GameRelease.globalPackageName,
            "TFT_CPU_CORES": "\(cpuCores)",
            "TFT_MEMORY_MB": "\(memoryMB)",
            "TFT_UI_SCALE": uiScale,
            "TFT_PERFORMANCE_MODE": effectsQuality == .maximum ? "1" : "0",
            "TFT_GRAPHICS_PROFILE": "osft",
            "TFT_MVK_QUEUE_MODE": "async",
            "MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE": "64",
            "MVK_CONFIG_FAST_MATH_ENABLED": "1",
            "TFT_INPUT_BRIDGE_ENABLED": "0",
            "TFT_ANGLE_OPENGL_APK": paths.overlayAPK.path,
            "TFT_ANGLE_OPENGL_APK_SHA256": overlayHash,
            "TFT_ORIGINAL_BASE_APK_SHA256": gameRelease.baseSHA256,
            "TFT_ANGLE_OPENGL_PROFILE": graphicsProfile.path,
            "TFT_ANGLE_OPENGL_PROFILE_SHA256": profileHash,
            "TFT_ANGLE_DISABLED_FEATURES": "preferSubmitAtFBOBoundary"
        ]) { _, new in new }

        outputPipe = pipe
        process = runtime
        eventBuffer.removeAll(keepingCapacity: true)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.parsingQueue.async { self?.consume(data, events: events) }
        }
        runtime.terminationHandler = { [weak self] process in
            self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                events(RuntimeEvent(event: .stopped, code: process.terminationStatus))
            }
        }
        try runtime.run()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [paths] in
            let environment = ["ANDROID_ADB_SERVER_PORT": "5038"]
            _ = try? SystemServices.run(paths.adb, ["-s", "emulator-5582", "emu", "kill"], environment: environment)
        }
        process.terminate()
    }

    private func consume(_ data: Data, events: @escaping EventHandler) {
        eventBuffer.append(data)
        while let newline = eventBuffer.firstIndex(of: 0x0A) {
            let line = eventBuffer[..<newline]
            eventBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let event = try? JSONDecoder().decode(RuntimeEvent.self, from: Data(line)) else {
                continue
            }
            DispatchQueue.main.async { events(event) }
        }
    }
}
