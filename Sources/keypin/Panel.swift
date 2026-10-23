import AppKit
import SwiftUI

enum PanelPage: Equatable {
    case main
    case settings
    case about
}

/// The single surface shown in both the menu-bar popover and the standalone window.
/// It sizes itself to its content so short lists never leave empty space.
struct Panel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateViewModel
    var inWindow = false
    var maximumHeight: CGFloat
    @State private var page: PanelPage
    @State private var query = ""
    @State private var setupQuery = ""
    @State private var showsKeepingHelp = false
    @State private var screenHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReducedTransparency
    @Environment(\.previewReduceTransparency) private var previewReducedTransparency
    private var reduceTransparency: Bool { systemReducedTransparency || previewReducedTransparency }

    init(model: AppModel, updates: UpdateViewModel? = nil, inWindow: Bool = false, page: PanelPage = .main, maximumHeight: CGFloat = 580) {
        self.model = model
        self.updates = updates ?? UpdateViewModel(info: AppBuildInfo(bundle: L10n.appBundle), isPreview: true)
        self.inWindow = inWindow
        self.maximumHeight = maximumHeight
        _page = State(initialValue: page)
    }

    private var filtered: [InputChoice] {
        query.isEmpty ? model.sources : model.sources.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var heightLimit: CGFloat { min(maximumHeight, screenHeight ?? maximumHeight) }
    private var headerHeight: CGFloat { (inWindow ? PanelMetrics.titlebarHeight : 38) + 10 }
    private var scrollIdentity: String { "\(page)-\(model.showsOnboarding)-\(model.setupStep)" }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, PanelMetrics.padding)
                .padding(.top, inWindow ? 0 : 10)
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView { content }
                    .scrollIndicators(.visible)
                    .frame(height: max(1, heightLimit - headerHeight))
                    .accessibilityIdentifier("panel-overflow")
                    .id(scrollIdentity)
            }
            .frame(maxHeight: max(1, heightLimit - headerHeight))
        }
        .frame(width: PanelMetrics.width)
        .frame(maxHeight: heightLimit)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if inWindow {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) } else { WindowMaterial() }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background { shortcuts }
        .background {
            PanelScreenHeight { height in
                if screenHeight != height { screenHeight = height }
            }
        }
        .animation(reduceMotion ? nil : .panelTransition(duration: 0.22), value: model.runtimeState)
        .animation(reduceMotion ? nil : .panelTransition(duration: 0.22), value: model.warning)
        .onChange(of: model.showsOnboarding) { showing in
            if showing { setupQuery = "" }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showsOnboarding {
                OnboardingView(model: model, query: $setupQuery)
            } else {
                switch page {
                case .main: mainPage
                case .settings: settingsPage
                case .about: aboutPage
                }
            }
        }
        .padding(.horizontal, PanelMetrics.padding)
        .padding(.bottom, PanelMetrics.padding)
        .frame(width: PanelMetrics.width, alignment: .topLeading)
    }

    @ViewBuilder private var shortcuts: some View {
        HiddenShortcut(key: "q") { NSApp.terminate(nil) }
        if !model.showsOnboarding {
            HiddenShortcut(key: ",") { model.refreshLogin(); page = .settings }
        }
        if inWindow { HiddenShortcut(key: "w") { NSApp.keyWindow?.performClose(nil) } }
    }

    // MARK: Main

    @ViewBuilder private var header: some View {
        if model.showsOnboarding {
            OnboardingHeader(model: model, inWindow: inWindow)
        } else {
            switch page {
            case .main: mainHeader
            case .settings: backHeader(L10n.text("ui.preferences"), to: .main)
            case .about: backHeader(L10n.text("about.title"), to: .settings)
            }
        }
    }

    private var mainHeader: some View {
        PanelHeader(inWindow: inWindow, title: L10n.text("app.name")) {
            if !inWindow {
                Image(nsImage: MenuBarIcon.image)
                    .renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 20, height: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } trailing: {
            if let version = updates.pendingUpdateVersion {
                Button { updates.check() } label: { Image(systemName: "arrow.down.circle.fill") }
                    .buttonStyle(IconButtonStyle())
                    .foregroundStyle(Color.accentColor)
                    .help(L10n.format("about.update.available", version))
                    .accessibilityLabel(L10n.format("about.update.available", version))
                    .accessibilityIdentifier("review-available-update")
                    .disabled(!updates.canCheckForUpdates)
            }
            Button { model.refreshLogin(); page = .settings } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconButtonStyle())
                .help(L10n.text("ui.preferences"))
                .accessibilityLabel(L10n.text("ui.preferences"))
                .accessibilityIdentifier("settings")
        }
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let warning = model.warning { warningBanner(warning) }
            if model.runtimeState.isTransient || model.runtimeState == .secureInput {
                statusLine(model.runtimeState).padding(.horizontal, 4)
            }
            sourceSection
            footer
        }
    }

    private func statusLine(_ state: RuntimeState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: state.symbol)
                .statusPulse(isActive: state.isTransient && !reduceMotion)
                .font(.system(size: 10, weight: .bold))
            Text(L10n.text(model.statusKey))
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(state.isNeutral ? Color.secondary : state.tint)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pin-status")
    }

    private func warningBanner(_ warning: String) -> some View {
        let secure = model.runtimeState == .secureInput
        return Banner(text: warning,
                      symbol: secure ? "lock.shield.fill" : "exclamationmark.triangle.fill",
                      tint: secure ? .indigo : .orange,
                      actionTitle: model.canRetrySwitch ? L10n.text("ui.retry") : nil,
                      action: model.canRetrySwitch ? { model.retry() } : nil)
            .accessibilityIdentifier("warning")
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.sources.count > PanelMetrics.visibleRows || !query.isEmpty {
                SearchField(text: $query, identifier: "source-search")
            }
            SourceList(sources: filtered, totalCount: model.sources.count, selectedID: model.enabled ? model.pinnedID : nil,
                       currentID: model.currentID,
                       followSystem: FollowSystemChoice(selected: !model.enabled, action: { model.pauseKeeping() }),
                       sourceIcon: { model.sourceIcon(for: $0) }) { model.choose($0) }
                .disabled(model.configError)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button { openKeyboardSettings(isPreview: model.isPreview) } label: {
                Label(L10n.text("ui.keyboard-settings"), systemImage: "keyboard")
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("keyboard-settings")
            Spacer(minLength: 4)
            Button { NSApp.terminate(nil) } label: {
                Label(L10n.text("panel.quit"), systemImage: "power")
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("quit")
        }
        .padding(.horizontal, -4)
    }

    // MARK: Settings

    private func backHeader(_ title: String, to destination: PanelPage) -> some View {
        PanelHeader(inWindow: inWindow, title: title) {
            Button { page = destination } label: { Image(systemName: "chevron.left") }
                .buttonStyle(IconButtonStyle())
                .help(L10n.text("ui.back"))
                .accessibilityLabel(L10n.text("ui.back"))
                .accessibilityIdentifier("back")
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .padding(.leading, -4)
        } trailing: { EmptyView() }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsRow(L10n.text("panel.login")) {
                ZStack {
                    Toggle(L10n.text("panel.login"), isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .disabled(model.loginBusy)
                        .opacity(model.loginBusy ? 0 : 1)
                        .accessibilityHidden(model.loginBusy)
                        .accessibilityHint(L10n.text("panel.login.caption"))
                        .accessibilityIdentifier("login-enabled")
                    if model.loginBusy {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel(L10n.text("state.updating"))
                            .accessibilityIdentifier("login-progress")
                    }
                }
                .frame(width: 36, height: 22)
            }
            .help(L10n.text("panel.login.caption"))

            settingsRow(L10n.text("panel.language")) {
                Menu {
                    Picker(L10n.text("panel.language"), selection: Binding(get: { model.language ?? "" },
                                                                           set: { model.setLanguage($0.isEmpty ? nil : $0) })) {
                        Text(L10n.text("lang.system")).tag("")
                        Divider()
                        Text("English").tag("en")
                        Text("简体中文").tag("zh-Hans")
                        Text("繁體中文").tag("zh-Hant")
                        Text("日本語").tag("ja")
                        Text("한국어").tag("ko")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(languageTitle).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L10n.text("panel.language"))
                .accessibilityValue(languageTitle)
                .accessibilityIdentifier("language")
            }

            if let warning = model.warning {
                warningBanner(warning).padding(.top, 6)
            }
            settingsDivider

            navigationRow(title: L10n.text("setup.reopen"), accessory: "chevron.right", id: "setup-reopen") {
                model.beginSetup()
            }
            .disabled(model.configError || model.loginBusy)
            navigationRow(title: L10n.text("ui.keyboard-settings"), accessory: "arrow.up.forward", id: "settings-keyboard") {
                openKeyboardSettings(isPreview: model.isPreview)
            }
            navigationRow(title: L10n.text("about.title"), accessory: updates.pendingUpdateVersion == nil ? "chevron.right" : "arrow.down.circle.fill", id: "about") { page = .about }

            settingsDivider
            DisclosureGroup(isExpanded: $showsKeepingHelp) {
                Text(L10n.text("ui.how-body"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                Text(L10n.text("ui.how-title"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("keeping-help")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var languageTitle: String {
        switch model.language {
        case "en": "English"
        case "zh-Hans": "简体中文"
        case "zh-Hant": "繁體中文"
        case "ja": "日本語"
        case "ko": "한국어"
        default: L10n.text("lang.system.short")
        }
    }

    /// One alignment grid for preferences and navigation, with no nested cards.
    private func settingsRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 0)
            trailing().fixedSize()
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var settingsDivider: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func navigationRow(title: String, accessory: String, id: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsRow(title) {
                Image(systemName: accessory)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(RowButtonStyle(radius: 7))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    // MARK: About

    private var aboutPage: some View {
        AboutView(model: updates)
    }
}
