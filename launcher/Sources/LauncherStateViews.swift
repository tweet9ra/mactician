import AppKit
import SwiftUI

struct LauncherStateDeck: View {
    @ObservedObject var model: LauncherModel
    @Binding var showSettings: Bool

    var body: some View {
        Group {
            switch model.mode {
            case .needsInstall:
                if model.isNativeIPadRuntimeSelected {
                    LauncherNativeIPadRequiredView(model: model)
                } else {
                    LauncherInstallRequiredView(model: model)
                }
            case .installing:
                LauncherInstallingView(model: model)
            case .ready:
                if model.isNativeIPadRuntimeSelected {
                    LauncherNativeIPadReadyView(model: model)
                } else {
                    LauncherReadyView(model: model, showSettings: $showSettings)
                }
            case .launching:
                LauncherLaunchingView(model: model)
            case .playing:
                LauncherPlayingView(model: model)
            case .deviceRunning:
                LauncherAndroidRunningView(model: model)
            case .stopping:
                LauncherStoppingView(model: model)
            case .failed:
                LauncherFailureView(model: model)
            }
        }
        .padding(LauncherTheme.Metric.stateDeckPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .launcherSurface()
        .shadow(color: Color.black.opacity(0.34), radius: 18, y: 8)
    }
}

private struct LauncherNativeIPadRequiredView: View {
    @ObservedObject var model: LauncherModel
    @State private var showsForgetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            LauncherStatusHeader(
                symbol: "app.badge",
                color: LauncherTheme.ColorToken.warning,
                title: LauncherL10n.text("native_ipad.not_selected.title"),
                description: LauncherL10n.text("native_ipad.not_selected.description")
            )

            Text(LauncherL10n.text("native_ipad.disclaimer"))
                .font(.system(size: 12))
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.nativeIPadValidationError {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(LauncherTheme.ColorToken.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: LauncherTheme.Spacing.medium) {
                Button(LauncherL10n.text("native_ipad.choose")) {
                    model.chooseNativeIPadApplication()
                }
                .buttonStyle(LauncherPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

                Button(LauncherL10n.text("native_ipad.use_android")) {
                    model.selectRuntime(.androidEmulator)
                }
                .buttonStyle(LauncherSecondaryButtonStyle())
                if model.nativeIPadHasSavedState {
                    Button(LauncherL10n.text("native_ipad.forget")) {
                        showsForgetConfirmation = true
                    }
                    .buttonStyle(LauncherTertiaryButtonStyle(tint: LauncherTheme.ColorToken.danger))
                }
                Spacer()
            }
        }
        .alert(
            LauncherL10n.text("native_ipad.forget.confirmation.title"),
            isPresented: $showsForgetConfirmation
        ) {
            Button(LauncherL10n.text("action.cancel"), role: .cancel) { }
            Button(LauncherL10n.text("native_ipad.forget"), role: .destructive) {
                model.forgetNativeIPadApplication()
            }
        } message: {
            Text(LauncherL10n.text("native_ipad.forget.confirmation.message"))
        }
    }
}

private struct LauncherNativeIPadReadyView: View {
    @ObservedObject var model: LauncherModel
    @State private var showsForgetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            HStack(alignment: .top, spacing: LauncherTheme.Spacing.large) {
                LauncherStatusHeader(
                    symbol: "checkmark",
                    color: LauncherTheme.ColorToken.success,
                    title: LauncherL10n.text("native_ipad.ready.title"),
                    description: LauncherL10n.text("native_ipad.ready.description")
                )
                Spacer()
                Button(LauncherL10n.text("action.play")) { model.play() }
                    .buttonStyle(LauncherPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.nativeIPadDescriptor == nil)
            }

            if let descriptor = model.nativeIPadDescriptor {
                HStack(spacing: LauncherTheme.Spacing.medium) {
                    nativeField(
                        LauncherL10n.text("native_ipad.application"),
                        descriptor.displayName
                    )
                    nativeField(
                        LauncherL10n.text("native_ipad.version"),
                        model.nativeIPadVersionSummary ?? LauncherL10n.text("native_ipad.version.unavailable")
                    )
                    nativeField(
                        LauncherL10n.text("native_ipad.signature"),
                        LauncherL10n.text("native_ipad.signature.\(descriptor.signatureKind.rawValue)")
                    )
                }

                VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
                    Text(descriptor.bundleIdentifier)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                        .textSelection(.enabled)
                    if let date = model.nativeIPadLastValidatedAt {
                        HStack(spacing: LauncherTheme.Spacing.xSmall) {
                            Text(LauncherL10n.text("native_ipad.last_validated"))
                            Text(date, style: .relative)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(LauncherTheme.ColorToken.textTertiary)
                    }
                    Text(LauncherL10n.text("native_ipad.external_updates"))
                        .font(.system(size: 11))
                        .foregroundColor(LauncherTheme.ColorToken.textTertiary)
                }
            }

