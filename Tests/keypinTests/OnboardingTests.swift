import Foundation
import XCTest
@testable import keypin

/// All configuration, input-source and login operations stay in memory.
final class OnboardingTests: XCTestCase {
    private final class Store {
        var config = Config.empty
        var choices = [InputChoice(id: "abc", name: "ABC"), InputChoice(id: "ime", name: "IME")]
        var current = InputChoice(id: "abc", name: "ABC")
        var login = false
        var loadFails = false
        var saveFails = false
        var loginFails = false
        var writes = 0
        var transactions = 0
        var loginChanges: [Bool] = []
        var callbacks: [(SwitchOutcome) -> Void] = []
        var events: [String] = []
        var appliedConfigurations: [Config] = []
        var loginConfigurations: [Config] = []

        func load() throws -> Config {
            if loadFails { throw NSError(domain: "onboarding.load", code: 1) }
            return config
        }

        func save(_ next: Config) throws {
            if saveFails { throw NSError(domain: "onboarding.save", code: 1) }
            config = next
            writes += 1
            events.append("save")
        }

        var services: AppServices {
            AppServices(
                load: { try self.load() },
                save: { try self.save($0) },
                choices: { self.choices },
                current: { self.current },
                loginEnabled: { self.login },
                setLogin: { on in
                    self.loginChanges.append(on)
                    self.loginConfigurations.append(self.config)
                    self.events.append("login")
                    if self.loginFails { throw NSError(domain: "onboarding.login", code: 1) }
                    self.login = on
                },
                apply: { callback in
                    self.appliedConfigurations.append(self.config)
                    self.events.append("apply")
                    self.callbacks.append(callback)
                },
                updateConfig: { edit in
                    self.transactions += 1
                    var next = try self.load()
                    edit(&next)
                    try self.save(next)
                    return next
                }
            )
        }

        func model(start: Bool = true) -> AppModel {
            let result = AppModel(services: services, isPreview: true)
            if start { result.start() }
            return result
        }
    }

    func testFreshInstallStartsWithAnUnselectedDraftAndNoMutations() {
        let store = Store()
        let model = store.model()
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertEqual(model.setupStep, 0)
        XCTAssertNil(model.setupSourceID)
        XCTAssertTrue(model.setupKeepEnabled)
        XCTAssertNil(model.setupLoginRequested)
        XCTAssertFalse(model.canFinishSetup)
        XCTAssertEqual(store.config, .empty)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
    }

    func testCompletedSetupDoesNotReplayForAnUnavailableTarget() {
        let store = Store()
        store.config = Config(sourceID: "removed", enabled: false, onboardingCompleted: true)
        XCTAssertFalse(store.model().showsOnboarding)
        XCTAssertEqual(store.writes, 0)
    }

    func testUnfinishedSetupRequiresConfirmationEvenWithASelectedTarget() {
        let store = Store()
        store.config.sourceID = "abc"
        XCTAssertTrue(store.model().showsOnboarding)
        XCTAssertEqual(store.writes, 0)
    }

