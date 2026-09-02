import Foundation

enum MacticianIdentity {
    static let appName = "Mactician"
    static let bundleIdentifier = "dev.sergeinaumov.mactician"
    static let applicationSupportDirectory = "Mactician"
    static let userDefaultsDomain = bundleIdentifier
    static let keychainService = bundleIdentifier
    static let loggingSubsystem = bundleIdentifier
    static let websiteURL = URL(string: "https://sergeinaumov.dev/mactician")!
    static let privacyPolicyURL = URL(string: "https://sergeinaumov.dev/mactician/privacy")!
    static let extendedDiagnosticsURL = URL(
        string: "https://sergeinaumov.dev/mactician/privacy#extended-diagnostics"
    )!
    static let sourceURL = URL(string: "https://github.com/tweet9ra/mactician")!
    static let technicalStoryURL = URL(
        string: "https://sergeinaumov.dev/writing/how-i-built-mactician"
    )!
    static let issueURL = URL(string: "https://github.com/tweet9ra/mactician/issues/new/choose")!
    static let gameUpdateURL = URL(
        string: "https://sergeinaumov.dev/mactician/updates/game/manifest.json"
    )!
    static let gameUpdatePublicKeyBase64 = "Nadxne/Zs1kndXT8OpaShZCEgK/LqUtMv4aqGQNzCcM="
}

struct ReleaseManifest: Codable, Equatable {
    let schemaVersion: Int
    let minimumFreeBytes: Int64
    let components: [SDKComponent]
    let game: GameRelease
    let profiles: [LaunchProfile]

    func validate() throws {
        guard schemaVersion == 1 else {
            throw LauncherError.invalidManifest("Unsupported release manifest schema: \(schemaVersion)")
        }
        guard minimumFreeBytes >= 10 * 1024 * 1024 * 1024 else {
            throw LauncherError.invalidManifest("Invalid minimum disk space")
        }
        guard Set(components.map(\.id)).count == components.count,
              Set(profiles.map(\.id)).count == profiles.count else {
            throw LauncherError.invalidManifest("Duplicate identifiers")
        }
        for component in components {
            try component.validate()
        }
        try game.validate()
        guard Set(profiles.map(\.id)) == Set(["balanced", "quality", "ultra", "4k"]) else {
            throw LauncherError.invalidManifest("Required profiles are missing")
        }
        for profile in profiles {
            try profile.validate()
        }
    }
}

struct SDKComponent: Codable, Equatable, Identifiable {
    let id: String
    let version: String
    let url: URL
    let size: Int64
    let sha256: String
    let archiveRoot: String
    let installPath: String

    func validate() throws {
        guard url.scheme == "https", url.host == "dl.google.com" else {
            throw LauncherError.invalidManifest("Component \(id) uses an unofficial URL")
        }
        guard size > 0, sha256.isLowercaseSHA256 else {
            throw LauncherError.invalidManifest("Component \(id) has an invalid size or hash")
        }
        guard Self.isSafeRelativePath(archiveRoot), Self.isSafeRelativePath(installPath) else {
            throw LauncherError.invalidManifest("Component \(id) contains an unsafe path")
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

struct GameRelease: Codable, Equatable {
    static let globalPackageName = "com.riotgames.league.teamfighttactics"
    static let vietnamPackageName = "com.riotgames.league.teamfighttacticsvn"
    static let supportedPackageNames = Set([globalPackageName, vietnamPackageName])

    let packageName: String
    let version: String
    let versionCode: Int?
    let baseSHA256: String
    let apks: [GameAPK]

    func validate() throws {
        guard Self.supportedPackageNames.contains(packageName),
              !version.isEmpty,
              baseSHA256.isLowercaseSHA256,
              (1 ... 32).contains(apks.count),
              Set(apks.map(\.name)).count == apks.count,
              apks.first?.name == "base.apk",
              apks.first?.sha256 == baseSHA256 else {
            throw LauncherError.invalidManifest("Invalid TFT release")
        }
        for apk in apks {
            guard !apk.name.contains("/"), apk.name.hasSuffix(".apk"),
                  apk.size > 0, apk.sha256.isLowercaseSHA256 else {
                throw LauncherError.invalidManifest("Invalid APK description for \(apk.name)")
            }
        }
    }
}

struct GameAPK: Codable, Equatable {
    let name: String
    let size: Int64
    let sha256: String
    let url: URL?
}

struct LaunchProfile: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let width: Int
    let height: Int
    let density: Int
    let memoryMB: Int

    var displaySize: String { "\(width)x\(height)" }
    var displayResolution: String { LauncherMetadata.resolution(width: width, height: height) }

    func validate() throws {
        guard ["balanced", "quality", "ultra", "4k"].contains(id),
              width >= 1280, height >= 720,
              (120 ... 640).contains(density),
              memoryMB == 6144 else {
            throw LauncherError.invalidManifest("Invalid profile \(id)")
        }
    }
}

enum EffectsQuality: String, CaseIterable, Identifiable {
    case high
    case performance
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high:
            return LauncherL10n.text("effects_quality.high")
        case .performance:
            return LauncherL10n.text("effects_quality.performance")
        case .maximum:
            return LauncherL10n.text("effects_quality.maximum")
        }
    }