            HStack(spacing: LauncherTheme.Spacing.medium) {
                Button(LauncherL10n.text("native_ipad.revalidate")) {
                    model.revalidateNativeIPadApplication()
                }
                .buttonStyle(LauncherSecondaryButtonStyle())
                Button(LauncherL10n.text("native_ipad.replace")) {
                    model.chooseNativeIPadApplication()
                }
                .buttonStyle(LauncherTertiaryButtonStyle())
                Button(LauncherL10n.text("native_ipad.forget")) {
                    showsForgetConfirmation = true
                }
                .buttonStyle(LauncherTertiaryButtonStyle(tint: LauncherTheme.ColorToken.danger))
                Spacer()
            }
        }
        .alert(
            LauncherL10n.text("native_ipad.forget.confirmation.title"),
            isPresented: $showsForgetConfirmation
        ) {
            Button(LauncherL10n.text("action.cancel"), role: .cancel) { }
            Button(LauncherL10n.text("native_ipad.forget"), role: .destructive) {
                model.forgetNativeIPadApplication()
            }
        } message: {
            Text(LauncherL10n.text("native_ipad.forget.confirmation.message"))
        }
    }

    private func nativeField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
            LauncherFieldLabel(text: label)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, LauncherTheme.Spacing.regular)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                .fill(LauncherTheme.ColorToken.raisedControl.opacity(0.72))
        )
    }
}

private struct LauncherInstallRequiredView: View {
    @ObservedObject var model: LauncherModel
    @State private var showsInstallDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            LauncherStatusHeader(
                symbol: model.installationWasCancelled ? "pause.circle.fill" : "arrow.down.circle.fill",
                color: model.installationWasCancelled
                    ? LauncherTheme.ColorToken.warning
                    : LauncherTheme.ColorToken.interactive,
                title: LauncherL10n.text(
                    model.installationWasCancelled ? "install.cancelled.title" : "install.required.title"
                ),
                description: LauncherL10n.text(
                    model.installationWasCancelled ? "install.cancelled.description" : "install.required.description"
                )
            )

            HStack(spacing: LauncherTheme.Spacing.medium) {
                requirement(
                    symbol: "arrow.down.circle",
                    value: model.downloadSize,
                    label: LauncherL10n.text("install.requirement.download")
                )
                requirement(
                    symbol: "externaldrive",
                    value: model.requiredFreeSpace,
                    label: LauncherL10n.text("install.requirement.free_space")
                )
                requirement(
                    symbol: "cpu",
                    value: LauncherL10n.text("install.requirement.apple_silicon_value"),
                    label: LauncherL10n.text("install.requirement.platform")
                )
            }

            DisclosureGroup(isExpanded: $showsInstallDetails) {
                HStack(spacing: LauncherTheme.Spacing.large) {
                    Label(model.androidSystemSummary, systemImage: "cpu")
                    Label(
                        LauncherL10n.format("install.emulator_format", model.emulatorVersion),
                        systemImage: "display"
                    )
                    Label(LauncherL10n.text("install.clean_profile"), systemImage: "lock.shield")
                }
                .font(.system(size: 12))
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                .padding(.top, LauncherTheme.Spacing.small)
            } label: {
                Text(LauncherL10n.text("install.what_is_installed"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
            }

            HStack(alignment: .center, spacing: LauncherTheme.Spacing.regular) {
                Toggle(
                    LauncherL10n.text("install.license.accept"),
                    isOn: $model.licenseAccepted
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 13))

                Link(
                    LauncherL10n.text("install.license.terms"),
                    destination: URL(string: "https://developer.android.com/studio/terms")!
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(LauncherTheme.ColorToken.interactive)

                Spacer()

                Button(LauncherL10n.text("action.install")) { model.install() }
                    .buttonStyle(LauncherPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.licenseAccepted)
                    .accessibilityHint(LauncherL10n.text("install.license.hint"))
            }
        }
    }

