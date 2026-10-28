import Foundation
import XCTest
@testable import keypin

final class LaunchPresentationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "app.keypin.launch-tests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testUpgradeFromVersionWithoutLaunchRecordStaysInMenuBar() {
        XCTAssertFalse(launch())
        XCTAssertEqual(defaults.string(forKey: LaunchPresentation.lastBuildKey), "22")
        XCTAssertTrue(launch(), "A later deliberate desktop launch still opens the window")
    }

    func testNewBuildIsQuietAndTheNextDesktopLaunchOpensNormally() {
        defaults.set("21", forKey: LaunchPresentation.lastBuildKey)
        XCTAssertFalse(launch())
        XCTAssertEqual(defaults.string(forKey: LaunchPresentation.lastBuildKey), "22")
        XCTAssertTrue(launch())
    }

    func testFirstLaunchAndConfigurationErrorsStillShowTheirWindow() {
        XCTAssertTrue(launch(requiresAttention: true))
        defaults.set("21", forKey: LaunchPresentation.lastBuildKey)
        XCTAssertTrue(launch(requiresAttention: true))
    }

    func testExplicitOpenAlwaysShowsWindowIncludingAfterAnUpgrade() {
        XCTAssertTrue(launch(mode: .explicitWindow))
        defaults.set("21", forKey: LaunchPresentation.lastBuildKey)
        XCTAssertTrue(launch(mode: .explicitWindow))
    }

    func testLoginLaunchIsQuietAndRecordsTheRunningBuild() {
        XCTAssertFalse(launch(mode: .background, requiresAttention: true))
        XCTAssertEqual(defaults.string(forKey: LaunchPresentation.lastBuildKey), "22")
        XCTAssertTrue(launch(), "A user opening an already installed build should see its window")
    }

    func testUnversionedDevelopmentBuildDoesNotSuppressDesktopWindowOrEraseHistory() {
        defaults.set("21", forKey: LaunchPresentation.lastBuildKey)
        XCTAssertTrue(launch(build: nil))
        XCTAssertTrue(launch(build: ""))
        XCTAssertEqual(defaults.string(forKey: LaunchPresentation.lastBuildKey), "21")
    }

    private func launch(mode: GUILaunchMode = .desktop, requiresAttention: Bool = false,
                        build: String? = "22") -> Bool {
        LaunchPresentation.recordLaunch(mode: mode, requiresAttention: requiresAttention,
                                        build: build, defaults: defaults)
    }
}
