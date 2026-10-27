import XCTest
@testable import keypin

final class RuntimeStateTests: XCTestCase {
    func testConflictPauseNeverClaimsKeepingAndHonorsSafetyPriorities() {
        let enabled = Config(sourceID: "ime", enabled: true)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "ime", targetAvailable: true,
                                           secureInput: false, conflictPaused: true), .conflictPaused)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "abc", targetAvailable: true,
                                           secureInput: true, conflictPaused: true), .secureInput)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "abc", targetAvailable: false,
                                           secureInput: false, conflictPaused: true), .missingSource)
        XCTAssertEqual(RuntimeState.resolve(config: Config(sourceID: "ime", enabled: false), currentID: "abc",
                                           targetAvailable: true, secureInput: false, conflictPaused: true), .paused)
    }

    func testPriorityReflectsWhetherInterventionCanActuallyRun() {
        let enabled = Config(sourceID: "ime", enabled: true)
        let paused = Config(sourceID: "ime", enabled: false)
        XCTAssertEqual(RuntimeState.resolve(config: Config(sourceID: nil, enabled: true), currentID: "abc", targetAvailable: false, secureInput: true), .setup)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "ime", targetAvailable: false, secureInput: true), .missingSource)
        XCTAssertEqual(RuntimeState.resolve(config: paused, currentID: "ime", targetAvailable: true, secureInput: true), .paused)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "ime", targetAvailable: true, secureInput: true), .secureInput)
        XCTAssertEqual(RuntimeState.resolve(config: paused, currentID: "abc", targetAvailable: true, secureInput: false, switching: true), .switching)
        XCTAssertEqual(RuntimeState.resolve(config: paused, currentID: "abc", targetAvailable: true, secureInput: true, switching: true), .secureInput)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "abc", targetAvailable: true, secureInput: false, switching: true, failed: true), .switching)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "ime", targetAvailable: true, secureInput: false, failed: true), .error)
        XCTAssertEqual(RuntimeState.resolve(config: paused, currentID: "abc", targetAvailable: true, secureInput: false, failed: true), .error)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "abc", targetAvailable: true, secureInput: false), .waiting)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "ime", targetAvailable: true, secureInput: false), .keeping)
        XCTAssertEqual(RuntimeState.resolve(config: enabled, currentID: "ime", targetAvailable: true, secureInput: false, isRunning: false), .stopped)
        XCTAssertEqual(RuntimeState.resolve(config: .empty, currentID: "abc", targetAvailable: false, secureInput: false, configurationError: true, isRunning: false), .error)
    }

    func testFollowingSystemDoesNotRequireARememberedTarget() {
        for sourceID in [nil, "", "removed"] as [String?] {
            let config = Config(sourceID: sourceID, enabled: false)
            XCTAssertEqual(RuntimeState.resolve(config: config, currentID: "abc", targetAvailable: false, secureInput: true), .paused)
            XCTAssertEqual(RuntimeState.resolve(config: config, currentID: "abc", targetAvailable: false, secureInput: false, configurationError: true), .error)
        }
    }

    func testAutomationStateNamesRoundTripWithoutDisplayText() throws {
        for state in RuntimeState.allCases {
            let data = try JSONEncoder().encode(state)
            XCTAssertEqual(try JSONDecoder().decode(RuntimeState.self, from: data), state)
        }
        XCTAssertEqual(RuntimeState.secureInput.rawValue, "secure_input")
        XCTAssertEqual(RuntimeState.missingSource.rawValue, "missing_source")
    }
}
