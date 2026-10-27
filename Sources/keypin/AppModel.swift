import AppKit
import Carbon
import Foundation

/// Services are injected so previews and tests cannot switch the user's keyboard or edit login items.
struct AppServices {
    var load: () throws -> Config
    var save: (Config) throws -> Void
    var choices: () -> [InputChoice]
    var current: () -> InputChoice
    var loginEnabled: () -> Bool
    var setLogin: (Bool) throws -> Void
    var apply: (@escaping (SwitchOutcome) -> Void) -> Void
    var updateConfig: (((inout Config) -> Void) throws -> Config)? = nil
    var secureInput: () -> Bool = { false }
    var isSwitching: () -> Bool = { false }
    var cancelSwitch: () -> Void = {}
    var sourceIcon: (String) -> NSImage? = { _ in nil }
    var isConflictPaused: () -> Bool = { false }

    static var live: AppServices {
        AppServices(
            load: { try ConfigStore.loadChecked() }, save: { try ConfigStore.save($0) },
            choices: { Catalog.choices() },
            current: { let value = Catalog.current(); return InputChoice(id: value.id, name: value.name) },
            loginEnabled: { Agent.isLoginEnabled },
            setLogin: { on in
                if on {
                    guard let executable = Bundle.main.executableURL else { throw AgentError(L10n.text("warn.no-executable")) }
                    try Agent.install(executable: executable, installCLICommand: false)
                } else { try Agent.uninstall(stopRunningAgent: false) }
            },
            apply: { completion in Enforcer.shared.enforce(force: true, finish: completion) },
            updateConfig: { edit in try ConfigStore.update(edit) },
            secureInput: { IsSecureEventInputEnabled() },
            isSwitching: { Enforcer.shared.isSwitching },
            cancelSwitch: { Enforcer.shared.cancelManualRequests() },
            sourceIcon: { Catalog.icon(for: $0) },
            isConflictPaused: { Enforcer.shared.isConflictPaused }
        )
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var sources: [InputChoice] = []
    @Published var currentName = ""
    @Published var currentID = ""
    @Published private(set) var currentSourceIcon: NSImage = MenuBarIcon.image
    @Published var pinnedID: String?
    @Published var enabled = false
    @Published var loginEnabled = false
    @Published var loginBusy = false
    @Published var switching = false
    @Published var language: String?
    @Published var warning: String?
    @Published private(set) var secureInput = false
    @Published private(set) var automaticSwitching = false
    @Published private(set) var conflictPaused = false
    @Published private(set) var configError = false
    @Published private(set) var showsOnboarding = false
    @Published var setupStep = 0
    @Published var setupSourceID: String?
    @Published var setupKeepEnabled = true
    // nil means leave the current login setting unchanged, including while its read is pending.
    @Published var setupLoginRequested: Bool?
    private var needsOnboarding = false
    private let services: AppServices
    private struct SwitchWarning {
        let outcome: SwitchOutcome

        var message: String? {
            switch outcome {
            case .success: return nil
            case .secureInput: return L10n.text("enf.secure")
            case .missingSource: return L10n.text("warn.missing")
            case .failed(let message): return L10n.format("warn.switch", message)
            case .busy: return L10n.text("warn.busy")
            }
        }
    }
    private var saveErrorDetail: String?
    private var manualWarning: SwitchWarning?
    private var automaticWarning: SwitchWarning?
    private var loginErrorDetail: String?
    private var request = 0
    private var loginRefresh = 0
    // Cache the normalized artwork, including the fallback, so menus and list
    // rows share one image without querying the catalog during every redraw.
    private var sourceArtwork: [String: NSImage] = [:]
    private var artworkSourceIDs: Set<String> = []
    let isPreview: Bool

    init(services: AppServices = .live, isPreview: Bool = false) {
        self.services = services
        self.isPreview = isPreview
    }

    var pinnedName: String? { sources.first { $0.id == pinnedID }?.name }
    var targetMissing: Bool { pinnedID != nil && pinnedName == nil }
    var canEnable: Bool { pinnedName != nil && !configError }
    var canRetrySwitch: Bool {
        !configError && !targetMissing && !switching && !automaticSwitching && !secureInput
            && (manualWarning != nil || (enabled && (automaticWarning != nil || conflictPaused)))
    }
    var runtimeState: RuntimeState {
        RuntimeState.resolve(config: Config(sourceID: pinnedID, enabled: enabled),
                             currentID: currentID, targetAvailable: pinnedName != nil,
                             secureInput: secureInput, switching: switching || (enabled && automaticSwitching),
                             failed: manualWarning != nil || (enabled && automaticWarning != nil),
                             configurationError: configError, conflictPaused: conflictPaused)
    }
    var menuSourceName: String { currentName.isEmpty ? L10n.text("ui.follow-system") : currentName }

    var statusKey: String { runtimeState.localizationKey }

    func sourceIcon(for id: String) -> NSImage {
        guard !id.isEmpty, artworkSourceIDs.contains(id) else { return MenuBarIcon.image }
        if let image = sourceArtwork[id] { return image }
        let image = MenuBarIcon.inputSourceImage(services.sourceIcon(id))
        sourceArtwork[id] = image
        return image
    }

    func refreshSourceArtwork() {
        // Row artwork can change even when the current source keeps using the
        // same fallback image, so explicitly invalidate the observable view.
        objectWillChange.send()
        sourceArtwork.removeAll()
        refresh()
    }

    func start() {
        if !isPreview {
            Enforcer.shared.onUpdate = { [weak self] in self?.refresh() }
            Enforcer.shared.onAutomaticOutcome = { [weak self] outcome in self?.receiveAutomaticOutcome(outcome) }
            Enforcer.shared.start()
        }
        refresh()
        refreshLogin()
        if needsOnboarding && !configError { beginSetup() }
        if enabled && !isPreview { Enforcer.shared.kick() }
    }

    /// Input-source notifications never launch a process or resize the window.
    func refresh() {
        let previousTarget = pinnedID
        let wasEnabled = enabled
        let previousCurrent = currentID
        do {
            let config = try services.load()
            needsOnboarding = config.needsOnboarding
            let code = L10n.normalized(config.language)
            L10n.languageCode = code
            if language != code { language = code }
            if pinnedID != config.sourceID { pinnedID = config.sourceID }
            if enabled != config.enabled { enabled = config.enabled }
            if configError { configError = false }
        } catch {
            if !configError { configError = true }
            if enabled { enabled = false }
        }
        if previousTarget != pinnedID || wasEnabled != enabled || configError {
            // An external pause or target change also invalidates late manual callbacks.
            request += 1
            switching = false
            manualWarning = nil
            automaticWarning = nil
        }
        if wasEnabled && !enabled { services.cancelSwitch() }
        let choices = services.choices()
        let catalogChanged = sources != choices
        let current = services.current()
        artworkSourceIDs = Set(choices.map(\.id)).union([current.id])
        if catalogChanged { sourceArtwork.removeAll() }
        else { sourceArtwork = sourceArtwork.filter { artworkSourceIDs.contains($0.key) } }
        if catalogChanged { sources = choices }
        if currentName != current.name { currentName = current.name }
        if currentID != current.id { currentID = current.id }
        let icon = sourceIcon(for: current.id)
        if currentSourceIcon !== icon { currentSourceIcon = icon }
        let secure = services.secureInput()
        if secureInput != secure { secureInput = secure }
        let activeSwitch = services.isSwitching()
        if automaticSwitching != activeSwitch { automaticSwitching = activeSwitch }
        let pausedForConflict = enabled && services.isConflictPaused()
        if conflictPaused != pausedForConflict { conflictPaused = pausedForConflict }
        if previousCurrent != current.id && current.id == pinnedID {
            clearSwitchWarnings()
        }
        // The system may leave secure input without performing a source switch.
        if !secure {
            if manualWarning?.outcome == .secureInput { manualWarning = nil }
            if automaticWarning?.outcome == .secureInput { automaticWarning = nil }
        }
        let nextWarning: String?
        if configError { nextWarning = L10n.text("warn.config") }
        else {
            let runtimeWarning = manualWarning?.message ?? (enabled ? (targetMissing ? L10n.text("warn.missing") :
                (conflictPaused ? L10n.text("warn.conflict") : automaticWarning?.message)) : nil)
            // Keep the error detail, not a translated sentence, so changing the app
            // language also updates warnings that remain visible until recovery.
            let messages = [saveErrorDetail.map { L10n.format("warn.save", $0) }, runtimeWarning,
                            loginErrorDetail.map { L10n.format("warn.login", $0) }].compactMap { $0 }
            nextWarning = messages.isEmpty ? nil : messages.joined(separator: "\n")
        }
        if warning != nextWarning { warning = nextWarning }
    }

    func receiveAutomaticOutcome(_ outcome: SwitchOutcome) {
        refresh()
        guard enabled, let target = pinnedID, !configError else { return }
        switch outcome {
        case .success:
            if currentID == target { clearSwitchWarnings() }
        case .busy: return
        default: automaticWarning = SwitchWarning(outcome: outcome)
        }
        refresh()
    }

    private func clearSwitchWarnings() {
        manualWarning = nil
        automaticWarning = nil
    }

    func refreshLogin() {
        guard !loginBusy else { return }
        if isPreview { loginEnabled = services.loginEnabled(); return }
        loginRefresh += 1
        let token = loginRefresh
        let check = services.loginEnabled
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let enabled = check()
            DispatchQueue.main.async {
                guard let self, !self.loginBusy, token == self.loginRefresh else { return }
                self.loginEnabled = enabled
            }
        }
    }

