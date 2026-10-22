import XCTest
@testable import keypin

@MainActor
final class UpdateTests: XCTestCase {
    // RFC 8032 public test vector, not a private key or a production verification key.
    private let publicKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
    private let info = AppBuildInfo(version: "1.0", build: 1)

    private func configuration() -> UpdateConfiguration {
        UpdateConfiguration(feed: UpdateConfiguration.releaseFeed, publicKey: publicKey,
                            bundleIdentifier: "app.keypin", isApplicationBundle: true)!
    }

    func testConfigurationRequiresCanonicalFeedAndPublicVerificationKey() {
        XCTAssertNotNil(configuration())
        for key in [nil, "", "not base64", Data(repeating: 0, count: 31).base64EncodedString(), publicKey + "\n"] {
            XCTAssertNil(UpdateConfiguration(feed: UpdateConfiguration.releaseFeed, publicKey: key,
                                             bundleIdentifier: "app.keypin", isApplicationBundle: true))
        }
        for feed in [nil, "", "http://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml",
                     "https://github.com/other/keypin/releases/latest/download/appcast.xml",
                     UpdateConfiguration.releaseFeed + "?override=1"] {
            XCTAssertNil(UpdateConfiguration(feed: feed, publicKey: publicKey,
                                             bundleIdentifier: "app.keypin", isApplicationBundle: true))
        }
    }

    func testCLIAndPreviewBundlesCannotSupplyProductionConfiguration() {
        XCTAssertNil(UpdateConfiguration(feed: UpdateConfiguration.releaseFeed, publicKey: publicKey,
                                         bundleIdentifier: "app.keypin", isApplicationBundle: false))
        XCTAssertNil(UpdateConfiguration(feed: UpdateConfiguration.releaseFeed, publicKey: publicKey,
                                         bundleIdentifier: "app.keypin.preview", isApplicationBundle: true))
    }

    func testUnconfiguredAndPreviewNeverInstantiateAnUpdaterOrAccessPreferences() {
        for preview in [false, true] {
            let model = UpdateViewModel(info: info, configuration: preview ? configuration() : nil, isPreview: preview) { _ in
                XCTFail("The real updater must not be created for a local or preview build")
                return Driver()
            }
            model.startIfAllowed(onboardingComplete: true)
            model.check()
            model.setAutomaticallyChecksForUpdates(true)
            model.setAutomaticallyDownloadsUpdates(true)
            XCTAssertEqual(model.state, .unconfigured)
            XCTAssertFalse(model.canCheckForUpdates)
            XCTAssertFalse(model.automaticallyChecksForUpdates)
            XCTAssertFalse(model.automaticallyDownloadsUpdates)
        }
    }

    func testStartWaitsForOnboardingAndRunsExactlyOnce() {
        let driver = Driver()
        var creations = 0
        let model = UpdateViewModel(info: info, configuration: configuration()) { _ in creations += 1; return driver }
        model.startIfAllowed(onboardingComplete: false)
        XCTAssertEqual(creations, 0)
        model.startIfAllowed(onboardingComplete: true)
        model.startIfAllowed(onboardingComplete: true)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(driver.starts, 1)
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.canCheckForUpdates)
        XCTAssertEqual(driver.checks, 0, "Starting should leave scheduling to Sparkle")
        XCTAssertEqual(driver.preferenceWrites, 0, "Starting must not overwrite saved preferences")
    }

    func testDriverFailureDisablesControlsWithoutRetryLoop() {
        let driver = Driver()
        driver.startError = URLError(.badURL)
        let model = makeModel(driver)
        model.startIfAllowed(onboardingComplete: true)
        model.check()
        model.setAutomaticallyChecksForUpdates(true)
        XCTAssertEqual(model.state, .failed)
        XCTAssertFalse(model.canCheckForUpdates)
        XCTAssertEqual(driver.starts, 1)
        XCTAssertEqual(driver.checks, 0)
        XCTAssertEqual(driver.preferenceWrites, 0)
    }

    func testManualCheckUsesSparkleAndBusyStatePreventsDuplicateChecks() {
        let driver = Driver()
        let model = makeModel(driver)
        model.check()
        model.check()
        XCTAssertEqual(driver.checks, 1)
        XCTAssertFalse(model.canCheckForUpdates)
        driver.canCheckForUpdates = true
        driver.onChange?()
        model.check()
        XCTAssertEqual(driver.checks, 2)
    }

    func testSettingsComeFromDriverAndDoNotResetOnReopening() {
        let driver = Driver()
        driver.automaticallyChecksForUpdates = true
        driver.automaticallyDownloadsUpdates = true
        driver.preferenceWrites = 0
        let model = makeModel(driver)
        XCTAssertTrue(model.automaticallyChecksForUpdates)
        XCTAssertTrue(model.automaticallyDownloadsUpdates)
        model.startIfAllowed(onboardingComplete: true)
        XCTAssertEqual(driver.preferenceWrites, 0)
        model.setAutomaticallyChecksForUpdates(false)
        XCTAssertFalse(model.automaticallyChecksForUpdates)
        XCTAssertTrue(model.automaticallyDownloadsUpdates, "Disabling checks preserves the download preference")
        let previousWrites = driver.preferenceWrites
        model.setAutomaticallyDownloadsUpdates(false)
        XCTAssertEqual(driver.preferenceWrites, previousWrites, "Disabled child input must not change a saved preference")
        model.setAutomaticallyChecksForUpdates(true)
        model.setAutomaticallyDownloadsUpdates(false)
        XCTAssertFalse(model.automaticallyDownloadsUpdates)
    }

    func testExternalSparkleSettingsAndGentleReminderReachBothViews() {
        let driver = Driver()
        let model = makeModel(driver)
        driver.automaticallyChecksForUpdates = true
        driver.automaticallyDownloadsUpdates = true
        driver.pendingUpdateVersion = "2.0"
        driver.onChange?()
        XCTAssertTrue(model.automaticallyChecksForUpdates)
        XCTAssertTrue(model.automaticallyDownloadsUpdates)
        XCTAssertEqual(model.pendingUpdateVersion, "2.0")
        model.check()
        XCTAssertEqual(driver.checks, 1, "Reviewing a pending update returns to the standard Sparkle UI")
        driver.pendingUpdateVersion = nil
        driver.onChange?()
        XCTAssertNil(model.pendingUpdateVersion)
    }

    func testLaunchAgentDoesNotRaceSparkleAfterSuccessfulExit() throws {
        let data = try AgentController.agentPlist(binary: URL(fileURLWithPath: "/Applications/KeyPin.app/Contents/MacOS/keypin"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["KeepAlive"] as? [String: Bool], ["SuccessfulExit": false])
    }

    private func makeModel(_ driver: Driver) -> UpdateViewModel {
        let model = UpdateViewModel(info: info, configuration: configuration()) { _ in driver }
        model.startIfAllowed(onboardingComplete: true)
        return model
    }

    private final class Driver: UpdateDriving {
        var starts = 0
        var checks = 0
        var preferenceWrites = 0
        var startError: Error?
        var canCheckForUpdates = true
        var automaticallyChecksForUpdates = false { didSet { preferenceWrites += 1 } }
        var automaticallyDownloadsUpdates = false { didSet { preferenceWrites += 1 } }
        var pendingUpdateVersion: String?
        var onChange: (() -> Void)?
        func start() throws { starts += 1; if let startError { throw startError } }
        func checkForUpdates() { checks += 1; canCheckForUpdates = false; onChange?() }
    }
}
