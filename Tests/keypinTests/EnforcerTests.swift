import Foundation
import XCTest
@testable import keypin

final class EnforcerTests: XCTestCase {
    private final class Harness {
        var config = Config(sourceID: "CJK-A", enabled: false)
        var secure = false
        var current = "latin"
        var missing: Set<String> = []
        var selectionStatus: Int32 = 0
        var selectionActuallyChanges = true
        var selected: [String] = []
        var launched: [String] = []
        var automatic: [Bool] = []
        var cancelled: [String] = []
        var completions: [(FocusProcessResult) -> Void] = []
        var launchError: Error?

        func makeEnforcer() -> Enforcer {
            Enforcer(dependencies: EnforcementDependencies(
                config: { self.config },
                secureInput: { self.secure },
                currentID: { self.current },
                find: { id in
                    self.missing.contains(id) ? nil : EnforcementTarget(id: id, requiresFocus: id.hasPrefix("CJK"))
                },
                select: { id in
                    self.selected.append(id)
                    if self.selectionStatus == 0 && self.selectionActuallyChanges { self.current = id }
                    return self.selectionStatus
                },
                launchFocus: { id, automatic, completion in
                    if let error = self.launchError { throw error }
                    self.launched.append(id)
                    self.automatic.append(automatic)
                    self.completions.append(completion)
                    return { self.cancelled.append(id) }
                },
                now: { Date(timeIntervalSince1970: 1_000) }
            ))
        }
    }

