import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var panelWindow: NSWindow?
    private let instanceLock = InstanceLock()
    var previewUpdates: UpdateViewModel?
    private lazy var updates = previewUpdates ?? UpdateViewModel(
        info: AppBuildInfo(bundle: Bundle.main), configuration: UpdateConfiguration(bundle: Bundle.main), isPreview: model.isPreview,
        makeDriver: { [weak self] configuration in
            SparkleUpdateDriver(configuration: configuration, allowsUpdates: { [weak self] in
                self?.model.showsOnboarding == false
            })
        }
    )
    private var editingMenu: NSMenu?
    private var editingMenuItem: NSMenuItem?
    private var editingCommands: [(item: NSMenuItem, key: String)] = []
    private var editingMenuLanguage: String?
    var launchMode: GUILaunchMode = .background
    var model = AppModel.shared
    var previewSettings = false
    var previewAbout = false
    var previewCompact = false
    var previewReduced = false
    var previewLegacyAppearance = false
    var previewPopover = false
    var previewHeight: CGFloat?

    private var maximumPanelHeight: CGFloat { previewHeight ?? 580 }

    func applicationWillTerminate(_ notification: Notification) {
        guard !model.isPreview else { return }
        RuntimeDiagnostics.shared.finish()
        DiagnosticLogStore.shared.flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 128, height: 128)
            NSApp.applicationIconImage = icon
        }
        guard adoptExistingInstance() == false else { return }
        configurePopover()
        configureStatusItem()
        model.start()
        let openWindowOnLaunch = model.isPreview ? true : LaunchPresentation.recordLaunch(
            mode: launchMode, requiresAttention: model.showsOnboarding || model.configError,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
        // Lifetime belongs to the GUI, never the About view, CLI, or focus helper.
        // Keep the instance lock until process exit; Sparkle waits for termination
        // before installing/reopening, and LaunchAgent only restarts failed exits.
        model.$showsOnboarding.removeDuplicates().sink { [weak self] showing in
            self?.updates.startIfAllowed(onboardingComplete: !showing)
        }.store(in: &cancellables)
        updates.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshStatusItem()
        }.store(in: &cancellables)
        configureEditingMenu()
        refreshStatusItem()
        if !model.isPreview { DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openFromOutside),
            name: ConfigStore.openWindow,
            object: nil,
            suspensionBehavior: .deliverImmediately
        ) }
        if previewPopover {
            // Debug previews only: show the real menu-bar popover once the status item is placed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.togglePopover() }
        } else if openWindowOnLaunch {
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func adoptExistingInstance() -> Bool {
        guard !model.isPreview else { return false }
        do {
            if try instanceLock.acquire(at: ConfigStore.directory.appendingPathComponent("gui.lock")) { return false }
            DistributedNotificationCenter.default().post(name: ConfigStore.openWindow, object: nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        NSApp.terminate(nil)
        return true
    }

    private func configurePopover() {
        let host = NSHostingController(rootView: Panel(model: model, updates: updates, inWindow: false, maximumHeight: maximumPanelHeight)
            .environment(\.previewReduceTransparency, previewReduced)
            .environment(\.previewLegacyAppearance, previewLegacyAppearance))
        // The panel measures itself; the popover follows its ideal height as pages change.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        // A status-item popover otherwise inherits the anchor's appearance,
        // which can differ from the isolated preview's requested light/dark mode.
        if model.isPreview { popover.appearance = NSApp.appearance }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
                self?.refreshEditingMenuTitles()
                self?.panelWindow?.title = L10n.text("app.name")
            }
            .store(in: &cancellables)
        if !model.isPreview {
            DistributedNotificationCenter.default()
                .publisher(for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.model.refreshSourceArtwork() }
                .store(in: &cancellables)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Accessory apps have no visible application menu, but AppKit still needs
    /// these key equivalents to send standard editing actions to the first responder.
    private func configureEditingMenu() {
        let menu = NSMenu()
        let edit = NSMenu()
        let editItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)

        let commands: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("menu.undo", Selector(("undo:")), "z", .command),
            ("menu.redo", Selector(("redo:")), "z", [.command, .shift]),
            ("menu.cut", #selector(NSText.cut(_:)), "x", .command),
            ("menu.copy", #selector(NSText.copy(_:)), "c", .command),
            ("menu.paste", #selector(NSText.paste(_:)), "v", .command),
            ("menu.select-all", #selector(NSText.selectAll(_:)), "a", .command)
        ]
        for (index, command) in commands.enumerated() {
            if index == 2 || index == 5 { edit.addItem(.separator()) }
            let (key, action, equivalent, modifiers) = command
            let item = NSMenuItem(title: "", action: action, keyEquivalent: equivalent)
            item.keyEquivalentModifierMask = modifiers
            // A nil target preserves native validation, text selection and undo routing.
            item.target = nil
            edit.addItem(item)
            editingCommands.append((item, key))
        }
        editingMenu = edit
        editingMenuItem = editItem
        refreshEditingMenuTitles(force: true)
        NSApp.mainMenu = menu
    }

    private func refreshEditingMenuTitles(force: Bool = false) {
        guard let editingMenu, force || editingMenuLanguage != model.language else { return }
        editingMenuLanguage = model.language
        let title = L10n.text("menu.edit")
        editingMenu.title = title
        editingMenuItem?.title = title
        for command in editingCommands { command.item.title = L10n.text(command.key) }
    }

    private func refreshStatusItem() {
        statusItem?.button?.image = model.currentSourceIcon
        statusItem?.button?.title = ""
        statusItem?.button?.appearsDisabled = model.runtimeState == .paused
        let status = L10n.format("app.tooltip", L10n.text(model.statusKey), model.menuSourceName)
        let updateNotice = updates.pendingUpdateVersion.map { L10n.format("about.update.reminder", $0) }
        statusItem?.button?.toolTip = [status, updateNotice].compactMap { $0 }.joined(separator: "\n")
        statusItem?.button?.setAccessibilityLabel(L10n.text("app.name"))
        statusItem?.button?.setAccessibilityValue(statusItem?.button?.toolTip)
    }

    @objc private func openFromOutside() {
        DispatchQueue.main.async { [weak self] in self?.showWindow() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.refreshSourceArtwork()
        model.refreshLogin()
        // 附属应用的弹出层如果不成为关键窗口，开关会画成灰色，看起来像关着。
        activateApplication()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showWindow() {
        if panelWindow == nil {
            let page: PanelPage = previewAbout ? .about : (previewSettings ? .settings : .main)
            let host = NSHostingController(rootView: Panel(model: model, updates: updates, inWindow: !previewCompact, page: page,
                                                          maximumHeight: maximumPanelHeight)
                .environment(\.previewReduceTransparency, previewReduced)
                .environment(\.previewLegacyAppearance, previewLegacyAppearance))
            // The shared header already reserves space for window controls. Don't add a second title-bar inset.
            if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
            // Fit the window to the panel's ideal size and follow it when pages change.
            host.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
            let window = NSWindow(contentViewController: host)
            window.title = L10n.text("app.name")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = false
            window.center()
            panelWindow = window
        }
        model.refreshSourceArtwork()
        model.refreshLogin()
        activateApplication()
        panelWindow?.makeKeyAndOrderFront(nil)
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
    }

}