    private func requirement(symbol: String, value: String, label: String) -> some View {
        HStack(spacing: LauncherTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LauncherTheme.ColorToken.interactive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(LauncherTheme.ColorToken.textTertiary)
            }
        }
        .padding(.horizontal, LauncherTheme.Spacing.regular)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                .fill(LauncherTheme.ColorToken.raisedControl.opacity(0.72))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct LauncherInstallingView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            HStack(alignment: .top, spacing: LauncherTheme.Spacing.regular) {
                LauncherStatusHeader(
                    symbol: "arrow.down.circle.fill",
                    color: LauncherTheme.ColorToken.interactive,
                    title: LauncherL10n.text("installing.title"),
                    description: phaseTitle
                )
                Spacer()
                Text(model.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(LauncherTheme.ColorToken.interactive)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.small) {
                LauncherProgressBar(value: model.progress)
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }

            HStack(spacing: LauncherTheme.Spacing.medium) {
                Button(
                    LauncherL10n.text(model.isPaused ? "action.resume" : "action.pause")
                ) { model.togglePause() }
                    .buttonStyle(LauncherSecondaryButtonStyle())

                Button(LauncherL10n.text("action.cancel")) { model.cancelInstall() }
                    .buttonStyle(LauncherTertiaryButtonStyle(tint: LauncherTheme.ColorToken.danger))

                Spacer()

                Button(LauncherL10n.text("action.view_log")) { model.openLog() }
                    .buttonStyle(LauncherTertiaryButtonStyle())
            }
        }
    }

    private var phaseTitle: String {
        let key: String
        switch model.installerPhase {
        case .checking: key = "installing.phase.checking"
        case .downloading: key = "installing.phase.downloading"
        case .extracting: key = "installing.phase.extracting"
        case .creatingAVD: key = "installing.phase.creating_device"
        case .installingGame: key = "installing.phase.installing_game"
        case .finished: key = "installing.phase.finished"
        case .paused: key = "installing.phase.paused"
        }
        return LauncherL10n.text(key)
    }
}

