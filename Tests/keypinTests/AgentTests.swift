import Foundation
import XCTest
@testable import keypin

final class AgentTests: XCTestCase {
    private var home: URL!
    private var binary: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("keypin-agent-tests-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        binary = home.appendingPathComponent("KeyPin & <test>.app/Contents/MacOS/keypin")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture, never executed".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    func testPropertyListRoundTripsSpecialPathCharacters() throws {
        let data = try AgentController.agentPlist(binary: binary)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, "app.keypin")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [binary.path, "background"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    func testFreshInstallEnablesBeforeBootstrapAndCreatesExplicitCLICommand() throws {
        let runner = Runner(disabled: true)
        let agent = controller(runner)
        try agent.install(executable: binary)
        XCTAssertEqual(runner.calls.map { $0[0] }, ["print-disabled", "print", "enable", "bootstrap"])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: agent.symlink.path), binary.path)
        XCTAssertTrue(agent.isLoginEnabled)
    }

    func testLoadedGUIInstallDoesNotStopOrDuplicateCurrentApplication() throws {
        let runner = Runner(loaded: true)
        let agent = controller(runner)
        try agent.install(executable: binary, installCLICommand: false)
        XCTAssertEqual(runner.calls.map { $0[0] }, ["print-disabled", "print", "enable"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.symlink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.plist.path))
    }

    func testGUIUninstallCleansDurableStateWithoutStoppingCurrentApplication() throws {
        let runner = Runner(loaded: true)
        let agent = controller(runner)
        try writePlist(agent)
        runner.beforeCall = { arguments in
            if arguments[0] == "disable" {
                XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
            }
        }
        try agent.uninstall(stopRunningAgent: false)
        XCTAssertEqual(runner.calls.map { $0[0] }, ["disable"])
        XCTAssertFalse(agent.isLoginEnabled)
        XCTAssertTrue(agent.isLoaded)
    }

    func testCLIUninstallRemovesPlistBeforeBootoutCanTerminateJob() throws {
        let runner = Runner(loaded: true)
        let agent = controller(runner)
        try writePlist(agent)
        runner.beforeCall = { arguments in
            if arguments[0] == "bootout" {
                XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
                XCTAssertTrue(runner.disabled)
            }
        }
        try agent.uninstall()
        XCTAssertEqual(runner.calls.map { $0[0] }, ["disable", "print", "bootout"])
    }

    func testUninstallFailureIsReportedAfterPlistRemoval() throws {
        let runner = Runner(loaded: true)
        runner.failures["disable"] = 5
        let agent = controller(runner)
        try writePlist(agent)
        XCTAssertThrowsError(try agent.uninstall())
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
        XCTAssertEqual(runner.calls.map { $0[0] }, ["disable"])
    }