    @discardableResult
    private func update(_ edit: (inout Config) -> Void) -> Bool {
        do {
            if let transaction = services.updateConfig { _ = try transaction(edit) }
            else {
                var config = try services.load()
                edit(&config)
                try services.save(config)
            }
            saveErrorDetail = nil
            refresh()
            return true
        } catch {
            saveErrorDetail = error.localizedDescription
            refresh()
            return false
        }
    }

    func choose(_ id: String) {
        // The source can be removed while the panel is open, before the next notification.
        // Validate against the current catalog before committing a new target.
        refresh()
        guard sources.contains(where: { $0.id == id }), !configError else { return }
        // A real source selection always means keep this source. Publish both values
        // together so enforcement never observes a new target with the old mode.
        guard update({ $0.sourceID = id; $0.enabled = true }) else { return }
        apply()
    }

    func pauseKeeping() {
        let wasEnabled = enabled
        guard update({ $0.enabled = false }) else { return }
        request += 1
        switching = false
        clearSwitchWarnings()
        if !wasEnabled { services.cancelSwitch() }
        refresh()
    }

    func retry() {
        guard canRetrySwitch else { return }
        if canEnable { apply() }
    }

    private func apply() {
        guard let target = pinnedID, canEnable else { return }
        request += 1
        let token = request
        clearSwitchWarnings()
        switching = true
        services.apply { [weak self] outcome in
            guard let self, token == self.request else { return }
            self.refresh()
            guard token == self.request, self.pinnedID == target else { return }
            self.switching = false
            self.manualWarning = outcome == .success ? nil : SwitchWarning(outcome: outcome)
            self.refresh()
        }
    }