private struct LauncherReadyView: View {
    @ObservedObject var model: LauncherModel
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            HStack(alignment: .top, spacing: LauncherTheme.Spacing.large) {
                LauncherStatusHeader(
                    symbol: "checkmark",
                    color: LauncherTheme.ColorToken.success,
                    title: LauncherL10n.text("ready.title"),
                    description: LauncherL10n.text("ready.description")
                )
                Spacer()
                if model.isGameUpdateAvailable {
                    Button(LauncherL10n.text("action.update_game")) { model.updateGame() }
                        .buttonStyle(LauncherPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(LauncherL10n.text("action.play")) { model.play() }
                        .buttonStyle(LauncherPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isCheckingGameUpdate)
                }
            }

            HStack(spacing: LauncherTheme.Spacing.medium) {
                languageField
                profileField
                advancedField
            }

            hotkeyRow
        }
        .onAppear {
            model.refreshHotkeyStatus()
            model.refreshGameUpdateAvailability()
        }
        .alert(
            LauncherL10n.text("game_update.result.title"),
            isPresented: Binding(
                get: { model.gameUpdateResultMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissGameUpdateResult()
                    }
                }
            )
        ) {
            Button(LauncherL10n.text("action.ok"), role: .cancel) {
                model.dismissGameUpdateResult()
            }
        } message: {
            Text(model.gameUpdateResultMessage ?? "")
        }
    }

    private var languageField: some View {
        LauncherSummaryField(
            label: LauncherL10n.text("field.game_language"),
            value: model.selectedLanguage.title
        ) {
            HStack(spacing: LauncherTheme.Spacing.medium) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.interactive)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
                    LauncherFieldLabel(text: LauncherL10n.text("field.game_language"))
                    LauncherMenuControl(
                        value: model.selectedLanguage.title,
                        showsBackground: false
                    ) {
                        ForEach(GameLanguage.supported) { language in
                            Button {
                                model.selectLanguage(language.id)
                            } label: {
                                if language.id == model.selectedLanguageID {
                                    Label(language.title, systemImage: "checkmark")
                                } else {
                                    Text(language.title)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LauncherTheme.Spacing.regular)
            .padding(.vertical, LauncherTheme.Spacing.small)
            .contentShape(Rectangle())
        }
    }

    private var profileField: some View {
        LauncherSummaryField(
            label: LauncherL10n.text("field.resolution"),
            value: model.selectedProfile.displayResolution
        ) {
            HStack(spacing: LauncherTheme.Spacing.medium) {
                Image(systemName: "display")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.interactive)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
                    LauncherFieldLabel(text: LauncherL10n.text("field.resolution"))
                    LauncherMenuControl(
                        value: model.selectedProfile.displayResolution,
                        showsBackground: false
                    ) {
                        ForEach(model.manifest.profiles) { profile in
                            let title = profile.displayResolution
                            Button {
                                model.selectProfile(profile.id)
                            } label: {
                                if profile.id == model.selectedProfileID {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LauncherTheme.Spacing.regular)
            .padding(.vertical, LauncherTheme.Spacing.small)
            .contentShape(Rectangle())
        }
    }

    private var advancedField: some View {
        LauncherSummaryField(
            label: LauncherL10n.text("field.advanced_settings"),
            value: model.selectedConfiguration.fullSummary
        ) {
            Button { showSettings = true } label: {
                summaryLabel(
                    label: LauncherL10n.text("field.advanced_settings"),
                    value: LauncherL10n.format(
                        "ready.advanced_summary_format",
                        model.selectedUIScalePercent,
                        model.selectedMemoryMB / 1024,
                        model.selectedCPUCores
                    ),
                    detail: LauncherL10n.text("ready.advanced_open"),
                    symbol: "slider.horizontal.3"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryLabel(
        label: String,
        value: String,
        detail: String?,
        symbol: String
    ) -> some View {
        HStack(spacing: LauncherTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LauncherTheme.ColorToken.interactive)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
                LauncherFieldLabel(text: label)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(LauncherTheme.ColorToken.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LauncherTheme.Spacing.small)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(LauncherTheme.ColorToken.interactive)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LauncherTheme.Spacing.regular)
        .padding(.vertical, LauncherTheme.Spacing.medium)
        .contentShape(Rectangle())
    }

    private var hotkeyRow: some View {
        HStack(spacing: LauncherTheme.Spacing.medium) {
            Image(systemName: hotkeySymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(hotkeyColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LauncherL10n.text("hotkeys.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                Text(hotkeyStatusText)
                    .font(.system(size: 11))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                Text(LauncherL10n.text("hotkeys.shortcuts"))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(LauncherTheme.ColorToken.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if needsPermissionAction {
                Button(LauncherL10n.text("hotkeys.grant_access")) { model.requestInputPermissions() }
                    .buttonStyle(LauncherTertiaryButtonStyle())
            }
        }
        .padding(.horizontal, LauncherTheme.Spacing.regular)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                .fill(
                    needsHotkeyAction
                        ? LauncherTheme.ColorToken.warning.opacity(0.09)
                        : Color.black.opacity(0.18)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                .stroke(
                    needsHotkeyAction
                        ? LauncherTheme.ColorToken.warning.opacity(0.36)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var needsHotkeyAction: Bool {
        model.hotkeyStatus == .permissionRequired
            || model.hotkeyStatus == .unavailable
    }

    private var needsPermissionAction: Bool {
        model.hotkeyStatus == .permissionRequired
    }

    private var hotkeyStatusText: String {
        LauncherL10n.text(model.hotkeyStatus.localizationKey)
    }

    private var hotkeyColor: Color {
        switch model.hotkeyStatus {
        case .ready, .active: return LauncherTheme.ColorToken.success
        case .permissionRequired, .unavailable: return LauncherTheme.ColorToken.warning
        }
    }

    private var hotkeySymbol: String {
        switch model.hotkeyStatus {
        case .ready, .active: return "checkmark.circle.fill"
        case .permissionRequired, .unavailable: return "exclamationmark.circle.fill"
        }
    }
}

private struct LauncherLaunchingView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            LauncherStatusHeader(
                symbol: "circle.dotted",
                color: LauncherTheme.ColorToken.interactive,
                title: LauncherL10n.text(
                    model.isNativeIPadRuntimeSelected
                        ? "native_ipad.launching.title"
                        : "launching.title"
                ),
                description: model.status,
                spinning: true
            )
            if model.isNativeIPadRuntimeSelected {
                if let descriptor = model.nativeIPadDescriptor {
                    Label(descriptor.displayName, systemImage: "app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                }
            } else {
                configurationSummary(model.activeConfiguration ?? model.selectedConfiguration)
            }
            HStack {
                Spacer()
                Button(LauncherL10n.text("action.view_log")) { model.openLog() }
                    .buttonStyle(LauncherTertiaryButtonStyle())
                Button(LauncherL10n.text("action.stop")) { model.stopGame() }
                    .buttonStyle(LauncherSecondaryButtonStyle())
            }
        }
    }
}

private struct LauncherPlayingView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        if model.isNativeIPadRuntimeSelected {
            nativePlayingView
        } else {
            androidPlayingView
        }
    }

    private var nativePlayingView: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            HStack(alignment: .top, spacing: LauncherTheme.Spacing.large) {
                LauncherStatusHeader(
                    symbol: "checkmark",
                    color: LauncherTheme.ColorToken.success,
                    title: LauncherL10n.text("native_ipad.running.title"),
                    description: LauncherL10n.text("native_ipad.running.description")
                )
                Spacer()
                Button(LauncherL10n.text("action.stop_game")) { model.stopGame() }
                    .buttonStyle(LauncherSecondaryButtonStyle())
            }
            if let descriptor = model.nativeIPadDescriptor {
                Label(
                    "\(descriptor.displayName) · \(descriptor.bundleIdentifier)",
                    systemImage: "app"
                )
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }
            Text(LauncherL10n.text("native_ipad.no_android_services"))
                .font(.system(size: 12))
                .foregroundColor(LauncherTheme.ColorToken.textTertiary)
        }
    }

    private var androidPlayingView: some View {
        let configuration = model.activeConfiguration ?? model.selectedConfiguration
        return VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            HStack(alignment: .top, spacing: LauncherTheme.Spacing.large) {
                LauncherStatusHeader(
                    symbol: "checkmark",
                    color: LauncherTheme.ColorToken.success,
                    title: LauncherL10n.text("playing.title"),
                    description: LauncherL10n.format(
                        "playing.description_format",
                        configuration.languageTitle
                    )
                )
                Spacer()
                Button(LauncherL10n.text("action.stop_emulator")) { model.stopGame() }
                    .buttonStyle(LauncherSecondaryButtonStyle())
            }
            configurationSummary(configuration, full: true)
            HStack(spacing: LauncherTheme.Spacing.medium) {
                Label(
                    LauncherL10n.text(model.hotkeyStatus.localizationKey),
                    systemImage: hotkeysNeedAttention ? "exclamationmark.triangle.fill" : "keyboard"
                )
                .foregroundColor(
                    hotkeysNeedAttention
                        ? LauncherTheme.ColorToken.warning
                        : LauncherTheme.ColorToken.textSecondary
                )
                Spacer()
                if model.hotkeyStatus == .permissionRequired {
                    Button(LauncherL10n.text("hotkeys.grant_access")) {
                        model.requestInputPermissions()
                    }
                    .buttonStyle(LauncherTertiaryButtonStyle())
                }
                Label(
                    LauncherL10n.text("playing.fill_window_tip"),
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, LauncherTheme.Spacing.regular)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                    .fill(Color.black.opacity(0.18))
            )
        }
    }

    private var hotkeysNeedAttention: Bool {
        model.hotkeyStatus == .permissionRequired || model.hotkeyStatus == .unavailable
    }
}

private struct LauncherAndroidRunningView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            HStack(alignment: .top, spacing: LauncherTheme.Spacing.large) {
                LauncherStatusHeader(
                    symbol: "display",
                    color: LauncherTheme.ColorToken.interactive,
                    title: LauncherL10n.text("android_running.title"),
                    description: LauncherL10n.text("android_running.description")
                )
                Spacer()
                Button(LauncherL10n.text("action.stop_emulator")) { model.stopGame() }
                    .buttonStyle(LauncherSecondaryButtonStyle())
            }

            Label(
                LauncherL10n.text("android_running.install_hint"),
                systemImage: "square.grid.2x2"
            )
            .font(.system(size: 12))
            .foregroundColor(LauncherTheme.ColorToken.textSecondary)
        }
    }
}

private struct LauncherStoppingView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            LauncherStatusHeader(
                symbol: "circle.dotted",
                color: LauncherTheme.ColorToken.warning,
                title: LauncherL10n.text(
                    model.isNativeIPadRuntimeSelected
                        ? "native_ipad.stopping.title"
                        : "stopping.title"
                ),
                description: LauncherL10n.text(
                    model.isNativeIPadRuntimeSelected
                        ? "native_ipad.stopping.description"
                        : "stopping.description"
                ),
                spinning: true
            )
            HStack {
                Spacer()
                Button(LauncherL10n.text("action.view_log")) { model.openLog() }
                    .buttonStyle(LauncherTertiaryButtonStyle())
            }
        }
    }
}

private struct LauncherFailureView: View {
    @ObservedObject var model: LauncherModel
    @State private var showsTechnicalDetails = false

    var body: some View {
        let failure = model.failure ?? LauncherFailure(origin: .runtime, technicalDetails: model.detail)
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.large) {
            LauncherStatusHeader(
                symbol: "exclamationmark.triangle.fill",
                color: failure.origin == .reset
                    ? LauncherTheme.ColorToken.danger
                    : LauncherTheme.ColorToken.warning,
                title: LauncherL10n.text(
                    model.isNativeIPadRuntimeSelected
                        ? "native_ipad.error.title"
                        : failure.titleLocalizationKey
                ),
                description: LauncherL10n.text(
                    model.isNativeIPadRuntimeSelected
                        ? "native_ipad.error.summary"
                        : failure.summaryLocalizationKey
                )
            )

            DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                VStack(alignment: .trailing, spacing: LauncherTheme.Spacing.small) {
                    ScrollView {
                        Text(failure.technicalDetails)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 92)

                    Button(LauncherL10n.text("action.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(failure.technicalDetails, forType: .string)
                    }
                    .buttonStyle(LauncherTertiaryButtonStyle())
                }
                .padding(.top, LauncherTheme.Spacing.small)
            } label: {
                Text(LauncherL10n.text("error.technical_details"))
                    .font(.system(size: 13, weight: .semibold))
            }

            HStack(spacing: LauncherTheme.Spacing.medium) {
                if failure.recoveryAction != .none {
                    Button(LauncherL10n.text(
                        model.isNativeIPadRuntimeSelected
                            ? (model.nativeIPadDescriptor == nil
                                ? "native_ipad.choose_another"
                                : "native_ipad.revalidate")
                            : failure.recoveryLocalizationKey
                    )) {
                        model.recoverFromFailure()
                    }
                    .buttonStyle(LauncherPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
                if !model.isNativeIPadRuntimeSelected
                    && (failure.origin == .launch || failure.origin == .runtime) {
                    Button(LauncherL10n.text("action.repair_installation")) { model.repair() }
                        .buttonStyle(LauncherSecondaryButtonStyle())
                }
                Spacer()
                Button(LauncherL10n.text("action.view_log")) { model.openLog() }
                    .buttonStyle(LauncherTertiaryButtonStyle())
                Button(LauncherL10n.text("action.data_folder")) { model.openDataFolder() }
                    .buttonStyle(LauncherTertiaryButtonStyle())
            }
        }
    }
}

private func configurationSummary(
    _ configuration: LaunchConfigurationSnapshot,
    full: Bool = false
) -> some View {
    Label(
        full ? configuration.fullSummary : configuration.compactSummary,
        systemImage: "slider.horizontal.3"
    )
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
    .padding(.horizontal, LauncherTheme.Spacing.regular)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
            .fill(LauncherTheme.ColorToken.raisedControl.opacity(0.64))
    )
}

extension LauncherHotkeyStatus {
    var localizationKey: String {
        switch self {
        case .permissionRequired: return "hotkeys.status.permission_required"
        case .ready: return "hotkeys.status.ready"
        case .active: return "hotkeys.status.active"
        case .unavailable: return "hotkeys.status.unavailable"
        }
    }
}

private extension LauncherFailure {
    var titleLocalizationKey: String {
        switch origin {
        case .installation: return "error.installation.title"
        case .launch: return "error.launch.title"
        case .runtime: return "error.runtime.title"
        case .validation: return "error.validation.title"
        case .reset: return "error.reset.title"
        }
    }

    var summaryLocalizationKey: String {
        switch origin {
        case .installation: return "error.installation.summary"
        case .launch: return "error.launch.summary"
        case .runtime: return "error.runtime.summary"
        case .validation: return "error.validation.summary"
        case .reset: return "error.reset.summary"
        }
    }

    var recoveryLocalizationKey: String {
        switch recoveryAction {
        case .retryInstallation: return "action.retry_installation"
        case .tryLaunchAgain: return "action.try_again"
        case .restartGame: return "action.restart_game"
        case .repairInstallation: return "action.repair_installation"
        case .none: return ""
        }
    }
}
