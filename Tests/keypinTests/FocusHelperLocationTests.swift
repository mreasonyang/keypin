import Foundation
import XCTest
@testable import keypin

final class FocusHelperLocationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keypin-helper-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testPackagedAppSelectsOnlyNestedHelperExecutable() throws {
        let application = try makeApplication()
        let executable = try makeHelper(in: application)
        XCTAssertEqual(try FocusHelperLocation.executable(in: application), executable)
        XCTAssertNotEqual(executable, application.executableURL)
        XCTAssertEqual(Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())?.bundleIdentifier,
                       "app.keypin.focus-helper")
    }

    func testMissingHelperNeverFallsBackToMainExecutable() throws {
        let application = try makeApplication()
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: application.executableURL!.path))
        XCTAssertThrowsError(try FocusHelperLocation.executable(in: application)) {
            XCTAssertEqual($0 as? FocusHelperLocation.Failure, .helperUnavailable)
        }
    }

    func testSourceAndNonProductionBundlesRejectFocusWorkaround() throws {
        for (name, identifier) in [("Source.bundle", "app.keypin"), ("Preview.app", "app.keypin.preview")] {
            let bundle = try makeApplication(name: name, identifier: identifier)
            XCTAssertThrowsError(try FocusHelperLocation.executable(in: bundle)) {
                XCTAssertEqual($0 as? FocusHelperLocation.Failure, .applicationRequired)
            }
        }
    }

    func testHelperUsingGUIIdentityIsRejected() throws {
        let application = try makeApplication()
        _ = try makeHelper(in: application, identifier: "app.keypin")
        XCTAssertThrowsError(try FocusHelperLocation.executable(in: application)) {
            XCTAssertEqual($0 as? FocusHelperLocation.Failure, .helperUnavailable)
        }
    }

    func testHelperWithUnexpectedExecutableNameIsRejected() throws {
        let application = try makeApplication()
        _ = try makeHelper(in: application, executableName: "keypin")
        XCTAssertThrowsError(try FocusHelperLocation.executable(in: application))
    }

    func testNonExecutableHelperAndSymlinkToMainAreRejected() throws {
        let application = try makeApplication()
        let executable = try makeHelper(in: application)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        XCTAssertThrowsError(try FocusHelperLocation.executable(in: application))
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: application.executableURL!)
        XCTAssertThrowsError(try FocusHelperLocation.executable(in: application))
    }

    func testHelperAllowsOnlyExplicitFocusInvocation() {
        let identity = FocusHelperLocation.bundleIdentifier
        XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: ["focus", "fixture.source"]),
                       .focus(sourceID: "fixture.source"))
        XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: ["focus", "fixture.source", "--automatic"]),
                       .focus(sourceID: "fixture.source"))
        for arguments in [[], ["gui"], ["background"], ["status"], ["--help"], ["preview"], ["focus"], ["focus", ""],
                          ["focus", "fixture.source", "--unknown"], ["focus", "fixture.source", "--automatic", "extra"]] {
            XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: arguments), .reject)
        }
    }

    func testApplicationAndSourceExecutableCannotBecomeSameIdentityFocusHelper() {
        for identity: String? in [nil, "app.keypin", "app.keypin.preview"] {
            XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: ["focus", "fixture.source"]), .reject)
            XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: []), .application)
            XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: ["gui"]), .application)
            XCTAssertEqual(FocusHelperInvocation.resolve(bundleIdentifier: identity, arguments: ["status", "--json"]), .application)
        }
    }

    private func makeApplication(name: String = "KeyPin.app", identifier: String = "app.keypin") throws -> Bundle {
        let applicationURL = directory.appendingPathComponent(name)
        try makeBundle(at: applicationURL, identifier: identifier, executableName: "keypin")
        return try XCTUnwrap(Bundle(url: applicationURL))
    }

    @discardableResult
    private func makeHelper(in application: Bundle, identifier: String = "app.keypin.focus-helper",
                            executableName: String = "keypin-focus") throws -> URL {
        let helperURL = application.bundleURL.appendingPathComponent(FocusHelperLocation.bundlePath)
        return try makeBundle(at: helperURL, identifier: identifier, executableName: executableName)
    }

    @discardableResult
    private func makeBundle(at url: URL, identifier: String, executableName: String) throws -> URL {
        let executable = url.appendingPathComponent("Contents/MacOS/\(executableName)")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture, never executed".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let info = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": identifier, "CFBundleExecutable": executableName]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return executable
    }
}
