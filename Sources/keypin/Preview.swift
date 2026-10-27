#if DEBUG
import AppKit
import Combine
import SwiftUI

/// A separate debug-only process with in-memory services; never starts Enforcer or Agent.
@MainActor
enum Preview {
    private static var launchObserver: NSObjectProtocol?
    @MainActor
    final class Store {
        var config: Config
        var choices: [InputChoice]
        var current: InputChoice
        var login = true
        var failed = false
        var saveFailed = false
        var saveFailuresRemaining = 0
        var loadFailed = false
        var loginFailed = false
        var secure = false
        var switching = false
        var conflictPaused = false
        var switchDelay: TimeInterval = 0
        var switchGeneration = 0
        var pendingChoices: [InputChoice]?
        var subscriptions = Set<AnyCancellable>()

        static let standardChoices = [InputChoice(id: "demo.abc", name: "ABC"),
                                      InputChoice(id: "demo.squirrel", name: "鼠须管 · 简体中文")]

        init(state: String, language: String) {
            choices = Self.standardChoices
            current = choices[1]
            config = Config(sourceID: current.id, enabled: true, language: language, onboardingCompleted: true)
            if state.hasPrefix("first") {
                config = Config(sourceID: nil, enabled: false, language: language)
                login = false
            }
            if state == "first-save-error" || state == "save-failure" { saveFailed = true }
            if state == "first-save-retry" || state == "save-retry" { saveFailuresRemaining = 1 }
            if state == "config-error" || state == "settings-config-error" { loadFailed = true }
            if state == "settings-login-error" { loginFailed = true }
            if state == "first-login-error" { loginFailed = true; failed = true }
            if state == "paused" { config.enabled = false; current = choices[0] }
            if state == "missing" { config.sourceID = "missing" }
            if state == "empty" || state == "first-empty" || state == "first-refresh" {
                choices = []
                config = Config(sourceID: nil, enabled: false, language: language)
            }
            if state == "failure" { failed = true; config.enabled = false }
            if state == "secure" { secure = true; current = choices[0] }
            if state == "switching" { switching = true; current = choices[0] }
            if state == "conflict" { conflictPaused = true; current = choices[0] }
            if state == "delayed-switch" { switchDelay = 15 }
            if state == "waiting" || state == "error" || state == "retry-success" { current = choices[0] }
            if state == "many" || state == "first-many" || state == "long-error" || state == "many-200" {
                let count = state == "many-200" ? 198 : 12
                choices += (1...count).map { InputChoice(id: "demo.\($0)", name: "\($0) · Extended Keyboard Input Source — Long Name") }
            }
            if state == "long-name" || state == "first-long-name" {
                choices[1] = InputChoice(id: choices[1].id,
                                        name: String(repeating: "Extended multilingual input source — 简体中文 · 日本語 · 한국어 · ", count: 4))
                current = choices[1]
            }
        }

        func readChoices() -> [InputChoice] {
            if let pendingChoices {
                choices = pendingChoices
                self.pendingChoices = nil
            }
            return choices
        }

        func apply(completion: @escaping (SwitchOutcome) -> Void) {
            conflictPaused = false
            if secure { completion(.secureInput); return }
            if failed { completion(.failed("Preview: input source did not change")); return }
            guard let choice = choices.first(where: { $0.id == config.sourceID }) else {
                completion(.missingSource)
                return
            }
            guard switchDelay > 0 else {
                current = choice
                completion(.success)
                return
            }
            switchGeneration += 1
            let generation = switchGeneration
            switching = true
            DispatchQueue.main.asyncAfter(deadline: .now() + switchDelay) { [weak self] in
                guard let self, self.switchGeneration == generation else { return }
                self.switching = false
                self.current = choice
                completion(.success)
            }
        }

        func cancelSwitch() {
            switchGeneration += 1
            switching = false
        }
    }