    func setLanguage(_ code: String?) {
        _ = update { $0.language = L10n.normalized(code) }
    }

    var setupSourceName: String? { sources.first { $0.id == setupSourceID }?.name }
    var isInitialSetup: Bool { needsOnboarding }
    var canFinishSetup: Bool { setupSourceName != nil && !configError && !loginBusy }

    func beginSetup() {
        refresh()
        guard !configError else { return }
        setupStep = 0
        setupSourceID = pinnedID
        setupKeepEnabled = pinnedID == nil ? true : enabled
        setupLoginRequested = nil
        showsOnboarding = true
        refreshLogin()
    }

    func skipSetup() {
        guard showsOnboarding, !loginBusy else { return }
        if needsOnboarding && !update({ $0.onboardingCompleted = true }) { return }
        showsOnboarding = false
    }

    func finishSetup() {
        guard showsOnboarding else { return }
        // Refresh the catalog at submission, since an input source can disappear while the wizard is open.
        refresh()
        guard canFinishSetup, let sourceID = setupSourceID else { return }
        let keep = setupKeepEnabled
        let login = setupLoginRequested
        // One transaction: Enforcer never sees a new target with stale enabled state.
        guard update({
            $0.sourceID = sourceID
            $0.enabled = keep
            $0.onboardingCompleted = true
        }) else { return }
        request += 1
        switching = false
        showsOnboarding = false
        if keep { apply() }
        if let login { setLogin(login) }
    }

    func setLogin(_ on: Bool) {
        guard !loginBusy else { return }
        loginBusy = true
        loginRefresh += 1
        loginErrorDetail = nil
        let change = services.setLogin
        let check = services.loginEnabled
        let work = { () -> (Bool, String?) in
            do { try change(on); return (check(), nil) }
            catch { return (check(), String(describing: error)) }
        }
        let finish: ((Bool, String?)) -> Void = { [weak self] result in
            guard let self else { return }
            self.loginEnabled = result.0
            self.loginBusy = false
            if let error = result.1 {
                self.loginErrorDetail = error
            }
            self.refresh()
        }
        if isPreview { finish(work()) }
        else {
            DispatchQueue.global(qos: .utility).async {
                let result = work()
                DispatchQueue.main.async { finish(result) }
            }
        }
    }
}
