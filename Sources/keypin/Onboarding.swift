import AppKit
import SwiftUI

/// A shared draft in AppModel keeps the window and menu-bar popover in sync.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @Binding var query: String

    private var choices: [InputChoice] {
        query.isEmpty ? model.sources : model.sources.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text(model.setupStep == 0 ? "setup.choose-title" : "setup.confirm-title"))
                        .font(.system(size: 20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text(model.setupStep == 0 ? "setup.choose-body" : "setup.confirm-body"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
                if model.setupStep == 0 { sourceSelection } else { confirmation }
                // Submission errors stay directly above the actions.
                if let warning = model.warning {
                    Banner(text: warning, symbol: "exclamationmark.triangle.fill", tint: .orange)
                        .accessibilityIdentifier("setup-warning")
                }
                navigation
            }
        }
    }

    private var sourceSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.sources.count > PanelMetrics.visibleRows || !query.isEmpty {
                SearchField(text: $query, identifier: "setup-search")
            }
            SourceList(sources: choices, totalCount: model.sources.count, selectedID: model.setupSourceID,
                       currentID: model.currentID, sourceIcon: { model.sourceIcon(for: $0) }) { model.setupSourceID = $0 }
            HStack(spacing: 2) {
                Button { openKeyboardSettings(isPreview: model.isPreview) } label: {
                    Label(L10n.text("ui.keyboard-settings"), systemImage: "keyboard")
                }
                .accessibilityIdentifier("setup-keyboard-settings")
                Spacer(minLength: 4)
                Button { model.refreshSourceArtwork() } label: {
                    Label(L10n.text("setup.refresh"), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("setup-refresh")
            }
            .buttonStyle(QuietButtonStyle())
            .padding(.horizontal, -4)
            Text(L10n.text("setup.draft-hint"))
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SourceArtwork(image: model.setupSourceID.map { model.sourceIcon(for: $0) } ?? MenuBarIcon.image, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("ui.target"))
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    Text(model.setupSourceName ?? L10n.text("setup.source-gone"))
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("setup-target")
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .surface(radius: 16, tint: .accentColor)

            VStack(spacing: 0) {
                SettingRow(symbol: "pin.fill", color: .accentColor, title: L10n.text("setup.keep"),
                           caption: L10n.text("setup.keep-caption")) {
                    Toggle(L10n.text("setup.keep"), isOn: $model.setupKeepEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .accessibilityIdentifier("setup-keep")
                }
                InsetDivider()
                SettingRow(symbol: "power", color: .green, title: L10n.text("panel.login"),
                           caption: L10n.text("setup.login-caption")) {
                    Toggle(L10n.text("panel.login"), isOn: Binding(
                        get: { model.setupLoginRequested ?? model.loginEnabled },
                        set: { model.setupLoginRequested = $0 }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .accessibilityIdentifier("setup-login")
                }
            }
            .surface(radius: 13)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("setup.menu-title")).font(.system(size: 11.5, weight: .semibold))
                    Text(L10n.text("setup.menu-body")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            if model.setupStep == 1 {
                Button { model.setupStep = 0 } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).frame(height: 18)
                }
                .modifier(SetupButtonStyle())
                .controlSize(.large)
                .help(L10n.text("ui.back"))
                .accessibilityLabel(L10n.text("ui.back"))
                .accessibilityIdentifier("setup-back")
            }
            StepDots(step: model.setupStep, count: 2)
            Spacer(minLength: 8)
            Button {
                if model.setupStep == 0 { model.setupStep = 1 } else { model.finishSetup() }
            } label: {
                Text(L10n.text(model.setupStep == 0 ? "setup.next" : "setup.finish"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
            }
            .modifier(SetupButtonStyle(prominent: true))
            .controlSize(.large)
            .disabled(!model.canFinishSetup)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("setup-next")
        }
        .padding(.top, 2)
    }
}

/// Kept outside the scrolling body so Skip/Cancel remains reachable on small displays.
struct OnboardingHeader: View {
    @ObservedObject var model: AppModel
    let inWindow: Bool

    var body: some View {
        PanelHeader(inWindow: inWindow, title: L10n.text("app.name")) {
            EmptyView()
        } trailing: {
            Button(L10n.text(model.isInitialSetup ? "setup.skip" : "setup.cancel")) { model.skipSetup() }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.loginBusy)
                .accessibilityIdentifier("setup-skip")
                .padding(.trailing, -6)
        }
    }
}

/// Progress indicator; the localized step text is exposed to assistive technologies.
struct StepDots: View {
    let step: Int
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: index == step ? 16 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .panelTransition(duration: 0.2), value: step)
        .accessibilityElement()
        .accessibilityLabel(L10n.format("setup.progress", step + 1))
        .accessibilityIdentifier("setup-progress")
    }
}