    var detail: String {
        switch self {
        case .high:
            return LauncherL10n.text("effects_quality.high.detail")
        case .performance:
            return LauncherL10n.text("effects_quality.performance.detail")
        case .maximum:
            return LauncherL10n.text("effects_quality.maximum.detail")
        }
    }

    var profileFilename: String {
        switch self {
        case .high, .performance:
            return "Android_Codex.DeviceProfiles.effects-\(rawValue).ini"
        case .maximum:
            return "Android_Codex.DeviceProfiles.performance-max.ini"
        }
    }

    static func selection(saved: String?) -> EffectsQuality {
        EffectsQuality(rawValue: saved ?? "") ?? .high
    }
}

struct GameLanguage: Equatable, Identifiable {
    let id: String
    let title: String

    static let supported: [GameLanguage] = [
        .init(id: "en-US", title: "English"),
        .init(id: "ru-RU", title: "Russian"),
        .init(id: "de-DE", title: "German"),
        .init(id: "fr-FR", title: "French"),
        .init(id: "es-ES", title: "Spanish (Spain)"),
        .init(id: "es-MX", title: "Spanish (Latin America)"),
        .init(id: "pt-BR", title: "Portuguese (Brazil)"),
        .init(id: "it-IT", title: "Italian"),
        .init(id: "pl-PL", title: "Polish"),
        .init(id: "cs-CZ", title: "Czech"),
        .init(id: "hu-HU", title: "Hungarian"),
        .init(id: "ro-RO", title: "Romanian"),
        .init(id: "el-GR", title: "Greek"),
        .init(id: "tr-TR", title: "Turkish"),
        .init(id: "ar-AE", title: "Arabic"),
        .init(id: "ja-JP", title: "Japanese"),
        .init(id: "ko-KR", title: "Korean"),
        .init(id: "zh-CN", title: "Chinese (Simplified)"),
        .init(id: "zh-SG", title: "Chinese (Singapore)"),
        .init(id: "zh-TW", title: "Chinese (Traditional)"),
        .init(id: "vi-VN", title: "Vietnamese"),
        .init(id: "th-TH", title: "Thai"),
        .init(id: "id-ID", title: "Indonesian")
    ]

    static let english = supported[0]

    static func language(withID id: String?) -> GameLanguage {
        supported.first(where: { $0.id == id }) ?? english
    }
}

struct InstallState: Codable, Equatable {
    enum Stage: String, Codable {
        case empty
        case downloading
        case sdkInstalled = "sdk_installed"
        case avdCreated = "avd_created"
        case ready
    }

    var schemaVersion: Int = 1
    var stage: Stage = .empty
    var installedComponents: [String: String] = [:]
    var gamePackageName: String?
    var gameVersion: String?
    var gameVersionCode: Int?
    var gameBaseSHA256: String?
    var overlaySHA256: String?
    var updatedAt: Date = Date()

    var isReady: Bool { schemaVersion == 1 && stage == .ready }
}

struct RuntimeEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case downloading
        case booting
        case installingGame = "installing_game"
        case emulatorStarted = "emulator_started"
        case deviceReady = "device_ready"
        case ready
        case gameStopped = "game_stopped"
        case stopped
        case error
    }

    let event: Kind
    var message: String?
    var pid: Int32?
    var serial: String?
    var package: String?
    var code: Int32?
}