    func testSkippedConfigurationRoundTripsAndDoesNotReplay() throws {
        let store = Store()
        let model = store.model()
        model.skipSetup()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertNil(store.config.sourceID)
        XCTAssertFalse(store.config.enabled)
        XCTAssertEqual(store.config.onboardingCompleted, true)
        XCTAssertEqual(store.writes, 1)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
        store.config = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(store.config))
        XCTAssertFalse(store.model().showsOnboarding)
    }

    func testCompletedConfigurationDoesNotReplayEvenWithoutATarget() {
        let store = Store()
        store.config.onboardingCompleted = true
        XCTAssertFalse(store.model().showsOnboarding)
        XCTAssertEqual(store.writes, 0)
    }

    func testCorruptConfigurationDoesNotEnterOrOverwriteSetup() {
        let store = Store()
        store.loadFails = true
        let model = store.model()
        XCTAssertTrue(model.configError)
        XCTAssertFalse(model.showsOnboarding)
        model.beginSetup()
        model.setupSourceID = "ime"
        model.finishSetup()
        model.skipSetup()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
    }

    func testDraftSurvivesCatalogAndCurrentSourceRefreshWithoutSideEffects() {
        let store = Store()
        let model = store.model()
        model.setupSourceID = "ime"
        model.setupStep = 1
        model.setupKeepEnabled = false
        model.setupLoginRequested = true
        store.current = store.choices[1]
        store.choices.append(InputChoice(id: "third", name: "Third"))
        model.refresh()
        model.refreshLogin()
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertEqual(model.setupSourceID, "ime")
        XCTAssertEqual(model.setupStep, 1)
        XCTAssertFalse(model.setupKeepEnabled)
        XCTAssertEqual(model.setupLoginRequested, true)
        XCTAssertEqual(store.config, .empty)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
    }

    func testFinishSaveFailureKeepsDraftAndPreventsEveryExternalOperation() {
        let store = Store()
        let model = store.model()
        model.setupSourceID = "ime"
        model.setupStep = 1
        model.setupLoginRequested = true
        store.saveFails = true
        model.finishSetup()
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertEqual(model.setupStep, 1)
        XCTAssertEqual(model.setupSourceID, "ime")
        XCTAssertNotNil(model.warning)
        XCTAssertEqual(store.config, .empty)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
        store.saveFails = false
        model.finishSetup()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertEqual(store.writes, 1)
    }

    func testSkipSaveFailureKeepsOnboardingVisibleAndCanBeRetried() {
        let store = Store()
        let model = store.model()
        store.saveFails = true
        model.skipSetup()
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertFalse(store.config.onboardingCompleted)
        XCTAssertNotNil(model.warning)
        store.saveFails = false
        model.skipSetup()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertEqual(store.config.onboardingCompleted, true)
    }

    func testFinishCommitsOnceBeforeApplyAndLoginAndRejectsDoubleSubmission() {
        let store = Store()
        let model = store.model()
        model.setupSourceID = "ime"
        model.setupLoginRequested = true
        // Simulate another editor changing a field after the wizard opened.
        store.config.language = "ko"
        model.finishSetup()
        model.finishSetup()
        model.skipSetup()
        let expected = Config(sourceID: "ime", enabled: true, language: "ko", onboardingCompleted: true)
        XCTAssertEqual(store.config, expected)
        XCTAssertEqual(store.transactions, 1)
        XCTAssertEqual(store.writes, 1)
        XCTAssertEqual(store.events, ["save", "apply", "login"])
        XCTAssertEqual(store.appliedConfigurations, [expected])
        XCTAssertEqual(store.loginConfigurations, [expected])
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertTrue(model.switching)
        XCTAssertEqual(store.loginChanges, [true])
        XCTAssertFalse(store.model().showsOnboarding)
    }

    func testFinishWhilePausedSavesTargetWithoutSwitchingOrChangingLogin() {
        let store = Store()
        store.login = true
        let model = store.model()
        model.setupSourceID = "ime"
        model.setupKeepEnabled = false
        model.finishSetup()
        XCTAssertEqual(store.config.sourceID, "ime")
        XCTAssertFalse(store.config.enabled)
        XCTAssertEqual(store.config.onboardingCompleted, true)
        XCTAssertEqual(store.writes, 1)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
        XCTAssertTrue(store.login)
        XCTAssertFalse(model.switching)
    }

    func testDisappearedDraftTargetIsRecheckedAtSubmission() {
        let store = Store()
        let model = store.model()
        model.setupSourceID = "ime"
        model.setupStep = 1
        XCTAssertTrue(model.canFinishSetup)
        store.choices.removeAll { $0.id == "ime" }
        // No manual refresh: finish must query the latest catalog itself.
        model.finishSetup()
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertNil(model.setupSourceName)
        XCTAssertFalse(model.canFinishSetup)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
        XCTAssertTrue(store.loginChanges.isEmpty)
    }

    func testEmptyCatalogCannotCompleteButCanSkip() {
        let store = Store()
        store.choices = []
        let model = store.model()
        model.finishSetup()
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertFalse(model.canFinishSetup)
        XCTAssertEqual(store.writes, 0)
        model.skipSetup()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertEqual(store.config.onboardingCompleted, true)
    }

    func testLoginFailureSurvivesDelayedSwitchFailureAndSuccess() {
        let store = Store()
        store.loginFails = true
        let model = store.model()
        model.setupSourceID = "ime"
        model.setupLoginRequested = true
        model.finishSetup()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertFalse(model.loginEnabled)
        let loginWarning = model.warning
        XCTAssertNotNil(loginWarning)
        store.callbacks[0](.failed("delayed failure"))
        let switchWarning = L10n.format("warn.switch", "delayed failure")
        XCTAssertEqual(model.warning, switchWarning + "\n" + (loginWarning ?? ""))
        XCTAssertTrue(model.canRetrySwitch)
        model.retry()
        XCTAssertEqual(store.callbacks.count, 2)
        store.current = store.choices[1]
        store.callbacks[1](.success)
        XCTAssertEqual(model.warning, loginWarning)
        XCTAssertFalse(model.canRetrySwitch)
        XCTAssertEqual(model.runtimeState, .keeping)
        store.loginFails = false
        model.setLogin(true)
        XCTAssertNil(model.warning)
        XCTAssertTrue(model.loginEnabled)
    }

    func testLoginSuccessDoesNotEraseAnExistingSwitchFailure() {
        let store = Store()
        let model = store.model()
        model.setupSourceID = "ime"
        model.finishSetup()
        store.callbacks[0](.failed("temporary"))
        let switchWarning = model.warning
        XCTAssertNotNil(switchWarning)
        model.setLogin(true)
        XCTAssertEqual(model.warning, switchWarning)
        XCTAssertTrue(model.canRetrySwitch)
    }

    func testReopenedSetupCancelDoesNotWriteOrApply() {
        for enabled in [false, true] {
            let store = Store()
            store.config = Config(sourceID: "abc", enabled: enabled, language: "ja", onboardingCompleted: true)
            let original = store.config
            let model = store.model()
            XCTAssertFalse(model.showsOnboarding)
            model.beginSetup()
            XCTAssertEqual(model.setupSourceID, "abc")
            XCTAssertEqual(model.setupKeepEnabled, enabled)
            model.setupSourceID = "ime"
            model.setupKeepEnabled = true
            model.setupLoginRequested = true
            model.skipSetup()
            XCTAssertFalse(model.showsOnboarding)
            XCTAssertEqual(store.config, original)
            XCTAssertEqual(store.writes, 0)
            XCTAssertTrue(store.callbacks.isEmpty)
            XCTAssertTrue(store.loginChanges.isEmpty)
        }
    }

    func testPausedSetupCompletionIgnoresAnOlderPendingSwitchOutcome() {
        let store = Store()
        store.config = Config(sourceID: "abc", enabled: false)
        let model = store.model()
        model.choose("ime")
        XCTAssertTrue(model.switching)
        XCTAssertEqual(store.callbacks.count, 1)
        model.beginSetup()
        model.setupSourceID = "abc"
        model.setupKeepEnabled = false
        model.finishSetup()
        XCTAssertFalse(model.switching)
        XCTAssertEqual(model.pinnedID, "abc")
        XCTAssertFalse(model.enabled)
        XCTAssertEqual(store.callbacks.count, 1)
        store.callbacks[0](.failed("obsolete operation"))
        XCTAssertNil(model.warning)
        XCTAssertFalse(model.switching)
    }
}
