import AppKit
import Carbon
import Darwin
import Foundation

enum SwitchOutcome: Equatable {
    case success
    case secureInput
    case missingSource
    case failed(String)
    /// A newer request replaced this one, or automatic switching is paused.
    case busy
}

/// CJK input methods still need the isolated focus workaround on affected macOS versions.
/// The helper validates its request again because configuration may change while it starts.
enum FocusHelper {
    static let secureExit: Int32 = 75
    static let staleExit: Int32 = 76
    static let missingExit: Int32 = 77
    static let switchExit: Int32 = 78

    static func requestIsCurrent(id: String, automatic: Bool, config: Config) -> Bool {
        config.sourceID == id && (!automatic || config.enabled)
    }

    static func run(id: String) -> Never {
        let automatic = CommandLine.arguments.contains("--automatic")
        guard requestIsCurrent(id: id, automatic: automatic, config: ConfigStore.load()) else {
            exit(staleExit)
        }
        guard !IsSecureEventInputEnabled() else { exit(secureExit) }
        guard let target = Catalog.find(id) else { exit(missingExit) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main else { exit(switchExit) }
        guard requestIsCurrent(id: id, automatic: automatic, config: ConfigStore.load()) else {
            exit(staleExit)
        }
        guard !IsSecureEventInputEnabled() else { exit(secureExit) }
        guard TISSelectInputSource(target.ref) == noErr else { exit(switchExit) }

        let side: CGFloat = 3
        let frame = screen.visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: frame.maxX - side - 8, y: frame.minY + 8, width: side, height: side),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        guard !IsSecureEventInputEnabled() else { exit(secureExit) }
        guard requestIsCurrent(id: id, automatic: automatic, config: ConfigStore.load()) else {
            exit(staleExit)
        }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
            guard requestIsCurrent(id: id, automatic: automatic, config: ConfigStore.load()) else {
                exit(staleExit)
            }
            exit(Catalog.current().id == id ? 0 : switchExit)
        }
        app.run()
        exit(switchExit)
    }
}

struct EnforcementTarget {
    let id: String
    let requiresFocus: Bool
}

enum FocusProcessResult: Equatable {
    case exited(Int32)
    case timedOut
    case cancelled
}

/// All system mutations are behind injected closures so unit tests never change input methods.
struct EnforcementDependencies {
    var config: () -> Config
    var secureInput: () -> Bool
    var currentID: () -> String
    var find: (String) -> EnforcementTarget?
    var select: (String) -> Int32
    var launchFocus: (String, Bool, @escaping (FocusProcessResult) -> Void) throws -> (() -> Void)
    var now: () -> Date = Date.init

    static var live: EnforcementDependencies {
        EnforcementDependencies(
            config: ConfigStore.load,
            secureInput: { IsSecureEventInputEnabled() },
            currentID: { Catalog.current().id },
            find: { id in
                Catalog.find(id).map { EnforcementTarget(id: $0.id, requiresFocus: $0.isCJKV) }
            },
            select: { id in
                guard let target = Catalog.find(id) else { return Int32(paramErr) }
                return TISSelectInputSource(target.ref)
            },
            launchFocus: { id, automatic, completion in
                let job = FocusProcessJob(completion: completion)
                try job.start(id: id, automatic: automatic)
                return { job.cancel() }
            }
        )
    }
}

/// Wait for the actual child exit; the cancellation closure keeps this job alive.
final class FocusProcessJob {
    private let process = Process()
    private var completion: ((FocusProcessResult) -> Void)?
    private var deadline: DispatchWorkItem?
    private var stopReason: FocusProcessResult?
    private let timeoutInterval: TimeInterval

    init(timeout: TimeInterval = 3, completion: @escaping (FocusProcessResult) -> Void) {
        self.timeoutInterval = timeout
        self.completion = completion
    }

    func start(id: String, automatic: Bool) throws {
        let executable = try FocusHelperLocation.executable(in: L10n.appBundle)
        try start(executable: executable, arguments: ["focus", id] + (automatic ? ["--automatic"] : []))
    }

    /// This overload also lets process-lifecycle tests use a harmless isolated child.
    func start(executable: URL, arguments: [String]) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async { self?.finish(status: status) }
        }
        try process.run()
        let timeout = DispatchWorkItem { [weak self] in self?.stop(.timedOut) }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
    }

    func cancel() { stop(.cancelled) }

    private func stop(_ reason: FocusProcessResult) {
        guard completion != nil, stopReason == nil else { return }
        stopReason = reason
        guard process.isRunning else { return }
        process.terminate()
        // A wedged AppKit child must not keep later manual requests queued forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [self] in
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finish(status: Int32) {
        deadline?.cancel()
        deadline = nil
        let callback = completion
        completion = nil
        callback?(stopReason ?? .exited(status))
    }
}

final class Enforcer: NSObject {
    static let shared = Enforcer()
    var onUpdate: (() -> Void)?
    var onAutomaticOutcome: ((SwitchOutcome) -> Void)?

    private struct Request {
        let token = UUID()
        let target: String
        let force: Bool
        let finish: ((SwitchOutcome) -> Void)?
    }

    private let dependencies: EnforcementDependencies
    private var active: Request?
    private var pending: Request?
    private var cancelActive: (() -> Void)?
    private var cancelledManualToken: UUID?
    private var completionDepth = 0
    private var ignoreActivationUntil = Date.distantPast
    private var nextFocusAt = Date.distantPast
    private var started = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(dependencies: EnforcementDependencies = .live) {
        self.dependencies = dependencies
        super.init()
    }

