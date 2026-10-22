import Foundation
import XCTest
@testable import keypin

final class AutomationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keypin-automation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func makeAutomation(running: Bool = true, current: String = "abc", secure: Bool = false) -> Automation {
        let path = directory!
        return Automation(services: AutomationServices(
            load: { try ConfigStore.loadChecked(from: path) },
            update: { try ConfigStore.mutate(in: path, edit: $0) },
            choices: { [InputChoice(id: "abc", name: "ABC")] },
            current: { InputChoice(id: current, name: current.uppercased()) },
            running: { running }, secureInput: { secure }, loginEnabled: { true }
        ))
    }

    private func write(enabled: Bool, source: String? = "abc", completed: Bool = true) throws {
        try ConfigStore.write(Config(sourceID: source, enabled: enabled, language: "ja", onboardingCompleted: completed), to: directory)
    }

    func testParserSupportsExplicitStatusAndJSONInEitherPosition() throws {
        for words in [[], ["status"], ["status", "--json"], ["--json", "status"], ["--json"]] {
            let request = try CLIRequest.parse(words)
            XCTAssertEqual(request.command, .status)
            XCTAssertEqual(request.json, words.contains("--json"))
        }
        for name in ["pause", "resume", "toggle", "list", "apply", "open", "uninstall"] {
            XCTAssertEqual(try CLIRequest.parse([name, "--json"]).command.rawValue, name)
        }
        XCTAssertEqual(try CLIRequest.parse(["set", "--json", "abc"]).sourceID, "abc")
        XCTAssertEqual(try CLIRequest.parse(["--json", "install", "abc"]).sourceID, "abc")
    }

    func testParserRejectsUnknownFlagsAndTrailingOperandsBeforeAnyAction() {
        for words in [["pause", "now"], ["resume", "--force"], ["toggle", "extra", "--json"],
                      ["set"], ["install"], ["set", "abc", "extra"], ["status", "extra"],
                      ["list", "extra"], ["open", "extra"], ["apply", "extra"], ["uninstall", "extra"],
                      ["wat"], ["--json", "--json"], ["set", "--bad"], ["help", "--json"]] {
            XCTAssertThrowsError(try CLIRequest.parse(words), "\(words)") {
                XCTAssertEqual(($0 as? AutomationFailure)?.code, "invalid_arguments")
            }
        }
    }

    func testPausePreservesChoiceLanguageAndSetupAndDoesNotSwitch() throws {
        try write(enabled: true, completed: false)
        let result = try makeAutomation(current: "other").setKeeping(.pause)
        XCTAssertFalse(result.enabled)
        XCTAssertEqual(result.current.id, "other")
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory),
                       Config(sourceID: "abc", enabled: false, language: "ja", onboardingCompleted: false))
    }

    func testResumeAndToggleDoNotClaimStoppedApplicationIsRunning() throws {
        try write(enabled: false)
        let automation = makeAutomation(running: false)
        let resumed = try automation.setKeeping(.resume)
        XCTAssertTrue(resumed.enabled)
        XCTAssertFalse(resumed.running)
        XCTAssertTrue(resumed.loginEnabled, "A login item alone is not evidence that the GUI is running")
        XCTAssertEqual(resumed.state, .stopped)
        XCTAssertFalse(try automation.setKeeping(.toggle).enabled)
        XCTAssertTrue(try automation.setKeeping(.toggle).enabled)
    }

    func testEnableRejectsMissingAndUnavailableTargetsWithoutChangingBytes() throws {
        for source: String? in [nil, "missing"] {
            try write(enabled: false, source: source)
            let file = directory.appendingPathComponent("config.json")
            let before = try Data(contentsOf: file)
            for command in [CLIRequest.Command.resume, .toggle] {
                XCTAssertThrowsError(try makeAutomation().setKeeping(command)) {
                    XCTAssertEqual(($0 as? AutomationFailure)?.code, source == nil ? "no_target" : "missing_source")
                }
                XCTAssertEqual(try Data(contentsOf: file), before)
            }
        }
    }

    func testToggleOffAllowsUnavailableTarget() throws {
        try write(enabled: true, source: "missing")
        XCTAssertFalse(try makeAutomation().setKeeping(.toggle).enabled)
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory).sourceID, "missing")
    }

    func testConcurrentTogglesAreAtomicAndRetainOtherFields() throws {
        try write(enabled: false)
        let automation = makeAutomation()
        let errors = NSLock()
        var failureCount = 0
        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            do { _ = try automation.setKeeping(.toggle) }
            catch { errors.lock(); failureCount += 1; errors.unlock() }
        }
        XCTAssertEqual(failureCount, 0)
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory),
                       Config(sourceID: "abc", enabled: false, language: "ja", onboardingCompleted: true))
    }

    func testCorruptConfigurationFailsClosedWithMachineReadableError() throws {
        let file = directory.appendingPathComponent("config.json")
        let bytes = Data("{broken".utf8)
        try bytes.write(to: file)
        for command in [CLIRequest.Command.pause, .resume, .toggle] {
            XCTAssertThrowsError(try makeAutomation().setKeeping(command)) { error in
                let failure = error as? AutomationFailure
                XCTAssertEqual(failure?.code, "invalid_config")
                let response = AutomationResponse(ok: false, command: command.rawValue, error: failure)
                let json = try? JSONSerialization.jsonObject(with: Data(try! response.encoded().utf8)) as? [String: Any]
                XCTAssertEqual(json?["ok"] as? Bool, false)
                XCTAssertEqual((json?["error"] as? [String: String])?["code"], "invalid_config")
            }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
        XCTAssertThrowsError(try makeAutomation().status())
    }

    func testStatusReflectsSecureInputAndPendingSwitchAndHasStableJSON() throws {
        try write(enabled: true)
        XCTAssertEqual(try makeAutomation(current: "other").status().state, .waiting)
        let secure = try makeAutomation(current: "other", secure: true).status()
        XCTAssertEqual(secure.state, .secureInput)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(AutomationResponse(ok: true, command: "status", status: secure).encoded().utf8)) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["ok"] as? Bool, true)
        let status = try XCTUnwrap(json["status"] as? [String: Any])
        XCTAssertEqual(status["state"] as? String, "secure_input")
        XCTAssertEqual(status["enabled"] as? Bool, true)
        XCTAssertEqual(status["running"] as? Bool, true)
    }

    func testReadOnlyStatusDoesNotWriteConfigurationOrCreateAFile() throws {
        _ = try makeAutomation(running: false).status()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }
}
