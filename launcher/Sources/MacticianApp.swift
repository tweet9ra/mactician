import AppKit
import SwiftUI

@main
struct MacticianApp: App {
    @NSApplicationDelegateAdaptor(LauncherAppDelegate.self) private var appDelegate
    @StateObject private var updateController = LauncherUpdateController()
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup("Mactician") {
            LauncherView(updateController: updateController, openLauncher: appDelegate.openLauncher)
                .frame(minWidth: 1080, minHeight: 660)
                .sheet(isPresented: $showAbout) {
                    MacticianAboutView()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About Mactician") {
                    showAbout = true
                }
            }
            CommandGroup(after: .appInfo) {
                Button(LauncherL10n.text("updates.check")) {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
            }
        }
    }
}

struct MacticianAboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    }

    var body: some View {
        VStack(spacing: LauncherTheme.Spacing.regular) {
            MacticianMark()
                .frame(width: 88, height: 88)
                .accessibilityLabel("Mactician")
            VStack(spacing: LauncherTheme.Spacing.xSmall) {
                Text("Mactician")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(LauncherL10n.text("about.descriptor"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                Text("Version \(version) (\(build))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(LauncherTheme.ColorToken.textTertiary)
            }
            VStack(spacing: LauncherTheme.Spacing.xSmall) {
                Text("Free and open source.")
                Text("Built for two tacticians. Shared with everyone.")
            }
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            HStack(spacing: LauncherTheme.Spacing.regular) {
                aboutLink("Website", destination: MacticianIdentity.websiteURL)
                aboutLink("GitHub", destination: MacticianIdentity.sourceURL)
                aboutLink("Technical story", destination: MacticianIdentity.technicalStoryURL)
                aboutLink("Report an issue", destination: MacticianIdentity.contactURL)
            }
        }
        .foregroundColor(LauncherTheme.ColorToken.textPrimary)
        .padding(LauncherTheme.Spacing.xLarge)
        .frame(width: 560, height: 360)
        .background(LauncherTheme.ColorToken.surface)
        .preferredColorScheme(.dark)
    }

    private func aboutLink(_ title: String, destination: URL) -> some View {
        Link(title, destination: destination)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(LauncherTheme.ColorToken.interactive)
    }
}

@MainActor
final class LauncherAppDelegate: NSObject, NSApplicationDelegate {
    private var model: LauncherModel?

    func openLauncher() -> LauncherModel {
        if let model { return model }
        let launcher = LauncherModel()
        model = launcher
        return launcher
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.shutdown()
        return .terminateNow
    }
}