    func testUninstallNeverRecursivelyDeletesUnexpectedDirectory() throws {
        let runner = Runner()
        let agent = controller(runner)
        try FileManager.default.createDirectory(at: agent.plist, withIntermediateDirectories: true)
        let unrelated = agent.plist.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: unrelated)
        XCTAssertThrowsError(try agent.uninstall())
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCLIInstallPreservesExistingRegularFile() throws {
        let runner = Runner()
        let agent = controller(runner)
        try FileManager.default.createDirectory(at: agent.symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = Data("user command".utf8)
        try existing.write(to: agent.symlink)
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertEqual(try Data(contentsOf: agent.symlink), existing)
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
    }

    func testCLIInstallPreservesDifferentDanglingSymlink() throws {
        let runner = Runner()
        let agent = controller(runner)
        try FileManager.default.createDirectory(at: agent.symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = home.appendingPathComponent("user-owned-command")
        try FileManager.default.createSymbolicLink(at: agent.symlink, withDestinationURL: existing)
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: agent.symlink.path), existing.path)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCLIInstallAcceptsExistingSameTargetSymlink() throws {
        let runner = Runner(loaded: true)
        let agent = controller(runner)
        try FileManager.default.createDirectory(at: agent.symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: agent.symlink, withDestinationURL: binary)
        try agent.install(executable: binary)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: agent.symlink.path), binary.path)
        XCTAssertFalse(runner.calls.contains { $0[0] == "bootout" })
    }

    func testBootstrapFailureRestoresOldPlistAndDisabledOverride() throws {
        let runner = Runner(disabled: true)
        runner.failures["bootstrap"] = 5
        let agent = controller(runner)
        let old = Data("original plist bytes".utf8)
        try writePlist(agent, data: old)
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertEqual(try Data(contentsOf: agent.plist), old)
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: agent.symlink.path))
        XCTAssertTrue(runner.disabled)
        XCTAssertEqual(runner.calls.map { $0[0] }, ["print-disabled", "print", "enable", "bootstrap", "disable"])
    }

    func testEnableFailureDoesNotBootstrapAndRemovesNewInstallFiles() throws {
        let runner = Runner(disabled: true)
        runner.failures["enable"] = 5
        let agent = controller(runner)
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: agent.symlink.path))
        XCTAssertEqual(runner.calls.map { $0[0] }, ["print-disabled", "print", "enable"])
    }

    func testLoginStateDistinguishesInstalledDisabledAndLoaded() throws {
        let runner = Runner(disabled: true, loaded: true)
        let agent = controller(runner)
        try writePlist(agent)
        XCTAssertFalse(agent.isLoginEnabled)
        XCTAssertTrue(agent.isLoaded)
        runner.disabled = false
        XCTAssertTrue(agent.isLoginEnabled)
        try FileManager.default.removeItem(at: agent.plist)
        XCTAssertFalse(agent.isLoginEnabled)
    }

    func testUnknownStatusOutputDoesNotClaimEnabledOrWriteFiles() throws {
        let runner = Runner()
        runner.statusOutput = "format changed"
        let agent = controller(runner)
        try writePlist(agent)
        let old = try Data(contentsOf: agent.plist)
        XCTAssertFalse(agent.isLoginEnabled)
        XCTAssertThrowsError(try agent.install(executable: binary, installCLICommand: false))
        XCTAssertEqual(try Data(contentsOf: agent.plist), old)
        XCTAssertTrue(runner.calls.allSatisfy { $0[0] == "print-disabled" })
    }

    func testLoginStateSupportsBooleanAndWordDisabledOverrides() throws {
        let runner = Runner()
        let agent = controller(runner)
        try writePlist(agent)
        for (state, expected) in [("true", false), ("false", true), ("disabled", false), ("enabled", true)] {
            runner.statusOutput = "disabled services = {\n \"app.keypin\" => \(state)\n}"
            XCTAssertEqual(agent.isLoginEnabled, expected, state)
        }
    }

    func testUnknownDisabledOverrideValueDoesNotPretendEnabled() throws {
        let runner = Runner()
        let agent = controller(runner)
        try writePlist(agent)
        let original = try Data(contentsOf: agent.plist)
        runner.statusOutput = "disabled services = {\n \"app.keypin\" => unknown\n}"
        XCTAssertFalse(agent.isLoginEnabled)
        XCTAssertThrowsError(try agent.install(executable: binary, installCLICommand: false))
        XCTAssertEqual(try Data(contentsOf: agent.plist), original)
        XCTAssertTrue(runner.calls.allSatisfy { $0[0] == "print-disabled" })
    }

    func testMissingExecutableDoesNotChangeState() throws {
        let runner = Runner()
        let agent = controller(runner)
        XCTAssertThrowsError(try agent.install(executable: home.appendingPathComponent("missing")))
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
    }

    func testInstallationUsesOnlyCanonicalIdentityAndPaths() throws {
        let agent = controller(Runner())
        XCTAssertEqual(Agent.label, "app.keypin")
        XCTAssertEqual(agent.plist, home.appendingPathComponent("Library/LaunchAgents/app.keypin.plist"))
        XCTAssertEqual(agent.symlink, home.appendingPathComponent(".local/bin/keypin"))
    }

    func testCLIInstallRejectsDifferentTargetEvenWhenRegisteredInPlist() throws {
        let runner = Runner(loaded: true)
        let agent = controller(runner)
        let otherBinary = home.appendingPathComponent("Other KeyPin.app/Contents/MacOS/keypin")
        let original = try AgentController.agentPlist(binary: otherBinary)
        try writePlist(agent, data: original)
        try makeLink(agent.symlink, to: otherBinary.path)
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertEqual(try linkDestination(agent.symlink), otherBinary.path)
        XCTAssertEqual(try Data(contentsOf: agent.plist), original)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCLIInstallAcceptsRelativeLinkToSameExecutable() throws {
        let runner = Runner(loaded: true)
        let agent = controller(runner)
        let relative = "../../KeyPin & <test>.app/Contents/MacOS/keypin"
        try makeLink(agent.symlink, to: relative)
        try agent.install(executable: binary)
        XCTAssertEqual(try linkDestination(agent.symlink), relative)
    }

    func testBootstrapFailurePreservesPreexistingSameTargetCommand() throws {
        let runner = Runner(disabled: true)
        runner.failures["bootstrap"] = 5
        let agent = controller(runner)
        try makeLink(agent.symlink, to: binary.path)
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertEqual(try linkDestination(agent.symlink), binary.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
        XCTAssertTrue(runner.disabled)
    }

    func testCommandCreationFailureRestoresPlistWithoutCallingEnable() throws {
        let runner = Runner(disabled: true)
        var agent = controller(runner)
        let original = Data("original plist bytes".utf8)
        try writePlist(agent, data: original)
        let manager = FailingFileManager()
        manager.failDestinationOnce = agent.symlink
        agent.fileManager = manager
        XCTAssertThrowsError(try agent.install(executable: binary))
        XCTAssertEqual(try Data(contentsOf: agent.plist), original)
        XCTAssertNil(try? linkDestination(agent.symlink))
        XCTAssertEqual(runner.calls.map { $0[0] }, ["print-disabled", "print"])
    }

    func testRollbackPreservesConcurrentlyReplacedCommandAndReportsCleanupFailure() throws {
        let runner = Runner(disabled: true)
        runner.failures["bootstrap"] = 5
        let agent = controller(runner)
        let unrelated = home.appendingPathComponent("user-owned-command")
        runner.beforeCall = { arguments in
            if arguments[0] == "bootstrap" {
                do {
                    try FileManager.default.removeItem(at: agent.symlink)
                    try self.makeLink(agent.symlink, to: unrelated.path)
                } catch { XCTFail("Unable to set up concurrent change: \(error)") }
            }
        }
        XCTAssertThrowsError(try agent.install(executable: binary)) { error in
            let expected = L10n.format(
                "agent.rollback",
                L10n.format("agent.command-failed", "bootstrap", Int32(5)),
                L10n.format("agent.command-conflict", agent.symlink.path)
            )
            XCTAssertEqual(String(describing: error), expected)
        }
        XCTAssertEqual(try linkDestination(agent.symlink), unrelated.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plist.path))
        XCTAssertTrue(runner.disabled)
    }

    private func makeLink(_ path: URL, to destination: String) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: destination)
    }

    private func linkDestination(_ path: URL) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: path.path)
    }

    private final class FailingFileManager: FileManager, @unchecked Sendable {
        var failDestinationOnce: URL?
        override func createSymbolicLink(at url: URL, withDestinationURL destURL: URL) throws {
            if url == failDestinationOnce {
                failDestinationOnce = nil
                throw CocoaError(.fileWriteNoPermission)
            }
            try super.createSymbolicLink(at: url, withDestinationURL: destURL)
        }
    }

    private func controller(_ runner: Runner) -> AgentController {
        AgentController(homeDirectory: home, domain: "gui/99999", runLaunchctl: runner.run)
    }

    private func writePlist(_ agent: AgentController, data: Data? = nil) throws {
        try FileManager.default.createDirectory(at: agent.plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data ?? AgentController.agentPlist(binary: binary)).write(to: agent.plist)
    }

    private final class Runner {
        var disabled: Bool
        var loaded: Bool
        var calls: [[String]] = []
        var failures: [String: Int32] = [:]
        var statusOutput: String?
        var beforeCall: (([String]) -> Void)?

        init(disabled: Bool = false, loaded: Bool = false) {
            self.disabled = disabled
            self.loaded = loaded
        }

        func run(_ arguments: [String]) -> LaunchctlResult {
            calls.append(arguments)
            beforeCall?(arguments)
            if let status = failures[arguments[0]] { return LaunchctlResult(status: status) }
            switch arguments[0] {
            case "print-disabled":
                return LaunchctlResult(status: 0, output: statusOutput ?? "disabled services = {\n\t\"app.keypin\" => \(disabled)\n}")
            case "print": return LaunchctlResult(status: loaded ? 0 : 113)
            case "enable": disabled = false
            case "disable": disabled = true
            case "bootstrap": loaded = true
            case "bootout": loaded = false
            default: XCTFail("Unexpected launchctl operation: \(arguments)")
            }
            return LaunchctlResult(status: 0)
        }
    }
}