    func testRapidManualChoiceQueuesLatestEvenWhenKeepingIsOff() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcomes: [SwitchOutcome] = []
        enforcer.enforce(force: true) { outcomes.append($0) }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { outcomes.append($0) }
        XCTAssertEqual(h.launched, ["CJK-A"])
        XCTAssertEqual(h.cancelled, ["CJK-A"])
        h.completions[0](.cancelled)
        XCTAssertEqual(h.launched, ["CJK-A", "CJK-B"])
        h.current = "CJK-B"
        h.completions[1](.exited(0))
        XCTAssertEqual(outcomes, [.busy, .success])
    }

    func testOnlyLatestQueuedChoiceRunsAndAllCallbacksComplete() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcomes: [String: SwitchOutcome] = [:]
        enforcer.enforce(force: true) { outcomes["A"] = $0 }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { outcomes["B"] = $0 }
        h.config.sourceID = "CJK-C"
        enforcer.enforce(force: true) { outcomes["C"] = $0 }
        XCTAssertEqual(outcomes["B"], .busy)
        h.completions[0](.cancelled)
        XCTAssertEqual(h.launched, ["CJK-A", "CJK-C"])
        h.current = "CJK-C"
        h.completions[1](.exited(0))
        XCTAssertEqual(outcomes, ["A": .busy, "B": .busy, "C": .success])
    }

    func testPassiveNotificationDoesNotReplaceQueuedManualSelection() {
        let h = Harness()
        h.config.enabled = true
        let enforcer = h.makeEnforcer()
        var latest: SwitchOutcome?
        enforcer.enforce(force: true)
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { latest = $0 }
        enforcer.enforce(force: false)
        h.completions[0](.cancelled)
        XCTAssertEqual(h.automatic, [false, false])
        h.current = "CJK-B"
        h.completions[1](.exited(0))
        XCTAssertEqual(latest, .success)
    }

    func testSecureInputDoesNotLaunchOrSelect() {
        let h = Harness()
        h.secure = true
        let enforcer = h.makeEnforcer()
        var outcome: SwitchOutcome?
        enforcer.enforce(force: true) { outcome = $0 }
        XCTAssertEqual(outcome, .secureInput)
        XCTAssertTrue(h.launched.isEmpty)
        XCTAssertTrue(h.selected.isEmpty)
    }

    func testMissingSourceIsAnExplicitFailure() {
        let h = Harness()
        h.missing.insert("CJK-A")
        let enforcer = h.makeEnforcer()
        var outcome: SwitchOutcome?
        enforcer.enforce(force: true) { outcome = $0 }
        XCTAssertEqual(outcome, .missingSource)
        XCTAssertTrue(h.launched.isEmpty)
    }

    func testChildMustExitAndCurrentSourceMustMatchBeforeSuccess() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcome: SwitchOutcome?
        enforcer.enforce(force: true) { outcome = $0 }
        XCTAssertNil(outcome)
        h.completions[0](.exited(0))
        guard case .failed = outcome else { return XCTFail("Child exit alone must not imply a successful switch") }
    }

    func testHelperFailuresArePropagated() {
        for result in [FocusProcessResult.exited(78), .timedOut] {
            let h = Harness()
            let enforcer = h.makeEnforcer()
            var outcome: SwitchOutcome?
            enforcer.enforce(force: true) { outcome = $0 }
            h.completions[0](result)
            guard case .failed = outcome else { return XCTFail("Expected failure for \(result)") }
        }
    }

    func testSecureInputThatStartsInsideChildIsPropagated() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcome: SwitchOutcome?
        enforcer.enforce(force: true) { outcome = $0 }
        h.completions[0](.exited(FocusHelper.secureExit))
        XCTAssertEqual(outcome, .secureInput)
    }

    func testLaunchErrorDoesNotLeaveEnforcerBusy() {
        let h = Harness()
        h.launchError = NSError(domain: "test", code: 1)
        let enforcer = h.makeEnforcer()
        var outcome: SwitchOutcome?
        enforcer.enforce(force: true) { outcome = $0 }
        guard case .failed = outcome else { return XCTFail("Expected launch failure") }
        h.launchError = nil
        enforcer.enforce(force: true)
        XCTAssertEqual(h.launched, ["CJK-A"])
    }

    func testPauseCancelsAutomaticChildAndRejectsItsLateSuccess() {
        let h = Harness()
        h.config.enabled = true
        let enforcer = h.makeEnforcer()
        var outcome: SwitchOutcome?
        enforcer.enforce(force: false) { outcome = $0 }
        h.config.enabled = false
        enforcer.enforce(force: false)
        XCTAssertEqual(h.cancelled, ["CJK-A"])
        h.current = "CJK-A"
        h.completions[0](.exited(0))
        XCTAssertEqual(outcome, .busy)
    }

    func testManualCancellationDropsQueuedWorkAndRejectsLateSuccessExactlyOnce() {
        let h = Harness(); h.config.enabled = true
        let enforcer = h.makeEnforcer()
        var first: [SwitchOutcome] = []
        var queued: [SwitchOutcome] = []
        enforcer.enforce(force: true) { first.append($0) }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { queued.append($0) }
        h.config.enabled = false
        enforcer.cancelManualRequests()
        enforcer.cancelManualRequests()
        XCTAssertEqual(queued, [.busy])
        XCTAssertTrue(first.isEmpty, "The active helper must exit before releasing its slot")
        h.current = "CJK-B"
        h.completions[0](.exited(0))
        h.completions[0](.exited(0))
        XCTAssertEqual(first, [.busy])
        XCTAssertEqual(queued, [.busy])
        XCTAssertEqual(h.launched, ["CJK-A"])
        XCTAssertFalse(enforcer.isSwitching)
        enforcer.enforce(force: false)
        XCTAssertEqual(h.launched, ["CJK-A"], "Pausing must not restart the discarded queue")
    }

    func testNewManualSelectionWhilePausedWaitsForCancelledHelperThenRuns() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcomes: [SwitchOutcome] = []
        enforcer.enforce(force: true) { outcomes.append($0) }
        enforcer.cancelManualRequests()
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { outcomes.append($0) }
        XCTAssertEqual(h.launched, ["CJK-A"])
        h.completions[0](.exited(0))
        XCTAssertEqual(h.launched, ["CJK-A", "CJK-B"])
        h.current = "CJK-B"; h.completions[1](.exited(0))
        XCTAssertEqual(outcomes, [.busy, .success])
    }

    func testAutomaticHelperStartAndExitPublishActualSwitchingState() {
        let h = Harness(); h.config.enabled = true
        let enforcer = h.makeEnforcer()
        var states: [Bool] = []
        enforcer.onUpdate = { states.append(enforcer.isSwitching) }
        enforcer.enforce(force: false)
        XCTAssertEqual(states, [true])
        h.current = "CJK-A"; h.completions[0](.exited(0))
        XCTAssertEqual(states, [true, false])
        enforcer.onUpdate = nil
    }

    func testPauseDetectedDuringCompletionCancelsQueuedManualRequest() {
        let h = Harness(); h.config.enabled = true
        let enforcer = h.makeEnforcer()
        var first: [SwitchOutcome] = []
        var queued: [SwitchOutcome] = []
        enforcer.enforce(force: true) { first.append($0) }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { queued.append($0) }
        // Model refresh first observes an external pause inside the completion notification.
        enforcer.onUpdate = {
            h.config.enabled = false
            enforcer.cancelManualRequests()
        }
        h.completions[0](.cancelled)
        XCTAssertEqual(h.launched, ["CJK-A"])
        XCTAssertEqual(first, [.busy])
        XCTAssertEqual(queued, [.busy])
        h.completions[0](.exited(0))
        XCTAssertEqual(first, [.busy]); XCTAssertEqual(queued, [.busy])
        XCTAssertFalse(enforcer.isSwitching)
        enforcer.onUpdate = nil
    }

    func testReentrantChoiceDuringCompletionReplacesOldQueueWithoutLosingCallbacks() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcomes: [String: [SwitchOutcome]] = [:]
        enforcer.enforce(force: true) { outcomes["A", default: []].append($0) }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { outcomes["B", default: []].append($0) }
        var enqueued = false
        enforcer.onUpdate = {
            guard !enqueued else { return }
            enqueued = true
            h.config.sourceID = "CJK-C"
            enforcer.enforce(force: true) { outcomes["C", default: []].append($0) }
        }
        h.completions[0](.cancelled)
        XCTAssertEqual(h.launched, ["CJK-A", "CJK-C"])
        XCTAssertEqual(outcomes, ["A": [.busy], "B": [.busy]])
        h.current = "CJK-C"; h.completions[1](.exited(0))
        h.completions[0](.exited(0)); h.completions[1](.exited(0))
        XCTAssertEqual(outcomes, ["A": [.busy], "B": [.busy], "C": [.success]])
        XCTAssertFalse(enforcer.isSwitching)
        enforcer.onUpdate = nil
    }

    func testReentrantChoiceFromDisplacedCallbackOwnsTheQueue() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcomes: [String: [SwitchOutcome]] = [:]
        enforcer.enforce(force: true) { outcomes["A", default: []].append($0) }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) {
            outcomes["B", default: []].append($0)
            h.config.sourceID = "CJK-D"
            enforcer.enforce(force: true) { outcomes["D", default: []].append($0) }
        }
        h.config.sourceID = "CJK-C"
        enforcer.enforce(force: true) { outcomes["C", default: []].append($0) }
        h.completions[0](.cancelled)
        XCTAssertEqual(h.launched, ["CJK-A", "CJK-D"])
        XCTAssertEqual(outcomes, ["A": [.busy], "B": [.busy], "C": [.busy]])
        h.current = "CJK-D"; h.completions[1](.exited(0))
        XCTAssertEqual(outcomes, ["A": [.busy], "B": [.busy], "C": [.busy], "D": [.success]])
    }

    func testPausedTimerRefreshClearsSecureInputWithoutAnExternalNotification() {
        let h = Harness(); h.secure = true
        let enforcer = h.makeEnforcer()
        let model = AppModel(services: AppServices(
            load: { h.config }, save: { h.config = $0 },
            choices: { [InputChoice(id: "CJK-A", name: "Input method")] },
            current: { InputChoice(id: h.current, name: h.current) },
            loginEnabled: { false }, setLogin: { _ in },
            apply: { enforcer.enforce(force: true, finish: $0) },
            secureInput: { h.secure }, isSwitching: { enforcer.isSwitching },
            cancelSwitch: { enforcer.cancelManualRequests() }), isPreview: true)
        model.refresh(); model.choose("CJK-A")
        XCTAssertEqual(model.runtimeState, .secureInput)
        // Choosing a real source enables keeping; explicitly follow the system
        // before testing the paused timer path.
        model.pauseKeeping()
        XCTAssertFalse(h.config.enabled)
        XCTAssertEqual(model.runtimeState, .paused)
        XCTAssertTrue(model.secureInput)
        h.secure = false
        XCTAssertTrue(model.secureInput, "The model must remain stale until the timer refresh")
        let refreshed = expectation(description: "The real two-second timer refreshes a paused model")
        let started = Date()
        var fulfilled = false
        enforcer.onUpdate = {
            // Ignore any unrelated workspace notification before the timer is due.
            guard Date().timeIntervalSince(started) >= 1.8 else { return }
            model.refresh()
            if model.runtimeState == .paused && !model.secureInput && !fulfilled {
                fulfilled = true
                refreshed.fulfill()
            }
        }
        enforcer.start()
        wait(for: [refreshed], timeout: 2.8)
        XCTAssertEqual(model.runtimeState, .paused)
        XCTAssertFalse(model.secureInput)
        XCTAssertNil(model.warning)
        XCTAssertTrue(h.launched.isEmpty); XCTAssertTrue(h.selected.isEmpty)
        enforcer.onUpdate = nil
    }

    func testStaleOrDuplicateChildCallbacksCannotCompleteNewRequest() {
        let h = Harness()
        let enforcer = h.makeEnforcer()
        var outcomes: [SwitchOutcome] = []
        enforcer.enforce(force: true) { outcomes.append($0) }
        h.config.sourceID = "CJK-B"
        enforcer.enforce(force: true) { outcomes.append($0) }
        h.completions[0](.cancelled)
        h.completions[0](.exited(0))
        XCTAssertEqual(outcomes, [.busy])
        h.current = "CJK-B"
        h.completions[1](.exited(0))
        XCTAssertEqual(outcomes, [.busy, .success])
    }

    func testDirectSelectionErrorAndUnconfirmedSelectionAreFailures() {
        for status: Int32 in [0, -50] {
            let h = Harness()
            h.config.sourceID = "latin-B"
            h.selectionStatus = status
            h.selectionActuallyChanges = false
            let enforcer = h.makeEnforcer()
            var outcome: SwitchOutcome?
            enforcer.enforce(force: true) { outcome = $0 }
            guard case .failed = outcome else { return XCTFail("Expected failure for status \(status)") }
            XCTAssertEqual(h.selected, ["latin-B"])
        }
    }

    func testHelperPolicyRejectsStaleTargetAndPausedAutomaticRequest() {
        let paused = Config(sourceID: "CJK-A", enabled: false)
        XCTAssertFalse(FocusHelper.requestIsCurrent(id: "CJK-B", automatic: false, config: paused))
        XCTAssertFalse(FocusHelper.requestIsCurrent(id: "CJK-A", automatic: true, config: paused))
        XCTAssertTrue(FocusHelper.requestIsCurrent(id: "CJK-A", automatic: false, config: paused))
    }

    func testAutomaticOutcomesReportFailuresAndRecoveryButIgnoreBusy() {
        let h = Harness()
        h.config.enabled = true
        h.secure = true
        let enforcer = h.makeEnforcer()
        var outcomes: [SwitchOutcome] = []
        enforcer.onAutomaticOutcome = { outcomes.append($0) }
        enforcer.enforce(force: false)
        XCTAssertEqual(outcomes, [.secureInput])
        h.secure = false
        enforcer.enforce(force: false)
        enforcer.enforce(force: false) // busy notification while the helper runs
        XCTAssertEqual(outcomes, [.secureInput])
        h.current = "CJK-A"
        h.completions[0](.exited(0))
        XCTAssertEqual(outcomes, [.secureInput, .success])
        enforcer.enforce(force: true)
        XCTAssertEqual(outcomes, [.secureInput, .success], "Manual results use their own callback")
    }

    func testProductionProcessRunnerTimesOutAndReapsAChildIgnoringTermination() throws {
        let finished = expectation(description: "Timed out child actually exited")
        var outcome: FocusProcessResult?
        let job = FocusProcessJob(timeout: 0.2) { result in
            outcome = result
            finished.fulfill()
        }
        // Only this test-owned sleep process is launched. No app, input source, or login item is touched.
        try job.start(executable: URL(fileURLWithPath: "/bin/sh"),
                      arguments: ["-c", "trap '' TERM; exec /bin/sleep 20"])
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(outcome, .timedOut)
        withExtendedLifetime(job) {}
    }

    func testProductionProcessRunnerCancellationWaitsForChildExit() throws {
        let finished = expectation(description: "Cancelled child actually exited")
        var outcome: FocusProcessResult?
        let job = FocusProcessJob(timeout: 3) { result in
            outcome = result
            finished.fulfill()
        }
        try job.start(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"])
        job.cancel()
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(outcome, .cancelled)
        withExtendedLifetime(job) {}
    }

}