    static func configure(arguments: [String]) {
        let state = arguments.count > 1 ? arguments[1] : "active"
        let language = arguments.count > 2 ? arguments[2] : "zh-Hans"
        let appearance = arguments.count > 3 ? arguments[3] : "light"
        let store = Store(state: state, language: language)
        // A failed configuration load cannot supply a language; keep the requested
        // fixture locale explicit without touching preferences or live files.
        L10n.languageCode = L10n.normalized(language)
        let services = AppServices(
            load: {
                if store.loadFailed { throw NSError(domain: "Preview.Load", code: 1) }
                return store.config
            }, save: {
                if store.saveFailed || store.saveFailuresRemaining > 0 {
                    store.saveFailuresRemaining = max(0, store.saveFailuresRemaining - 1)
                    throw NSError(domain: "Preview.Save", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Preview: configuration could not be saved."])
                }
                store.config = $0
            }, choices: { store.readChoices() }, current: { store.current },
            loginEnabled: { store.login }, setLogin: {
                if store.loginFailed { throw AgentError("Preview: login registration failed") }
                store.login = $0
            },
            apply: { store.apply(completion: $0) },
            secureInput: { store.secure },
            isSwitching: { store.switching },
            cancelSwitch: { store.cancelSwitch() },
            // Optional bundle-only visual fixtures; never read the live input-source catalog.
            sourceIcon: { id in
                guard let url = Bundle.main.url(forResource: id, withExtension: "tiff", subdirectory: "PreviewArtwork") else { return nil }
                return NSImage(contentsOf: url)
            },
            isConflictPaused: { store.conflictPaused }
        )
        let controller = AppController.shared
        controller.model = AppModel(services: services, isPreview: true)
        if state == "error" || state == "retry-success" {
            controller.model.receiveAutomaticOutcome(.failed("Preview: input source did not change"))
        }
        if state == "long-error" {
            controller.model.receiveAutomaticOutcome(.failed(String(repeating: "Preview: input source did not change. ", count: 20)))
        }
        controller.previewSettings = state.hasPrefix("settings")
        if state == "settings-busy" || state == "settings-busy-completes" { controller.model.loginBusy = true }
        controller.previewAbout = state.hasPrefix("about")
        if state.hasPrefix("about-update") {
            controller.previewUpdates = updateFixture(state: state)
        }
        controller.previewCompact = arguments.contains("compact")
        controller.previewReduced = appearance == "reduced"
        controller.previewLegacyAppearance = arguments.contains("legacy")
        controller.previewPopover = arguments.contains("popover")
        controller.previewHeight = arguments.contains("short") ? 420 : nil
        configureTransitions(state: state, store: store, model: controller.model)
        controller.openWindowOnLaunch = true
        NSApplication.shared.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        if state == "first-confirm" || arguments.contains("--smoke-test") {
            // Exercise real window creation and layout on CI's older macOS runtime.
            // This entry point only exists in debug builds with in-memory services.
            launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
            ) { _ in
                if let launchObserver { NotificationCenter.default.removeObserver(launchObserver) }
                launchObserver = nil
                DispatchQueue.main.async {
                    if state == "first-confirm" {
                        controller.model.setupSourceID = "demo.squirrel"
                        controller.model.setupStep = 1
                    }
                    guard arguments.contains("--smoke-test") else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
                              let view = window.contentView,
                              view.bounds.width >= 300, view.bounds.height >= 100,
                              view.bounds.height <= 900 else { exit(1) }
                        view.layoutSubtreeIfNeeded()
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        print("PASS: preview window rendered")
                        exit(0)
                    }
                }
            }
        }
    }

    /// Only the debug preview can inject this in-memory driver. No Sparkle object,
    /// defaults domain, network request, or installed application is involved.
    private static func updateFixture(state: String) -> UpdateViewModel {
        let configuration = UpdateConfiguration(feed: UpdateConfiguration.releaseFeed,
            publicKey: "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=",
            bundleIdentifier: "app.keypin", isApplicationBundle: true)!
        let driver = UpdatePreviewDriver()
        driver.failsToStart = state == "about-update-failure"
        driver.pendingUpdateVersion = state == "about-update-available" ? "0.0.16" : nil
        let model = UpdateViewModel(info: AppBuildInfo(bundle: L10n.appBundle), configuration: configuration,
                                    makeDriver: { _ in driver })
        model.startIfAllowed(onboardingComplete: true)
        return model
    }

    private final class UpdatePreviewDriver: UpdateDriving {
        var failsToStart = false
        var canCheckForUpdates = true
        var automaticallyChecksForUpdates = false { didSet { onChange?() } }
        var automaticallyDownloadsUpdates = false { didSet { onChange?() } }
        var pendingUpdateVersion: String?
        var onChange: (() -> Void)?
        func start() throws { if failsToStart { throw URLError(.unknown) } }
        func checkForUpdates() {
            // Clicking Check discovers the fixture; Review dismisses its reminder.
            pendingUpdateVersion = pendingUpdateVersion == nil ? "0.0.16" : nil
            onChange?()
        }
    }

    private static func configureTransitions(state: String, store: Store, model: AppModel) {
        if state == "first-refresh" {
            // Background-launched preview windows may never become key. Arm
            // after launch finishes and its initial model reads have completed.
            NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
                .first()
                .receive(on: RunLoop.main)
                .sink { [weak store] _ in store?.pendingChoices = Store.standardChoices }
                .store(in: &store.subscriptions)
        }
        if state == "first-source-gone" {
            model.$setupStep.filter { $0 == 1 }.first()
                .sink { [weak store, weak model] _ in
                    // @Published emits before assignment; queue the catalog
                    // change so the confirmation screen observes step 1.
                    DispatchQueue.main.async {
                        guard let store, let model else { return }
                        let available = store.choices
                        store.choices.removeAll { $0.id == model.setupSourceID }
                        model.refresh()
                        // Back → Refresh restores the missing source.
                        store.pendingChoices = available
                    }
                }
                .store(in: &store.subscriptions)
        }
        if state == "settings-busy-completes" {
            // This exercises the UI transition only. Preview login services are
            // intentionally synchronous, so never block them to imitate Agent.
            NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
                .first()
                .receive(on: RunLoop.main)
                .sink { [weak store, weak model] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        guard let store, let model else { return }
                        store.login = false
                        model.loginBusy = false
                        model.refreshLogin()
                    }
                }
                .store(in: &store.subscriptions)
        }
    }
}
#endif