enum LauncherError: LocalizedError, Equatable {
    case invalidManifest(String)
    case preflight(String)
    case integrity(String)
    case process(String)
    case unsupportedGame(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .invalidManifest(message), let .preflight(message),
             let .integrity(message), let .process(message),
             let .unsupportedGame(message):
            return message
        case .cancelled:
            return "Operation cancelled"
        }
    }
}

enum HostSizing {
    static func guestCPUCores(logicalCPUCount: Int) -> Int {
        min(6, max(4, logicalCPUCount - 2))
    }

    static func guestCPUList(logicalCPUCount: Int) -> String {
        "0-\(guestCPUCores(logicalCPUCount: logicalCPUCount) - 1)"
    }

    static func guestCPUMask(logicalCPUCount: Int) -> String {
        let cores = guestCPUCores(logicalCPUCount: logicalCPUCount)
        return String((1 << cores) - 1, radix: 16)
    }
}

enum GuestResourceOptions {
    static let defaultMemoryMB = 6144

    static func memoryMB(physicalMemoryBytes: UInt64) -> [Int] {
        let hostMemoryMB = Int(physicalMemoryBytes / 1_048_576)
        let maximum = min(16_384, max(4_096, hostMemoryMB - 4_096))
        return Array(stride(from: 4_096, through: maximum, by: 2_048))
    }

    static func installationMemoryMB(physicalMemoryBytes: UInt64) -> Int {
        selection(
            saved: defaultMemoryMB,
            options: memoryMB(physicalMemoryBytes: physicalMemoryBytes),
            fallback: defaultMemoryMB
        )
    }

    static func cpuCores(logicalCPUCount: Int) -> [Int] {
        let maximum = min(16, max(1, logicalCPUCount))
        if maximum == 1 { return [1] }
        return Array(2 ... maximum)
    }

    static func selection(saved: Int, options: [Int], fallback: Int) -> Int {
        if options.contains(saved) { return saved }
        if options.contains(fallback) { return fallback }
        return options.last ?? fallback
    }

    static func recommended(
        physicalMemoryBytes: UInt64,
        logicalCPUCount: Int
    ) -> GuestResourceConfiguration {
        let memoryOptions = memoryMB(physicalMemoryBytes: physicalMemoryBytes)
        let hostMemoryGB = Int(physicalMemoryBytes / 1_073_741_824)
        let targetMemoryMB = hostMemoryGB >= 24 ? 8192 : 6144
        let recommendedMemoryMB = selection(
            saved: targetMemoryMB,
            options: memoryOptions,
            fallback: defaultMemoryMB
        )

        let cpuOptions = cpuCores(logicalCPUCount: logicalCPUCount)
        let targetCPUCores: Int
        if logicalCPUCount >= 12 {
            targetCPUCores = 8
        } else if logicalCPUCount >= 8 {
            targetCPUCores = 6
        } else {
            targetCPUCores = max(2, logicalCPUCount - 2)
        }
        let recommendedCPUCores = selection(
            saved: targetCPUCores,
            options: cpuOptions,
            fallback: HostSizing.guestCPUCores(logicalCPUCount: logicalCPUCount)
        )
        return GuestResourceConfiguration(
            memoryMB: recommendedMemoryMB,
            cpuCores: recommendedCPUCores
        )
    }
}

struct GuestResourceConfiguration: Equatable {
    let memoryMB: Int
    let cpuCores: Int
}

enum InterfaceScaleOptions {
    static let defaultPercent = 100
    static let percentages = [100, 125, 150, 175, 200]

    static func selection(saved: Int) -> Int {
        percentages.contains(saved) ? saved : defaultPercent
    }

    static func runtimeValue(percent: Int) -> String? {
        switch percent {
        case 100: "1.0"
        case 125: "1.25"
        case 150: "1.5"
        case 175: "1.75"
        case 200: "2.0"
        default: nil
        }
    }
}

extension String {
    fileprivate var isLowercaseSHA256: Bool {
        count == 64 && allSatisfy { ("0" ... "9").contains(String($0)) || ("a" ... "f").contains(String($0)) }
    }
}
