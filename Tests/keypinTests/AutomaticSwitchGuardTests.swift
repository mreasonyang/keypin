import XCTest
@testable import keypin

final class AutomaticSwitchGuardTests: XCTestCase {
    private func conflict(_ guardState: inout AutomaticSwitchGuard, at start: Double) {
        for offset in 0..<3 {
            XCTAssertTrue(guardState.permitsAttempt(at: start + Double(offset)))
            guardState.observeCurrent(matchesTarget: true, at: start + Double(offset) + 0.1)
        }
        XCTAssertFalse(guardState.permitsAttempt(at: start + 3))
    }

    func testSuccessfulEchoesDoNotHideARepeatedFight() {
        var state = AutomaticSwitchGuard()
        state.updateContext(target: "ime", enabled: true, appPID: 1)
        conflict(&state, at: 0)
        XCTAssertTrue(state.isPaused(at: 3))
        for time in [4.0, 6, 8, 10, 12, 14, 16, 17.99] {
            XCTAssertFalse(state.permitsAttempt(at: time))
        }
        XCTAssertFalse(state.isPaused(at: 18))
        XCTAssertTrue(state.permitsAttempt(at: 18))
    }

    func testPersistentConflictDoublesPauseUpToTwoMinutes() {
        var state = AutomaticSwitchGuard()
        var start = 0.0
        for pause in [15.0, 30, 60, 120, 120] {
            conflict(&state, at: start)
            let deadline = start + 3 + pause
            XCTAssertTrue(state.isPaused(at: deadline - 0.01))
            XCTAssertFalse(state.isPaused(at: deadline))
            start = deadline
        }
    }

    func testThirtySecondsOfObservedStabilityRefillsBudgetAndPauseDuration() {
        var state = AutomaticSwitchGuard()
        conflict(&state, at: 0)
        state.observeCurrent(matchesTarget: true, at: 4)
        state.observeCurrent(matchesTarget: true, at: 34)
        conflict(&state, at: 35)
        XCTAssertTrue(state.isPaused(at: 52.99))
        XCTAssertFalse(state.isPaused(at: 53))
    }

    func testSparseCorrectionsDoNotAccumulateIntoAConflict() {
        var state = AutomaticSwitchGuard()
        for time in stride(from: 0.0, through: 100, by: 10) {
            XCTAssertTrue(state.permitsAttempt(at: time))
            XCTAssertFalse(state.isPaused(at: time))
        }
    }

    func testOwnHelperAndUnrelatedSettingsDoNotClearPause() {
        var state = AutomaticSwitchGuard()
        state.updateContext(target: "ime", enabled: true, appPID: 1)
        conflict(&state, at: 0)
        state.updateContext(target: "ime", enabled: true, appPID: nil)
        state.updateContext(target: "ime", enabled: true, appPID: 1)
        XCTAssertFalse(state.permitsAttempt(at: 4))
    }

    func testNewAppTargetOrExplicitPauseResetsTheConflict() {
        for change in ["app", "target", "pause", "manual"] {
            var state = AutomaticSwitchGuard()
            state.updateContext(target: "ime", enabled: true, appPID: 1)
            conflict(&state, at: 0)
            switch change {
            case "app": state.updateContext(target: "ime", enabled: true, appPID: 2)
            case "target": state.updateContext(target: "other", enabled: true, appPID: 1)
            case "pause":
                state.updateContext(target: "ime", enabled: false, appPID: 1)
                state.updateContext(target: "ime", enabled: true, appPID: 1)
            default: state.reset()
            }
            XCTAssertTrue(state.permitsAttempt(at: 4), change)
            XCTAssertFalse(state.isPaused(at: 4), change)
        }
    }
}
