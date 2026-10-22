import Foundation
import Combine
import Sparkle

struct AppBuildInfo: Sendable {
    let version: String?
    let build: Int?
    let minimumSystemVersion: String

    init(version: String?, build: Int?, minimumSystemVersion: String = "26.0") {
        self.version = version
        self.build = build
        self.minimumSystemVersion = minimumSystemVersion
    }

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init)
        minimumSystemVersion = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "26.0"
    }

    static var architecture: String {
        #if arch(arm64)
        "Apple silicon"
        #elseif arch(x86_64)
        "Intel"
        #else
        "—"
        #endif
    }
}

/// Packaging supplies only a public verification key. An incomplete local build
/// never creates Sparkle, accesses its preferences, or starts an update request.
struct UpdateConfiguration: Equatable {
    static let releaseFeed = "https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml"
    let feedURL: URL

    init?(feed: String?, publicKey: String?, bundleIdentifier: String?, isApplicationBundle: Bool) {
        guard isApplicationBundle, bundleIdentifier == "app.keypin", feed == Self.releaseFeed,
              let publicKey, let decoded = Data(base64Encoded: publicKey), decoded.count == 32,
              decoded.base64EncodedString() == publicKey,
              let feedURL = URL(string: Self.releaseFeed) else { return nil }
        self.feedURL = feedURL
    }

    init?(bundle: Bundle) {
        self.init(feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                  publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  bundleIdentifier: bundle.bundleIdentifier,
                  isApplicationBundle: bundle.bundleURL.pathExtension == "app")
    }
}

/// The production implementation delegates every update operation to Sparkle.
/// Tests inject a driver and never instantiate Sparkle or touch user preferences.
@MainActor
protocol UpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var pendingUpdateVersion: String? { get }
    var onChange: (() -> Void)? { get set }
    func start() throws
    func checkForUpdates()
}

@MainActor
final class UpdateViewModel: ObservableObject {
    enum State: Equatable { case unconfigured, ready, failed }

    let info: AppBuildInfo
    @Published private(set) var state: State = .unconfigured
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var pendingUpdateVersion: String?
    private let configuration: UpdateConfiguration?
    private let isPreview: Bool
    private let makeDriver: @MainActor (UpdateConfiguration) -> any UpdateDriving
    private var driver: (any UpdateDriving)?
    private var attemptedStart = false

    init(info: AppBuildInfo, configuration: UpdateConfiguration? = nil, isPreview: Bool = false,
         makeDriver: @escaping @MainActor (UpdateConfiguration) -> any UpdateDriving = { SparkleUpdateDriver(configuration: $0) }) {
        self.info = info
        self.configuration = configuration
        self.isPreview = isPreview
        self.makeDriver = makeDriver
    }

    /// Called only by the GUI owner after it acquires its instance lock and setup
    /// is complete. Reopening the popover/about page cannot create another updater.
    func startIfAllowed(onboardingComplete: Bool) {
        guard onboardingComplete, !isPreview, !attemptedStart, let configuration else { return }
        attemptedStart = true
        let driver = makeDriver(configuration)
        self.driver = driver
        driver.onChange = { [weak self] in self?.refresh() }
        do {
            try driver.start()
            state = .ready
            refresh()
        } catch {
            driver.onChange = nil
            self.driver = nil
            state = .failed
        }
    }

    func check() {
        guard state == .ready, let driver, driver.canCheckForUpdates else { return }
        driver.checkForUpdates()
        refresh()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard state == .ready, let driver else { return }
        driver.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard state == .ready, let driver, driver.automaticallyChecksForUpdates else { return }
        driver.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    private func refresh() {
        guard state == .ready, let driver else { return }
        canCheckForUpdates = driver.canCheckForUpdates
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = driver.automaticallyDownloadsUpdates
        pendingUpdateVersion = driver.pendingUpdateVersion
    }
}

@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriving, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private let configuration: UpdateConfiguration
    private let allowsUpdates: () -> Bool
    private var controller: SPUStandardUpdaterController!
    private var observations = Set<AnyCancellable>()
    var onChange: (() -> Void)?
    private(set) var pendingUpdateVersion: String?

    init(configuration: UpdateConfiguration, allowsUpdates: @escaping () -> Bool = { true }) {
        self.configuration = configuration
        self.allowsUpdates = allowsUpdates
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates).sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    func start() throws { try controller.updater.start() }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    // Keep the feed bound to the public repository even if a previous build left
    // an SUFeedURL user-default override. Archive/feed signatures are verified by Sparkle.
    func feedURLString(for updater: SPUUpdater) -> String? { configuration.feedURL.absoluteString }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard allowsUpdates() else {
            throw NSError(domain: "KeyPin.Updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.text("about.update.setup")])
        }
    }

    // A menu-bar utility must never take focus from the app the user is typing in.
    // The status item and About page expose a gentle reminder; clicking Check / Review
    // opens Sparkle's standard UI and resumes any already downloaded update.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            pendingUpdateVersion = update.displayVersionString
            onChange?()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { clearReminder() }
    func standardUserDriverWillFinishUpdateSession() { clearReminder() }

    private func clearReminder() {
        pendingUpdateVersion = nil
        onChange?()
    }
}
