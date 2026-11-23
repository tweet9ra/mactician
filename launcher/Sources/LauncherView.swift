import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var updateController: LauncherUpdateController
    let openLauncher: () -> LauncherModel
    @State private var model: LauncherModel?

    private let heroImage = Bundle.main.url(forResource: "MacticianHero", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
                        if let model {
                            LauncherGameControls(model: model, updateController: updateController)
                                .padding(.top, LauncherTheme.Spacing.large)
                        } else {
                            hero(compact: geometry.size.height < 720)
                            farewellNote
                        }
                    }
                    .padding(.horizontal, LauncherTheme.Metric.stateDeckInset)
                    .padding(.bottom, LauncherTheme.Spacing.large)
                    .frame(maxWidth: LauncherTheme.Metric.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                footer
            }
            .background(LauncherTheme.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: LauncherTheme.Metric.surfaceRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.surfaceRadius)
                    .strokeBorder(LauncherTheme.ColorToken.neutralBorder)
            }
            .padding(LauncherTheme.Metric.outerInset)
        }
        .background(LauncherTheme.ColorToken.window.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: LauncherTheme.Spacing.medium) {
            LauncherBrandMark()
            VStack(alignment: .leading, spacing: 3) {
                Text("Mactician")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                Text(LauncherL10n.text("header.subtitle"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }

            LauncherDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

            if model != nil {
                Button {
                    model = nil
                } label: {
                    Label(LauncherL10n.text("farewell.return"), systemImage: "chevron.left")
                }
                .buttonStyle(.link)
            } else {
                Button {
                    model = openLauncher()
                } label: {
                    HStack(spacing: LauncherTheme.Spacing.small) {
                        Text(LauncherL10n.text("farewell.continue"))
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(LauncherSecondaryButtonStyle())
            }

            Text(LauncherBuildInfo.display)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
        }
        .padding(.horizontal, LauncherTheme.Metric.trafficLightReserve)
        .frame(height: 64)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .bottom) { LauncherDivider() }
    }

    private func hero(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.regular) {
            Text(LauncherL10n.text("farewell.title"))
                .font(.system(size: compact ? 46 : 56, weight: .bold, design: .serif))
                .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(LauncherL10n.text("farewell.riot"))
                .font(.system(size: 17))
                .lineSpacing(3)
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                .frame(maxWidth: 470, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: LauncherTheme.Spacing.large) {
                Link(destination: MacticianIdentity.riotDownloadURL) {
                    Label(LauncherL10n.text("farewell.download"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(LauncherPrimaryButtonStyle())

                Link(destination: MacticianIdentity.riotMacNewsURL) {
                    HStack(spacing: 5) {
                        Text(LauncherL10n.text("farewell.news"))
                        Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(.link)
                .foregroundColor(LauncherTheme.ColorToken.textPrimary)
            }
            .padding(.top, LauncherTheme.Spacing.small)
        }
        .padding(.horizontal, LauncherTheme.Metric.stateDeckPadding)
        .padding(.vertical, LauncherTheme.Spacing.large)
        .frame(maxWidth: .infinity, minHeight: compact ? 245 : 300, alignment: .leading)
        .background {
            if let heroImage {
                GeometryReader { geometry in
                    Image(nsImage: heroImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width * 0.55, height: geometry.size.height)
                        .clipped()
                        .mask(LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.36)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LauncherTheme.Metric.surfaceRadius))
    }

    private var farewellNote: some View {
        HStack(spacing: LauncherTheme.Spacing.xLarge) {
            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.medium) {
                Text(LauncherL10n.text("farewell.thanks"))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(LauncherL10n.text("farewell.message"))
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: LauncherTheme.Spacing.regular) {
                    Text(LauncherL10n.text("farewell.author"))
                        .font(.system(size: 15, weight: .medium, design: .serif).italic())
                        .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                    Link(destination: MacticianIdentity.contactURL) {
                        Label(MacticianIdentity.contactEmail, systemImage: "envelope")
                    }
                    .buttonStyle(.link)
                }
                .padding(.top, LauncherTheme.Spacing.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.regular) {
                Text(LauncherL10n.text("farewell.donation"))
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: MacticianIdentity.donateURL) {
                    Label(LauncherL10n.text("farewell.donate"), systemImage: "heart")
                }
                .buttonStyle(LauncherActionButtonStyle(kind: .support))
            }
            .frame(width: 248, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, LauncherTheme.Metric.stateDeckPadding)
        .padding(.vertical, LauncherTheme.Spacing.large)
        .launcherSurface()
    }

    private var footer: some View {
        HStack(spacing: LauncherTheme.Spacing.small) {
            Label(LauncherL10n.text("footer.private_build"), systemImage: "lock.fill")
            Text("\u{00b7}")
            Text(LauncherL10n.text("footer.apple_silicon"))
            Text("\u{00b7}")
            Link(destination: MacticianIdentity.websiteURL) {
                Label(LauncherL10n.text("footer.developer_website"), systemImage: "link")
                    .foregroundColor(LauncherTheme.ColorToken.interactive)
            }
            .buttonStyle(.plain)
            .help(LauncherL10n.text("footer.developer_website"))
            Spacer()
            Text(LauncherL10n.text("footer.legal"))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(LauncherTheme.ColorToken.textSecondary)
        .padding(.horizontal, LauncherTheme.Metric.stateDeckInset + 12)
        .frame(height: 44)
    }
}

private struct LauncherGameControls: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var updateController: LauncherUpdateController
    @State private var showSettings = false
    @State private var showResetConfirmation = false

    var body: some View {
        LauncherStateDeck(model: model, showSettings: $showSettings)
            .sheet(isPresented: Binding(
                get: {
                    model.shouldShowTelemetryNotice && !model.isNativeIPadRuntimeSelected
                },
                set: { isPresented in
                    if !isPresented && !model.isNativeIPadRuntimeSelected {
                        model.shouldShowTelemetryNotice = false
                    }
                }
            )) {
                LauncherTelemetryNoticeView(model: model)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showSettings) {
                LauncherSettingsView(
                    model: model,
                    updateController: updateController,
                    showResetConfirmation: $showResetConfirmation
                )
            }
            .sheet(item: $model.announcement) { announcement in
                LauncherAnnouncementView(
                    announcement: announcement,
                    dismiss: model.dismissAnnouncement
                )
                .interactiveDismissDisabled()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.refreshHotkeyStatus()
            }
    }
}
