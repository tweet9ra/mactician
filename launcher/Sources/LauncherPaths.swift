import Foundation

struct LauncherPaths {
    let root: URL
    let bundleResources: URL

    init(root: URL? = nil, bundle: Bundle = .main, resources: URL? = nil) throws {
        let fileManager = FileManager.default
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["MACTICIAN_DATA_ROOT"],
                  !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.root = Self.defaultRoot(applicationSupport: applicationSupport)
        }
        guard let resources = resources ?? bundle.resourceURL else {
            throw LauncherError.process("The application Resources directory is missing")
        }
        bundleResources = resources
    }

    static func defaultRoot(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(
            MacticianIdentity.applicationSupportDirectory,
            isDirectory: true
        )
    }

    var sdk: URL { root.appendingPathComponent("sdk", isDirectory: true) }
    var emulator: URL { sdk.appendingPathComponent("emulator/emulator") }
    var qemuSystem: URL { sdk.appendingPathComponent("emulator/qemu/darwin-aarch64/qemu-system-aarch64") }
    var qemuImg: URL { sdk.appendingPathComponent("emulator/qemu-img") }
    var adb: URL { sdk.appendingPathComponent("platform-tools/adb") }
    var systemImage: URL {
        sdk.appendingPathComponent(
            "system-images/android-36/google_apis_playstore/arm64-v8a",
            isDirectory: true
        )
    }
    var avdHome: URL { root.appendingPathComponent("avd", isDirectory: true) }
    var avdDirectory: URL { avdHome.appendingPathComponent("TftPlay.avd", isDirectory: true) }
    var avdINI: URL { avdHome.appendingPathComponent("TftPlay.ini") }
    var avdBootCompleted: URL { avdDirectory.appendingPathComponent("bootcompleted.ini") }
    var runtimeProject: URL { root.appendingPathComponent("runtime-project", isDirectory: true) }
    var downloads: URL { root.appendingPathComponent("downloads", isDirectory: true) }
    var gameCache: URL { root.appendingPathComponent("game", isDirectory: true) }
    var hostedGameFeed: URL { gameCache.appendingPathComponent("manifest.json") }
    func gameReleaseDirectory(baseSHA256: String) -> URL {
        gameCache.appendingPathComponent("releases/\(baseSHA256)", isDirectory: true)
    }
    func gameResources(for release: GameRelease) -> URL {
        let hosted = gameReleaseDirectory(baseSHA256: release.baseSHA256)
        if FileManager.default.fileExists(atPath: hosted.appendingPathComponent("base.apk").path) {
            return hosted
        }
        return gameResources
    }
    var staging: URL { root.appendingPathComponent(".staging", isDirectory: true) }
    var stateFile: URL { root.appendingPathComponent("install-state.json") }
    var nativeIPadDirectory: URL { root.appendingPathComponent("native-ipad", isDirectory: true) }
    var nativeIPadStateFile: URL { nativeIPadDirectory.appendingPathComponent("native-ipad-state.json") }
    var logDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }
    var launcherLog: URL { logDirectory.appendingPathComponent("launcher.log") }
    var gameResources: URL { bundleResources.appendingPathComponent("Game", isDirectory: true) }
    var runtimeTemplate: URL { bundleResources.appendingPathComponent("RuntimeTemplate", isDirectory: true) }
    var emulatorHostTemplate: URL {
        bundleResources.deletingLastPathComponent().appendingPathComponent(
            "Helpers/Mactician Game Host.app",
            isDirectory: true
        )
    }
    var manifest: URL { bundleResources.appendingPathComponent("release-manifest.json") }
    var shaderProfile: URL {
        runtimeProject.appendingPathComponent("artifacts/tft-18.1-angle-opengl/Android_Codex.DeviceProfiles.shader-prewarm.ini")
    }
    var performanceMaxProfile: URL {
        runtimeProject.appendingPathComponent("artifacts/tft-18.1-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini")
    }
    func effectsProfile(for quality: EffectsQuality) -> URL {
        runtimeProject.appendingPathComponent(
            "artifacts/tft-18.1-angle-opengl/\(quality.profileFilename)"
        )
    }
    var overlayAPK: URL {
        runtimeProject.appendingPathComponent("artifacts/tft-18.1-angle-opengl/base-angle-opengl.apk")
    }
    var runtimeHelper: URL { bundleResources.appendingPathComponent("launcher-runtime.command") }
    var qemuHypervisorEntitlements: URL {
        bundleResources.appendingPathComponent("QEMU-Hypervisor.entitlements")
    }
}