    deinit {
        if started {
            DistributedNotificationCenter.default().removeObserver(self)
            workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        }
        timer?.invalidate()
        cancelActive?()
    }

    var suppressesActivation: Bool { dependencies.now() < ignoreActivationUntil }
    var isSwitching: Bool { active != nil }

    /// Explicit pause cancels GUI-owned manual work without affecting a later one-time selection.
    /// Keep the active slot until the child exits, so a replacement cannot overlap that process.
    func cancelManualRequests() {
        let queued = pending?.force == true ? pending : nil
        if queued != nil { pending = nil }
        if let active, active.force, cancelledManualToken != active.token {
            cancelledManualToken = active.token
            cancelActive?()
        }
        queued?.finish?(.busy)
    }

    func start() {
        guard !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(inputSourceChanged),
                           name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                           object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(configChanged), name: ConfigStore.changed,
                           object: nil, suspensionBehavior: .deliverImmediately)
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.kick() })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
            if self.suppressesActivation { return }
            self.kick()
        })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            // Secure input can end without an app/input-source notification, even while paused.
            self?.kick()
        }
    }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in self?.kick() }
    }

    @objc private func configChanged() {
        DispatchQueue.main.async { [weak self] in self?.kick() }
    }

    func kick() {
        onUpdate?()
        enforce(force: false)
    }

    /// Manual requests always produce a result. A newer manual choice replaces only queued work.
    func enforce(force: Bool, finish: ((SwitchOutcome) -> Void)? = nil) {
        let config = dependencies.config()
        if !force && !config.enabled {
            if let active, !active.force { cancelActive?() }
            finish?(.success)
            return
        }
        guard let target = config.sourceID, !target.isEmpty else {
            finish?(.missingSource)
            return
        }
        let request = Request(target: target, force: force, finish: finish)
        if active != nil || completionDepth > 0 {
            // Passive notifications must not displace an explicit selection already waiting.
            if !force && (active?.target == target || pending?.force == true) {
                finish?(.busy)
                return
            }
            let displaced = pending
            pending = request
            // Finish callbacks may enqueue an even newer choice. Publish this request first,
            // then only cancel for it if that callback has not already replaced it.
            displaced?.finish?(.busy)
            if pending?.token == request.token, let active, active.target != target { cancelActive?() }
            return
        }
        execute(request)
    }

    private func execute(_ request: Request) {
        active = request
        let config = dependencies.config()
        guard config.sourceID == request.target, request.force || config.enabled else {
            complete(request, .busy)
            return
        }
        guard !dependencies.secureInput() else {
            complete(request, .secureInput)
            return
        }
        guard dependencies.currentID() != request.target else {
            complete(request, .success)
            return
        }
        guard let target = dependencies.find(request.target) else {
            complete(request, .missingSource)
            return
        }
        ignoreActivationUntil = dependencies.now().addingTimeInterval(1)
        if target.requiresFocus {
            guard request.force || dependencies.now() >= nextFocusAt else {
                complete(request, .busy)
                return
            }
            nextFocusAt = dependencies.now().addingTimeInterval(3)
            do {
                let cancellation = try dependencies.launchFocus(target.id, !request.force) { [weak self] result in
                    self?.helperFinished(request, result: result)
                }
                if active?.token == request.token { cancelActive = cancellation }
                onUpdate?()
            } catch {
                complete(request, .failed(L10n.format("enf.focus", error.localizedDescription)))
            }
            return
        }
        let status = dependencies.select(target.id)
        if status != noErr {
            complete(request, .failed(L10n.format("enf.switch", target.id, status)))
        } else if dependencies.currentID() != target.id {
            complete(request, .failed(L10n.format("enf.unconfirmed", target.id)))
        } else {
            complete(request, .success)
        }
    }

    private func helperFinished(_ request: Request, result: FocusProcessResult) {
        guard active?.token == request.token else { return }
        guard cancelledManualToken != request.token else {
            complete(request, .busy)
            return
        }
        let config = dependencies.config()
        guard config.sourceID == request.target, request.force || config.enabled else {
            complete(request, .busy)
            return
        }
        switch result {
        case .cancelled: complete(request, .busy)
        case .timedOut: complete(request, .failed(L10n.text("enf.timeout")))
        case .exited(FocusHelper.secureExit): complete(request, .secureInput)
        case .exited(FocusHelper.staleExit): complete(request, .busy)
        case .exited(FocusHelper.missingExit): complete(request, .missingSource)
        case .exited(let status) where status != 0:
            complete(request, .failed(L10n.format("enf.helper-exit", status)))
        case .exited:
            let outcome: SwitchOutcome = dependencies.currentID() == request.target
                ? .success : .failed(L10n.format("enf.unconfirmed", request.target))
            complete(request, outcome)
        }
    }

    private func complete(_ request: Request, _ outcome: SwitchOutcome) {
        guard active?.token == request.token else { return }
        completionDepth += 1
        active = nil
        cancelActive = nil
        cancelledManualToken = nil
        onUpdate?()
        if !request.force && outcome != .busy { onAutomaticOutcome?(outcome) }
        request.finish?(outcome)
        completionDepth -= 1
        // Leave pending visible during callbacks so pause can cancel it, and a reentrant
        // selection can replace it. Start only the request still queued after they unwind.
        if completionDepth == 0, active == nil, let next = pending {
            pending = nil
            execute(next)
        }
    }
}
