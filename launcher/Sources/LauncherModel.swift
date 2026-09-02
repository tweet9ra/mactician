import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LauncherModel: ObservableObject {
    enum Mode: Equatable {
        case needsInstall
        case installing
        case ready
        case launching
        case playing
        case deviceRunning
        case stopping
        case failed
    }

    @Published var mode: Mode = .needsInstall
    @Published var status = "Preparing…"
    @Published var detail = ""
    @Published var progress = 0.0
    @Published var licenseAccepted = false
    @Published var selectedProfileID: String
    @Published var selectedEffectsQualityID: String
    @Published var selectedLanguageID: String
    @Published var selectedMemoryMB: Int
    @Published var selectedCPUCores: Int
    @Published var selectedUIScalePercent: Int
    @Published var isPaused = false
    @Published var installerPhase: InstallerProgress.Phase = .checking
    @Published var installationWasCancelled = false
    @Published var failure: LauncherFailure?
    @Published var hotkeyStatus: LauncherHotkeyStatus = .permissionRequired
    @Published var announcement: LauncherAnnouncement?
    @Published private(set) var gameUpdateResultMessage: String?
    @Published private(set) var isGameUpdateAvailable = false
    @Published private(set) var isCheckingGameUpdate = false
    @Published var shouldShowTelemetryNotice: Bool
    @Published var extendedDiagnosticsEnabled: Bool
    @Published private(set) var activeConfiguration: LaunchConfigurationSnapshot?
    @Published private(set) var gameRelease: GameRelease
    @Published private(set) var selectedRuntimeKind = GameRuntimeKind.androidEmulator
    @Published private(set) var nativeIPadDescriptor: NativeIPadAppDescriptor?
    @Published private(set) var nativeIPadLastValidatedAt: Date?
    @Published private(set) var nativeIPadValidationError: String?
    @Published private(set) var nativeIPadHasSavedState = false

    let paths: LauncherPaths
    let manifest: ReleaseManifest
    let nativeIPadRuntimeEnabled: Bool
    private(set) var installState: InstallState
    private let installer: InstallerService
    private let androidRuntime: AndroidRuntimeControllerAdapter
    private let nativeRuntime: NativeIPadRuntimeController
    private let nativeValidator: NativeIPadRuntimeValidator
    private let nativeStateStore: NativeIPadRuntimeStateStore
    private let telemetry = LauncherTelemetryService()
    private let inputBridge = InputBridgeService()
    private let audioRecovery = EmulatorAudioRecoveryService()
    private let fpsOverlay = FPSOverlayService()
    private let loginAnimationRepair = RiotLoginAnimationRepairService()
    private var emulatorPID: pid_t?
    private var runtimeHadError = false
    private var stopRequested = false
    private var installCancellationRequested = false
    private var launchProfile: LaunchProfile?
    private var launchEffectsQuality: EffectsQuality?
    private var hotkeyEventTapActive = false
    private var hotkeyEventTapAttemptFailed = false
    private var gameSessionTracker = GameSessionTracker()
    private var pendingAnnouncements: [LauncherAnnouncement] = []
    private var activeRuntimeKind: GameRuntimeKind?

    init() {
        do {
            let paths = try LauncherPaths()
            let manifest = try SystemServices.loadManifest(from: paths.manifest)
            self.paths = paths
            self.manifest = manifest
            var restoredState = SystemServices.loadState(from: paths.stateFile)
            let restoredRelease = (try? HostedGameUpdate.loadVerifiedFeed(from: paths.hostedGameFeed).release)
                ?? manifest.game
            if restoredState.gamePackageName == nil,
               restoredState.gameVersion == restoredRelease.version,
               restoredState.gameBaseSHA256 == restoredRelease.baseSHA256 {
                restoredState.gamePackageName = restoredRelease.packageName
                try? SystemServices.saveState(restoredState, to: paths.stateFile)
            }
            installState = restoredState
            gameRelease = restoredRelease
            installer = InstallerService(paths: paths, manifest: manifest)
            androidRuntime = AndroidRuntimeControllerAdapter(runtime: RuntimeController(paths: paths))
            let nativeValidator = NativeIPadRuntimeValidator()
            self.nativeValidator = nativeValidator
            nativeRuntime = NativeIPadRuntimeController(validator: nativeValidator)
            let nativeStateStore = NativeIPadRuntimeStateStore(stateURL: paths.nativeIPadStateFile)
            self.nativeStateStore = nativeStateStore
            nativeIPadRuntimeEnabled = ExperimentalFeatures.nativeIPadRuntimeEnabled
            selectedRuntimeKind = GameRuntimeSelection.restoredKind(
                savedValue: UserDefaults.standard.string(
                    forKey: ExperimentalFeatures.selectedRuntimeDefaultsKey
                ),
                nativeEnabled: nativeIPadRuntimeEnabled
            )
            let saved = UserDefaults.standard.string(forKey: "launchProfile") ?? "balanced"
            selectedProfileID = manifest.profiles.contains(where: { $0.id == saved }) ? saved : "balanced"
            selectedEffectsQualityID = EffectsQuality.selection(
                saved: UserDefaults.standard.string(forKey: "effectsQuality")
            ).id
            selectedLanguageID = GameLanguage.language(
                withID: UserDefaults.standard.string(forKey: "gameLanguage")
            ).id
            let memoryOptions = GuestResourceOptions.memoryMB(
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
            )
            selectedMemoryMB = GuestResourceOptions.selection(
                saved: UserDefaults.standard.integer(forKey: "androidMemoryMB"),
                options: memoryOptions,
                fallback: GuestResourceOptions.defaultMemoryMB
            )
            let cpuOptions = GuestResourceOptions.cpuCores(
                logicalCPUCount: ProcessInfo.processInfo.processorCount
            )
            selectedCPUCores = GuestResourceOptions.selection(
                saved: UserDefaults.standard.integer(forKey: "androidCPUCores"),
                options: cpuOptions,
                fallback: HostSizing.guestCPUCores(
                    logicalCPUCount: ProcessInfo.processInfo.processorCount
                )
            )
            selectedUIScalePercent = InterfaceScaleOptions.selection(
                saved: UserDefaults.standard.integer(forKey: "uiScalePercent")
            )
            shouldShowTelemetryNotice = telemetry.shouldShowNotice
            extendedDiagnosticsEnabled = telemetry.isExtendedDiagnosticsEnabled
            if nativeIPadRuntimeEnabled {
                switch nativeStateStore.load() {
                case .missing:
                    break
                case let .loaded(state, url):
                    nativeIPadHasSavedState = true
                    do {
                        let descriptor = try nativeValidator.validate(url)
                        let validatedAt = Date()
                        try nativeStateStore.save(
                            descriptor: descriptor,
                            sourceKind: state.sourceKind,
                            validatedAt: validatedAt
                        )
                        nativeIPadDescriptor = descriptor
                        nativeIPadLastValidatedAt = validatedAt
                        nativeIPadValidationError = nil
                    } catch {
                        nativeIPadValidationError = NativeIPadDiagnostics.displayMessage(
                            error.localizedDescription
                        )
                    }
                case let .invalid(message):
                    nativeIPadHasSavedState = true
                    nativeIPadValidationError = message
                }
            }
            applySelectedRuntimePresentation()
            if selectedRuntimeKind == .androidEmulator { refreshHotkeyStatus() }
            inputBridge.observeStatus { [weak self] eventTapActive, eventTapAttemptFailed in
                self?.updateHotkeyActivity(
                    eventTapActive: eventTapActive,
                    eventTapAttemptFailed: eventTapAttemptFailed
                )
            }
            requestAnnouncement(for: .launcherStarted)
        } catch {
            fatalError("Launcher resources are invalid: \(error)")
        }
    }

    var selectedProfile: LaunchProfile {
        manifest.profiles.first(where: { $0.id == selectedProfileID }) ?? manifest.profiles[0]
    }

    var selectedLanguage: GameLanguage {
        GameLanguage.language(withID: selectedLanguageID)
    }

    var selectedEffectsQuality: EffectsQuality {
        EffectsQuality.selection(saved: selectedEffectsQualityID)
    }

    var availableMemoryMB: [Int] {
        GuestResourceOptions.memoryMB(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    var availableCPUCores: [Int] {
        GuestResourceOptions.cpuCores(logicalCPUCount: ProcessInfo.processInfo.processorCount)
    }

    var availableUIScalePercents: [Int] {
        InterfaceScaleOptions.percentages
    }

    var recommendedResources: GuestResourceConfiguration {
        GuestResourceOptions.recommended(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            logicalCPUCount: ProcessInfo.processInfo.processorCount
        )
    }

    var hostResourceSummary: String {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return LauncherL10n.format(
            "settings.performance.host_format",
            memoryGB,
            ProcessInfo.processInfo.processorCount
        )
    }

    var gameDisplayVersion: String {
        LauncherMetadata.gameDisplayVersion(from: gameRelease.version)
    }

    var downloadSize: String {
        LauncherMetadata.byteCount(LauncherMetadata.totalDownloadBytes(in: manifest))
    }

    var requiredFreeSpace: String {
        LauncherMetadata.byteCount(manifest.minimumFreeBytes)
    }

    var androidSystemSummary: String {
        let api = LauncherMetadata.androidAPILevel(in: manifest) ?? "?"
        return LauncherL10n.format("install.android_api_format", api)
    }

    var emulatorVersion: String {
        LauncherMetadata.componentVersion("emulator", in: manifest) ?? "?"
    }

    var settingsLocked: Bool {
        mode == .launching || mode == .playing || mode == .deviceRunning || mode == .stopping
    }

    var maintenanceLocked: Bool {
        mode == .installing || isCheckingGameUpdate || settingsLocked
    }

    var runtimeSelectionLocked: Bool {
        mode == .installing || isCheckingGameUpdate || settingsLocked
    }

    var isNativeIPadRuntimeSelected: Bool {
        selectedRuntimeKind == .nativeIPadExperimental
    }

    var nativeIPadVersionSummary: String? {
        guard let descriptor = nativeIPadDescriptor else { return nil }
        switch (descriptor.shortVersion, descriptor.buildVersion) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return LauncherL10n.format("native_ipad.build_format", build)
        case (.none, .none):
            return nil
        }
    }

    var selectedConfiguration: LaunchConfigurationSnapshot {
        LaunchConfigurationSnapshot(
            languageTitle: selectedLanguage.title,
            resolution: selectedProfile.displayResolution,
            effectsQualityTitle: selectedEffectsQuality.title,
            uiScalePercent: selectedUIScalePercent,
            memoryMB: selectedMemoryMB,
            cpuCores: selectedCPUCores
        )
    }

    func selectProfile(_ id: String) {
        guard !settingsLocked else { return }
        selectedProfileID = id
        UserDefaults.standard.set(id, forKey: "launchProfile")
    }

    func selectEffectsQuality(_ id: String) {
        guard !settingsLocked, let quality = EffectsQuality(rawValue: id) else { return }
        selectedEffectsQualityID = quality.id
        UserDefaults.standard.set(quality.id, forKey: "effectsQuality")
    }

    func selectLanguage(_ id: String) {
        guard !settingsLocked else { return }
        let language = GameLanguage.language(withID: id)
        selectedLanguageID = language.id
        UserDefaults.standard.set(language.id, forKey: "gameLanguage")
    }

    func selectMemoryMB(_ memoryMB: Int) {
        guard !settingsLocked, availableMemoryMB.contains(memoryMB) else { return }
        selectedMemoryMB = memoryMB
        UserDefaults.standard.set(memoryMB, forKey: "androidMemoryMB")
    }

    func selectCPUCores(_ cpuCores: Int) {
        guard !settingsLocked, availableCPUCores.contains(cpuCores) else { return }
        selectedCPUCores = cpuCores
        UserDefaults.standard.set(cpuCores, forKey: "androidCPUCores")
    }

    func selectUIScalePercent(_ percent: Int) {
        guard !settingsLocked, availableUIScalePercents.contains(percent) else { return }
        selectedUIScalePercent = percent
        UserDefaults.standard.set(percent, forKey: "uiScalePercent")
    }

    func selectRuntime(_ kind: GameRuntimeKind) {
        guard kind != selectedRuntimeKind,
              GameRuntimeSelection.canSelect(
                kind,
                nativeEnabled: nativeIPadRuntimeEnabled,
                stateMachineLocked: runtimeSelectionLocked,
                androidRunning: androidRuntime.isRunning,
                nativeRunning: nativeRuntime.isRunning
              ) else { return }
        selectedRuntimeKind = kind
        UserDefaults.standard.set(
            kind.rawValue,
            forKey: ExperimentalFeatures.selectedRuntimeDefaultsKey
        )
        failure = nil
        activeConfiguration = nil
        isGameUpdateAvailable = false
        isCheckingGameUpdate = false
        loginAnimationRepair.stop()
        audioRecovery.stop()
        fpsOverlay.stop()
        inputBridge.stop()
        applySelectedRuntimePresentation()
        if kind == .androidEmulator { refreshHotkeyStatus() }
    }

    func chooseNativeIPadApplication() {
        guard nativeIPadRuntimeEnabled,
              selectedRuntimeKind == .nativeIPadExperimental,
              !maintenanceLocked,
              !nativeRuntime.isRunning,
              !androidRuntime.isRunning else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = LauncherL10n.text("native_ipad.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        validateAndPersistNativeApplication(at: url)
    }

    func revalidateNativeIPadApplication() {
        guard selectedRuntimeKind == .nativeIPadExperimental,
              !maintenanceLocked,
              !nativeRuntime.isRunning,
              !androidRuntime.isRunning,
              let url = nativeIPadDescriptor?.canonicalURL else { return }
        validateAndPersistNativeApplication(at: url)
    }

    func forgetNativeIPadApplication() {
        guard selectedRuntimeKind == .nativeIPadExperimental,
              !maintenanceLocked,
              !nativeRuntime.isRunning,
              !androidRuntime.isRunning else { return }
        do {
            try nativeStateStore.reset()
            nativeIPadDescriptor = nil
            nativeIPadLastValidatedAt = nil
            nativeIPadValidationError = nil
            nativeIPadHasSavedState = false
            failure = nil
            mode = .needsInstall
            status = LauncherL10n.text("native_ipad.not_selected.title")
            detail = LauncherL10n.text("native_ipad.not_selected.description")
        } catch {
            fail(
                "Could not forget the selected application: "
                    + NativeIPadDiagnostics.displayMessage(error.localizedDescription),
                origin: .reset
            )
        }
    }

    func applyRecommendedResources() {
        guard !settingsLocked else { return }
        let recommendation = recommendedResources
        selectMemoryMB(recommendation.memoryMB)
        selectCPUCores(recommendation.cpuCores)
    }

    func completeTelemetryNotice(extendedDiagnostics: Bool) {
        telemetry.completeNotice(extendedDiagnostics: extendedDiagnostics)
        extendedDiagnosticsEnabled = telemetry.isExtendedDiagnosticsEnabled
        shouldShowTelemetryNotice = false
    }

    func setExtendedDiagnosticsEnabled(_ enabled: Bool) {
        telemetry.setExtendedDiagnosticsEnabled(enabled)
        extendedDiagnosticsEnabled = telemetry.isExtendedDiagnosticsEnabled
    }

    func install(repair: Bool = false) {
        guard selectedRuntimeKind == .androidEmulator else { return }
        guard repair || licenseAccepted else {
            fail(
                "Accept the Android SDK License Agreement before installing.",
                origin: .installation
            )
            return
        }
        failure = nil
        installationWasCancelled = false
        installCancellationRequested = false
        mode = .installing
        isPaused = false
        installerPhase = .checking
        status = repair ? "Repairing installation…" : "Installing…"
        detail = "You can pause the download."
        progress = 0
        installer.install(repair: repair, progress: { [weak self] value in
            guard let self else { return }
            progress = value.fraction
            status = value.message
            installerPhase = value.phase
            isPaused = value.phase == .paused
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(state):
                installCancellationRequested = false
                installState = state
                gameRelease = (try? HostedGameUpdate.loadVerifiedFeed(from: paths.hostedGameFeed).release)
                    ?? manifest.game
                isGameUpdateAvailable = false
                mode = .ready
                progress = 1
                status = "Ready to play"
                detail = "Choose graphics and language, then press Play."
            case let .failure(error):
                if InstallerCompletionPresentation.isUserCancellation(
                    requested: installCancellationRequested,
                    error: error
                ) {
                    installCancellationRequested = false
                    installationWasCancelled = true
                    mode = .needsInstall
                    status = "Installation stopped"
                    detail = "The next installation will resume incomplete downloads."
                    return
                }
                fail(
                    error.localizedDescription,
                    origin: failureOrigin(for: error, fallback: .installation)
                )
            }
        })
    }

    func togglePause() {
        if isPaused {
            installer.resume()
            isPaused = false
        } else {
            installer.pause()
            isPaused = true
        }
    }

    func cancelInstall() {
        installCancellationRequested = true
        installationWasCancelled = true
        installer.cancel()
        mode = .needsInstall
        status = "Installation stopped"
        detail = "The next installation will resume incomplete downloads."
    }

    func play() {
        guard mode == .ready,
              !androidRuntime.isRunning,
              !nativeRuntime.isRunning else { return }
        if selectedRuntimeKind == .androidEmulator {
            guard !shouldShowTelemetryNotice,
                  !isCheckingGameUpdate,
                  !isGameUpdateAvailable else { return }
        }
        failure = nil
        runtimeHadError = false
        stopRequested = false
        emulatorPID = nil
        activeRuntimeKind = selectedRuntimeKind
        mode = .launching
        do {
            switch selectedRuntimeKind {
            case .androidEmulator:
                let profile = selectedProfile
                let effectsQuality = selectedEffectsQuality
                let language = selectedLanguage
                launchProfile = profile
                launchEffectsQuality = effectsQuality
                activeConfiguration = selectedConfiguration
                status = "Launching TFT…"
                detail = "Starting the game in \(selectedLanguage.title)."
                try androidRuntime.launch(
                    configuration: .android(AndroidRuntimeLaunchConfiguration(
                        profile: profile,
                        effectsQuality: effectsQuality,
                        language: language,
                        cpuCores: selectedCPUCores,
                        memoryMB: selectedMemoryMB,
                        uiScalePercent: selectedUIScalePercent,
                        state: installState,
                        gameRelease: gameRelease,
                        gameResources: paths.gameResources(for: gameRelease)
                    ))
                ) { [weak self] event in
                    self?.handle(event)
                }
            case .nativeIPadExperimental:
                guard let savedDescriptor = nativeIPadDescriptor else {
                    throw LauncherError.integrity("Choose and validate a prepared iPad application first")
                }
                let descriptor = try nativeValidator.validate(savedDescriptor.canonicalURL)
                let validatedAt = Date()
                try nativeStateStore.save(descriptor: descriptor, validatedAt: validatedAt)
                nativeIPadDescriptor = descriptor
                nativeIPadLastValidatedAt = validatedAt
                nativeIPadValidationError = nil
                activeConfiguration = nil
                status = LauncherL10n.text("native_ipad.launching")
                detail = LauncherL10n.text("native_ipad.warning")
                try nativeRuntime.launch(configuration: .nativeIPad(descriptor)) { [weak self] event in
                    self?.handle(event)
                }
            }
        } catch {
            activeRuntimeKind = nil
            let message = selectedRuntimeKind == .nativeIPadExperimental
                ? NativeIPadDiagnostics.displayMessage(error.localizedDescription)
                : error.localizedDescription
            if selectedRuntimeKind == .nativeIPadExperimental {
                recordNativeError(message)
            }
            fail(
                message,
                origin: failureOrigin(for: error, fallback: .launch)
            )
        }
    }

    func stopGame() {
        guard mode == .launching || mode == .playing || mode == .deviceRunning else { return }
        stopRequested = true
        mode = .stopping
        status = activeRuntimeKind == .nativeIPadExperimental
            ? LauncherL10n.text("native_ipad.stopping")
            : "Stopping emulator…"
        loginAnimationRepair.stop()
        audioRecovery.stop()
        fpsOverlay.stop()
        inputBridge.stop()
        switch activeRuntimeKind {
        case .nativeIPadExperimental:
            nativeRuntime.stop()
        case .androidEmulator, .none:
            androidRuntime.stop()
        }
    }

    func repair() {
        if selectedRuntimeKind == .nativeIPadExperimental {
            revalidateNativeIPadApplication()
            return
        }
        guard !maintenanceLocked, !androidRuntime.isRunning, !nativeRuntime.isRunning else { return }
        licenseAccepted = true
        install(repair: true)
    }

    func updateGame() {
        guard selectedRuntimeKind == .androidEmulator,
              mode == .ready, isGameUpdateAvailable,
              !androidRuntime.isRunning, !nativeRuntime.isRunning else { return }
        failure = nil
        gameUpdateResultMessage = nil
        installationWasCancelled = false
        installCancellationRequested = false
        mode = .installing
        isPaused = false
        installerPhase = .checking
        status = "Checking for TFT updates…"
        detail = "Updates are downloaded securely from sergeinaumov.dev."
        progress = 0
        installer.updateGame(currentState: installState, progress: { [weak self] value in
            guard let self else { return }
            progress = value.fraction
            status = value.message
            installerPhase = value.phase
            isPaused = value.phase == .paused
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(update):
                installState = update.state
                gameRelease = update.release
                isGameUpdateAvailable = false
                mode = .ready
                progress = 1
                status = update.changed ? "TFT updated" : "TFT is up to date"
                detail = update.changed
                    ? "The new game version is ready to play."
                    : "No game update is available."
                let displayVersion = LauncherMetadata.gameDisplayVersion(from: update.release.version)
                gameUpdateResultMessage = LauncherL10n.format(
                    update.changed ? "game_update.updated.message" : "game_update.current.message",
                    displayVersion
                )
                let versionCode = update.release.versionCode.map(String.init) ?? "unknown"
                SystemServices.appendLog(
                    "Game update check completed: \(update.changed ? "installed" : "already current") "
                        + "\(update.release.version) (versionCode \(versionCode)).",
                    to: paths.launcherLog
                )
            case let .failure(error):
                fail(
                    error.localizedDescription,
                    origin: failureOrigin(for: error, fallback: .installation)
                )
            }
        })
    }

    func refreshGameUpdateAvailability() {
        guard selectedRuntimeKind == .androidEmulator,
              mode == .ready,
              !androidRuntime.isRunning,
              !nativeRuntime.isRunning,
              !isCheckingGameUpdate else { return }
        isCheckingGameUpdate = true
        isGameUpdateAvailable = false
        installer.checkGameUpdateAvailability(currentState: installState) { [weak self] result in
            guard let self else { return }
            isCheckingGameUpdate = false
            switch result {
            case let .success(availability):
                isGameUpdateAvailable = availability.isAvailable
                if availability.isAvailable {
                    let versionCode = availability.release.versionCode.map(String.init) ?? "unknown"
                    SystemServices.appendLog(
                        "TFT update available: \(availability.release.version) "
                            + "(versionCode \(versionCode)).",
                        to: paths.launcherLog
                    )
                }
            case .failure:
                isGameUpdateAvailable = false
            }
        }
    }

    func dismissGameUpdateResult() {
        gameUpdateResultMessage = nil
    }

    func reset() {
        guard selectedRuntimeKind == .androidEmulator,
              !maintenanceLocked,
              !androidRuntime.isRunning,
              !nativeRuntime.isRunning else { return }
        loginAnimationRepair.stop()
        audioRecovery.stop()
        fpsOverlay.stop()
        inputBridge.stop()
        installer.cancel()
        do {
            if FileManager.default.fileExists(atPath: paths.root.path) {
                try FileManager.default.removeItem(at: paths.root)
            }
            installState = InstallState()
            isGameUpdateAvailable = false
            isCheckingGameUpdate = false
            mode = .needsInstall
            failure = nil
            installationWasCancelled = false
            activeConfiguration = nil
            progress = 0
            status = "Data deleted"
            detail = "The next installation will create a clean AVD. Riot sign-in and game data were removed."
        } catch {
            fail("Could not delete data: \(error.localizedDescription)", origin: .reset)
        }
    }

    func openDataFolder() {
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.root)
    }

    func openLog() {
        if FileManager.default.fileExists(atPath: paths.launcherLog.path) {
            NSWorkspace.shared.open(paths.launcherLog)
        } else {
            openDataFolder()
        }
    }

    func requestInputPermissions() {
        guard selectedRuntimeKind == .androidEmulator else { return }
        inputBridge.requestPermissions()
        refreshHotkeyStatus()
    }

    func refreshHotkeyStatus() {
        guard selectedRuntimeKind == .androidEmulator else {
            hotkeyStatus = .ready
            return
        }
        let facts = InputBridgeService.permissionFacts(
            eventTapActive: hotkeyEventTapActive,
            eventTapAttemptFailed: hotkeyEventTapAttemptFailed
        )
        hotkeyStatus = LauncherHotkeyPresentation.status(for: facts)
    }

    func recoverFromFailure() {
        guard let failure else { return }
        self.failure = nil
        if selectedRuntimeKind == .nativeIPadExperimental {
            if nativeIPadDescriptor != nil {
                revalidateNativeIPadApplication()
            } else {
                applySelectedRuntimePresentation()
                chooseNativeIPadApplication()
            }
            return
        }
        switch failure.recoveryAction {
        case .retryInstallation, .repairInstallation:
            licenseAccepted = true
            install(repair: true)
        case .tryLaunchAgain, .restartGame:
            mode = .ready
            play()
        case .none:
            break
        }
    }

    func shutdown() {
        installer.cancel()
        loginAnimationRepair.stop()
        audioRecovery.stop()
        fpsOverlay.stop()
        inputBridge.stop()
        finishGameSession(showAnnouncement: false)
        androidRuntime.shutdown()
        nativeRuntime.shutdown()
    }

    func dismissAnnouncement() {
        if pendingAnnouncements.isEmpty {
            announcement = nil
        } else {
            announcement = pendingAnnouncements.removeFirst()
        }
    }

    private func handle(_ event: RuntimeEvent) {
        switch event.event {
        case .booting:
            mode = .launching
            status = event.message ?? "Booting Android…"
        case .emulatorStarted:
            emulatorPID = event.pid
        case .deviceReady:
            mode = .deviceRunning
            status = LauncherL10n.text("android_running.title")
            detail = LauncherL10n.text("android_running.description")
        case .ready:
            mode = .playing
            gameSessionTracker.start()
            if activeRuntimeKind == .nativeIPadExperimental {
                status = LauncherL10n.text("native_ipad.running.title")
                detail = LauncherL10n.text("native_ipad.running.description")
            } else {
                let activePackage = event.package ?? gameRelease.packageName
                status = "TFT is open"
                detail = "Space — shop  •  D — reroll  •  F — XP  •  Tab — items/traits  •  V — players/damage  •  Control + Fn + F — fill window."
                loginAnimationRepair.start(
                    adb: paths.adb,
                    package: activePackage,
                    log: paths.launcherLog
                )
                if let emulatorPID {
                    let profile = launchProfile ?? selectedProfile
                    fpsOverlay.start(
                        targetPID: emulatorPID,
                        adb: paths.adb,
                        package: activePackage
                    )
                    inputBridge.start(
                        targetPID: emulatorPID,
                        adb: paths.adb,
                        width: profile.width,
                        height: profile.height
                    )
                }
            }
        case .error:
            guard !stopRequested || activeRuntimeKind == .nativeIPadExperimental else { return }
            let errorMessage = activeRuntimeKind == .nativeIPadExperimental
                ? NativeIPadDiagnostics.displayMessage(event.message ?? "Runtime error")
                : event.message ?? "Runtime error"
            runtimeHadError = true
            loginAnimationRepair.stop()
            audioRecovery.stop()
            fpsOverlay.stop()
            inputBridge.stop()
            finishGameSession(showAnnouncement: false)
            if activeRuntimeKind == .nativeIPadExperimental {
                recordNativeError(errorMessage)
            }
            activeRuntimeKind = nil
            fail(errorMessage, origin: .runtime)
        case .gameStopped:
            finishGameSession(showAnnouncement: activeRuntimeKind == .androidEmulator)
            loginAnimationRepair.stop()
            audioRecovery.stop()
            fpsOverlay.stop()
            inputBridge.stop()
            mode = .deviceRunning
            status = LauncherL10n.text("android_running.title")
            detail = LauncherL10n.text("android_running.description")
        case .stopped:
            let stoppedRuntime = activeRuntimeKind
            loginAnimationRepair.stop()
            audioRecovery.stop()
            fpsOverlay.stop()
            inputBridge.stop()
            finishGameSession(showAnnouncement: stoppedRuntime == .androidEmulator)
            emulatorPID = nil
            if stopRequested || !runtimeHadError {
                mode = .ready
                activeConfiguration = nil
                launchProfile = nil
                launchEffectsQuality = nil
                if stoppedRuntime == .nativeIPadExperimental {
                    status = LauncherL10n.text("native_ipad.closed.title")
                    detail = LauncherL10n.text("native_ipad.closed.description")
                } else {
                    status = "Emulator closed"
                    detail = "Temporary overlays and settings were restored."
                }
            }
            activeRuntimeKind = nil
            stopRequested = false
            runtimeHadError = false
        case .downloading, .installingGame:
            break
        }
    }

    private func updateHotkeyActivity(eventTapActive: Bool, eventTapAttemptFailed: Bool) {
        hotkeyEventTapActive = eventTapActive
        hotkeyEventTapAttemptFailed = eventTapAttemptFailed
        refreshHotkeyStatus()
    }

    private func validateAndPersistNativeApplication(at url: URL) {
        let currentURL = nativeIPadDescriptor?.canonicalURL
        do {
            let descriptor = try nativeValidator.validate(url)
            let validatedAt = Date()
            try nativeStateStore.save(descriptor: descriptor, validatedAt: validatedAt)
            nativeIPadDescriptor = descriptor
            nativeIPadLastValidatedAt = validatedAt
            nativeIPadValidationError = nil
            nativeIPadHasSavedState = true
            failure = nil
            mode = .ready
            status = LauncherL10n.text("native_ipad.ready.title")
            detail = LauncherL10n.text("native_ipad.ready.description")
        } catch {
            let message = NativeIPadDiagnostics.displayMessage(error.localizedDescription)
            nativeIPadValidationError = message
            if url.standardizedFileURL.resolvingSymlinksInPath() == currentURL {
                recordNativeError(message)
            }
            fail(message, origin: .validation)
        }
    }

    private func recordNativeError(_ message: String) {
        let sanitized = NativeIPadDiagnostics.displayMessage(message)
        nativeIPadValidationError = sanitized
        guard let descriptor = nativeIPadDescriptor else { return }
        try? nativeStateStore.save(
            descriptor: descriptor,
            lastError: sanitized,
            validatedAt: nativeIPadLastValidatedAt ?? Date.distantPast
        )
    }

    private func applySelectedRuntimePresentation() {
        activeRuntimeKind = nil
        progress = 0
        installationWasCancelled = false
        switch selectedRuntimeKind {
        case .androidEmulator:
            if Self.installationLooksReady(
                state: installState,
                paths: paths,
                gameRelease: gameRelease
            ) {
                mode = .ready
                status = "Ready to play"
                detail = "Choose graphics and language, then press Play."
            } else {
                mode = .needsInstall
                status = "Initial installation required"
                detail = "Android components will be downloaded directly from dl.google.com."
            }
        case .nativeIPadExperimental:
            if nativeIPadDescriptor != nil {
                mode = .ready
                status = LauncherL10n.text("native_ipad.ready.title")
                detail = LauncherL10n.text("native_ipad.ready.description")
            } else {
                mode = .needsInstall
                status = LauncherL10n.text("native_ipad.not_selected.title")
                detail = nativeIPadValidationError
                    ?? LauncherL10n.text("native_ipad.not_selected.description")
            }
        }
    }

    private func finishGameSession(showAnnouncement: Bool) {
        let endedAt = Date()
        guard let duration = gameSessionTracker.finish(at: endedAt) else { return }
        guard activeRuntimeKind == .androidEmulator else { return }
        let profile = launchProfile ?? selectedProfile
        let effectsQuality = launchEffectsQuality ?? selectedEffectsQuality
        telemetry.recordGameSession(
            durationSeconds: duration,
            launcherSettings: LauncherTelemetrySettings(
                profile: profile,
                effectsQuality: effectsQuality,
                uiScalePercent: selectedUIScalePercent,
                androidMemoryMB: selectedMemoryMB,
                androidCPUCores: selectedCPUCores
            ),
            endedAt: endedAt
        )
        if showAnnouncement {
            requestAnnouncement(for: .gameClosed)
        }
    }

    private func requestAnnouncement(for trigger: LauncherMessageTrigger) {
        telemetry.fetchAnnouncement(trigger: trigger) { [weak self] message in
            guard let self, let message else { return }
            if announcement == nil {
                announcement = message
            } else if pendingAnnouncements.count < 4 {
                pendingAnnouncements.append(message)
            }
        }
    }

    private func fail(_ message: String, origin: LauncherFailureOrigin) {
        mode = .failed
        status = "Unable to continue"
        detail = message
        failure = LauncherFailure(origin: origin, technicalDetails: message)
    }

    private func failureOrigin(for error: Error, fallback: LauncherFailureOrigin) -> LauncherFailureOrigin {
        guard let launcherError = error as? LauncherError else { return fallback }
        switch launcherError {
        case .invalidManifest, .integrity, .unsupportedGame:
            return .validation
        case .preflight, .process:
            return fallback
        case .cancelled:
            return .installation
        }
    }

    private static func installationLooksReady(
        state: InstallState,
        paths: LauncherPaths,
        gameRelease: GameRelease
    ) -> Bool {
        state.isReady
            && (state.gamePackageName.map { $0 == gameRelease.packageName } ?? true)
            && state.gameVersion == gameRelease.version
            && state.gameBaseSHA256 == gameRelease.baseSHA256
            && state.overlaySHA256 != nil
            && FileManager.default.isExecutableFile(atPath: paths.adb.path)
            && FileManager.default.isExecutableFile(atPath: paths.emulator.path)
            && FileManager.default.fileExists(atPath: paths.avdINI.path)
            && FileManager.default.fileExists(atPath: paths.overlayAPK.path)
    }
}
