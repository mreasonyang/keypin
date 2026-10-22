import AppKit
import Combine
import Foundation
import XCTest
@testable import keypin

final class AppModelTests: XCTestCase {
    final class Store {
        var config = Config(sourceID: "abc", enabled: false, language: "en")
        var current = InputChoice(id: "abc", name: "ABC")
        var choices = [InputChoice(id: "abc", name: "ABC"), InputChoice(id: "ime", name: "IME")]
        var writes = 0
        var savedConfigs: [Config] = []
        var appliedConfigs: [Config] = []
        var login = false
        var loginChecks = 0
        var loadError = false
        var saveError = false
        var loginError = false
        var secure = false
        var activeSwitch = false
        var cancellations = 0
        var callbacks: [(SwitchOutcome) -> Void] = []
        var services: AppServices {
            AppServices(load: { if self.loadError { throw NSError(domain: "load", code: 1) }; return self.config },
                save: { if self.saveError { throw NSError(domain: "save", code: 1) }; self.config = $0; self.savedConfigs.append($0); self.writes += 1 },
                choices: { self.choices }, current: { self.current },
                loginEnabled: { self.loginChecks += 1; return self.login },
                setLogin: { if self.loginError { throw NSError(domain: "login", code: 1) }; self.login = $0 },
                apply: { self.appliedConfigs.append(self.config); self.callbacks.append($0) }, secureInput: { self.secure },
                isSwitching: { self.activeSwitch }, cancelSwitch: { self.cancellations += 1 })
        }
    }

    func testChoosingAnInputSourceEnablesKeepingInOneWriteBeforeSwitching() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime")
        XCTAssertEqual(store.config.sourceID, "ime"); XCTAssertTrue(store.config.enabled)
        XCTAssertEqual(store.writes, 1)
        XCTAssertEqual(store.savedConfigs, [Config(sourceID: "ime", enabled: true, language: "en")])
        XCTAssertEqual(store.appliedConfigs, store.savedConfigs)
        XCTAssertTrue(model.switching); XCTAssertEqual(store.callbacks.count, 1)
        store.current = store.choices[1]; store.callbacks[0](.success)
        XCTAssertEqual(model.currentID, "ime"); XCTAssertEqual(model.runtimeState, .keeping)
    }
    func testChoosingUsesOneTransactionAndPreservesLatestUnrelatedSettings() {
        let store = Store()
        var services = store.services
        var transactions: [Config] = []
        services.updateConfig = { edit in
            var latest = store.config
            latest.language = "ja"
            latest.onboardingCompleted = true
            edit(&latest)
            transactions.append(latest)
            store.config = latest
            return latest
        }
        let model = AppModel(services: services, isPreview: true)
        model.refresh(); model.choose("ime")
        let expected = Config(sourceID: "ime", enabled: true, language: "ja", onboardingCompleted: true)
        XCTAssertEqual(transactions, [expected])
        XCTAssertEqual(store.writes, 0, "The live transaction must not fall back to a separate save")
        XCTAssertEqual(store.appliedConfigs, [expected])
    }
    func testLatestRequestOwnsVisibleOutcome() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime"); model.choose("abc")
        store.callbacks[0](.failed("outdated"))
        XCTAssertTrue(model.switching); XCTAssertNil(model.warning)
        store.callbacks[1](.success)
        XCTAssertFalse(model.switching); XCTAssertNil(model.warning); XCTAssertEqual(model.pinnedID, "abc")
    }
    func testSaveFailureDoesNotSwitchOrMutateState() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); store.saveError = true; model.choose("ime")
        XCTAssertEqual(model.pinnedID, "abc"); XCTAssertTrue(store.callbacks.isEmpty); XCTAssertNotNil(model.warning)
        XCTAssertFalse(store.config.enabled); XCTAssertFalse(model.enabled); XCTAssertEqual(store.writes, 0)
        model.refresh(); XCTAssertNotNil(model.warning)
    }
    func testMissingSourceAndCorruptConfigCannotBeChosen() {
        let store = Store(); store.config.sourceID = "removed"
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("removed")
        XCTAssertTrue(model.targetMissing); XCTAssertFalse(model.canEnable); XCTAssertEqual(store.writes, 0)
        store.loadError = true; model.refresh(); model.choose("abc")
        XCTAssertTrue(model.configError); XCTAssertFalse(model.enabled); XCTAssertEqual(store.writes, 0)
    }
    func testInvalidSelectionDoesNotCreateTarget() {
        let store = Store(); store.config = .empty
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("")
        XCTAssertEqual(store.config, .empty); XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
    }
    func testChoosingARecentlyRemovedSourceDoesNotSaveOrEnableKeeping() {
        let store = Store()
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh()
        store.choices.removeAll { $0.id == "ime" }

        // The row was visible at the last refresh; the catalog changes before the click.
        model.choose("ime")

        XCTAssertEqual(model.sources, store.choices)
        XCTAssertEqual(model.pinnedID, "abc")
        XCTAssertFalse(model.enabled)
        XCTAssertEqual(store.config.sourceID, "abc")
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
    }
    func testChoosingRememberedSourceRechecksAvailability() {
        let store = Store()
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh()
        XCTAssertTrue(model.canEnable)
        store.choices.removeAll { $0.id == "abc" }

        model.choose("abc")

        XCTAssertTrue(model.targetMissing)
        XCTAssertFalse(model.canEnable)
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(store.config.enabled)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
    }
    func testLoginErrorSurvivesRefresh() {
        let store = Store(); store.loginError = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.setLogin(true)
        XCTAssertFalse(model.loginEnabled); XCTAssertFalse(model.loginBusy); XCTAssertNotNil(model.warning)
        model.refresh(); XCTAssertNotNil(model.warning)
    }
    func testKeyboardRefreshDoesNotInspectLoginServices() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.refresh(); model.refresh()
        XCTAssertEqual(store.loginChecks, 0)
    }
    func testFailedLanguageSaveDoesNotUpdateLanguage() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); store.saveError = true; model.setLanguage("ja")
        XCTAssertEqual(model.language, "en"); XCTAssertEqual(L10n.languageCode, "en")
    }
    func testSecureInputDoesNotAppearAsSuccessfulLock() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime"); store.secure = true; store.callbacks[0](.secureInput)
        XCTAssertNotNil(model.warning); XCTAssertFalse(model.switching)
        XCTAssertEqual(model.runtimeState, .secureInput)
    }
    func testAutomaticFailureIsVisibleWithoutClearingSaveFailure() {
        let store = Store(); store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); store.secure = true; model.receiveAutomaticOutcome(.secureInput)
        XCTAssertNotNil(model.warning)
        store.secure = false; model.receiveAutomaticOutcome(.success); XCTAssertNil(model.warning)
        store.saveError = true; model.setLanguage("ja")
        let savedWarning = model.warning
        model.receiveAutomaticOutcome(.success)
        XCTAssertEqual(model.warning, savedWarning)
    }

    func testRetryDoesNotSwitchForLoginOrSaveFailure() {
        let store = Store(); store.loginError = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.setLogin(true)
        XCTAssertFalse(model.canRetrySwitch)
        let loginWarning = model.warning
        model.retry()
        XCTAssertEqual(model.warning, loginWarning); XCTAssertTrue(store.callbacks.isEmpty)
        store.saveError = true; model.choose("ime"); model.retry()
        XCTAssertFalse(model.canRetrySwitch); XCTAssertTrue(store.callbacks.isEmpty)
    }

    func testAutomaticRecoveryClearsManualSwitchFailure() {
        let store = Store(); store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime"); store.callbacks[0](.failed("temporary"))
        XCTAssertNotNil(model.warning)
        model.refresh()
        XCTAssertNotNil(model.warning, "An ordinary refresh must preserve the failed action")
        store.current = store.choices[1]
        model.receiveAutomaticOutcome(.success)
        XCTAssertNil(model.warning, "Confirmed recovery must clear the old switch failure")
        XCTAssertEqual(model.runtimeState, .keeping)
    }

    func testRefreshDoesNotHideAFailedActionWhenTargetWasAlreadySelected() {
        let store = Store(); store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("abc"); store.callbacks[0](.failed("temporary"))
        XCTAssertEqual(model.runtimeState, .error)
        let warning = model.warning
        model.refresh()
        XCTAssertEqual(model.warning, warning)
        model.receiveAutomaticOutcome(.success)
        XCTAssertNil(model.warning)
        XCTAssertEqual(model.runtimeState, .keeping)
    }

    func testObservedRecoveryClearsOnlySwitchFailure() {
        let store = Store(); store.config.enabled = true; store.loginError = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.setLogin(true)
        let loginWarning = model.warning
        model.choose("ime"); store.callbacks[0](.failed("temporary"))
        store.saveError = true; model.setLanguage("ja")
        let failureWarning = model.warning
        store.current = store.choices[1]; model.refresh()
        XCTAssertNotNil(model.warning)
        XCTAssertNotEqual(model.warning, failureWarning)
        XCTAssertTrue(model.warning?.contains(loginWarning ?? "unexpected") == true)
        XCTAssertTrue(model.warning?.contains(L10n.text("warn.save")) == true)
        XCTAssertEqual(model.runtimeState, .keeping)
    }

    func testExternalPauseInvalidatesPendingCallback() {
        let store = Store(); store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime")
        store.config.enabled = false
        store.callbacks[0](.failed("outdated"))
        XCTAssertFalse(model.switching); XCTAssertNil(model.warning)
        XCTAssertEqual(model.runtimeState, .paused)
        XCTAssertEqual(store.cancellations, 1)
    }

    func testFollowingSystemCancelsPendingSelectionAndDiscardsLateOutcome() {
        let store = Store(); let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime"); model.pauseKeeping()
        store.callbacks[0](.failed("outdated"))
        XCTAssertFalse(model.switching); XCTAssertNil(model.warning)
        XCTAssertEqual(model.runtimeState, .paused)
        XCTAssertEqual(store.cancellations, 1)
        XCTAssertEqual(store.config.sourceID, "ime", "Keep the remembered target available for CLI resume")
        XCTAssertFalse(store.config.enabled)
        XCTAssertEqual(store.current.id, "abc", "Following the system must not switch the source")
        XCTAssertEqual(store.callbacks.count, 1)
    }

    func testFollowingSystemIgnoresAbsentOrRemovedRememberedTarget() {
        let store = Store(); store.config.sourceID = "removed"
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh()
        XCTAssertEqual(model.runtimeState, .paused); XCTAssertNil(model.warning)
        XCTAssertEqual(model.menuSourceName, "ABC")
        store.current = store.choices[1]; model.refresh()
        XCTAssertEqual(model.menuSourceName, "IME", "The menu follows the actual system input source while disabled")
        store.config.sourceID = nil; model.refresh()
        XCTAssertEqual(model.runtimeState, .paused); XCTAssertNil(model.warning)
        store.current = InputChoice(id: "", name: ""); model.refresh()
        XCTAssertEqual(model.menuSourceName, L10n.text("ui.follow-system"))
        XCTAssertEqual(store.writes, 0); XCTAssertTrue(store.callbacks.isEmpty)
    }

    func testMenuIconTracksActualSourceRatherThanPendingTargetAndCachesUnchangedSource() {
        let store = Store()
        var services = store.services
        var requested: [String] = []
        services.sourceIcon = { id in
            requested.append(id)
            return NSImage(size: id == "abc" ? NSSize(width: 10, height: 20) : NSSize(width: 20, height: 10))
        }
        let model = AppModel(services: services, isPreview: true)
        model.refresh(); model.refresh(); model.choose("ime")
        XCTAssertEqual(requested, ["abc"])
        XCTAssertEqual(model.menuSourceName, "ABC")
        XCTAssertEqual(model.currentSourceIcon.size, NSSize(width: 9, height: 18))
        XCTAssertTrue(model.sourceIcon(for: "abc") === model.currentSourceIcon)
        let rowIcon = model.sourceIcon(for: "ime")
        XCTAssertEqual(rowIcon.size, NSSize(width: 22, height: 11))
        XCTAssertEqual(requested, ["abc", "ime"], "A non-current row must load its own artwork")
        XCTAssertEqual(model.currentID, "abc", "Loading row artwork must not select the source")
        model.refresh()
        XCTAssertTrue(model.sourceIcon(for: "ime") === rowIcon)
        store.current = InputChoice(id: "ime", name: "A full input source name - without truncation")
        store.callbacks[0](.success)
        XCTAssertEqual(requested, ["abc", "ime"])
        XCTAssertEqual(model.menuSourceName, store.current.name)
        XCTAssertEqual(model.currentSourceIcon.size, NSSize(width: 22, height: 11))
        XCTAssertTrue(model.currentSourceIcon === rowIcon, "The menu must reuse the already-loaded row image")
        let icon = model.currentSourceIcon
        model.pauseKeeping()
        XCTAssertTrue(model.currentSourceIcon === icon)
        XCTAssertEqual(requested, ["abc", "ime"])
    }

    func testCatalogChangeReloadsArtworkAndMissingImageUsesKeyboardFallback() {
        let store = Store()
        var services = store.services
        var available = false
        var calls = 0
        services.sourceIcon = { _ in calls += 1; return available ? NSImage(size: NSSize(width: 16, height: 16)) : nil }
        let model = AppModel(services: services, isPreview: true)
        model.refresh()
        XCTAssertTrue(model.currentSourceIcon === MenuBarIcon.image)
        XCTAssertTrue(model.sourceIcon(for: "abc") === model.currentSourceIcon)
        available = true
        store.choices.append(InputChoice(id: "extra", name: "Extra"))
        model.refresh()
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(model.currentSourceIcon === MenuBarIcon.image)
        available = false
        model.refreshSourceArtwork()
        XCTAssertEqual(calls, 3, "Opening a panel or an enabled-source notification retries the same source's artwork")
        XCTAssertTrue(model.currentSourceIcon === MenuBarIcon.image)
        store.current = InputChoice(id: "", name: "")
        model.refresh()
        XCTAssertEqual(calls, 3, "An empty source ID must not query the live catalog")
        XCTAssertTrue(model.currentSourceIcon === MenuBarIcon.image)
        XCTAssertTrue(model.sourceIcon(for: "") === MenuBarIcon.image)
    }

    func testMissingRowArtworkIsCachedAndExplicitRefreshUpdatesRowsWhenMenuFallbackIsUnchanged() {
        let store = Store()
        var services = store.services
        var available = false
        var requested: [String] = []
        services.sourceIcon = { id in
            requested.append(id)
            return id == "ime" && available ? NSImage(size: NSSize(width: 24, height: 24)) : nil
        }
        let model = AppModel(services: services, isPreview: true)
        model.refresh()
        XCTAssertTrue(model.sourceIcon(for: "ime") === MenuBarIcon.image)
        model.refresh()
        XCTAssertTrue(model.sourceIcon(for: "ime") === MenuBarIcon.image)
        XCTAssertEqual(requested, ["abc", "ime"], "Missing artwork is cached too")

        var invalidations = 0
        let observation = model.objectWillChange.sink { invalidations += 1 }
        available = true
        model.refreshSourceArtwork()

        XCTAssertGreaterThan(invalidations, 0, "Rows must redraw even when the menu image is still the same fallback")
        XCTAssertTrue(model.currentSourceIcon === MenuBarIcon.image)
        XCTAssertFalse(model.sourceIcon(for: "ime") === MenuBarIcon.image)
        XCTAssertEqual(requested, ["abc", "ime", "abc", "ime"])
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(store.callbacks.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testCatalogChangesInvalidateRowArtworkAndRemovedSourcesCannotReuseCachedImages() {
        let store = Store()
        var services = store.services
        var calls: [String: Int] = [:]
        services.sourceIcon = { id in
            calls[id, default: 0] += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let model = AppModel(services: services, isPreview: true)
        model.refresh()
        let original = model.sourceIcon(for: "ime")
        store.choices.removeAll { $0.id == "ime" }
        model.refresh()
        XCTAssertTrue(model.sourceIcon(for: "ime") === MenuBarIcon.image)
        XCTAssertEqual(calls["ime"], 1, "Removed sources must not query the icon service")

        store.choices.append(InputChoice(id: "ime", name: "IME"))
        model.refresh()
        XCTAssertFalse(model.sourceIcon(for: "ime") === original)
        XCTAssertEqual(calls["ime"], 2, "A reinstalled source must load fresh artwork")
        XCTAssertEqual(calls["abc"], 3, "A catalog change also invalidates the still-current source's artwork")
    }

    func testCurrentSourceOutsideCatalogSharesArtworkAndIsPrunedAfterLeaving() {
        let store = Store()
        store.current = InputChoice(id: "external", name: "External")
        var services = store.services
        var requested: [String] = []
        services.sourceIcon = { id in
            requested.append(id)
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let model = AppModel(services: services, isPreview: true)
        model.refresh()
        let external = model.currentSourceIcon
        XCTAssertFalse(external === MenuBarIcon.image)
        XCTAssertTrue(model.sourceIcon(for: "external") === external)
        model.refresh()
        XCTAssertEqual(requested, ["external"])

        store.current = store.choices[0]
        model.refresh()
        XCTAssertTrue(model.sourceIcon(for: "external") === MenuBarIcon.image)
        XCTAssertEqual(requested, ["external", "abc"])
        store.current = InputChoice(id: "external", name: "External")
        model.refresh()
        XCTAssertFalse(model.currentSourceIcon === external)
        XCTAssertTrue(model.sourceIcon(for: "external") === model.currentSourceIcon)
        XCTAssertEqual(requested, ["external", "abc", "external"])
    }

    func testFollowingSystemClearsMissingSourceWarningButRetainsConfigurationError() {
        let store = Store(); store.config.sourceID = "removed"; store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh()
        XCTAssertEqual(model.runtimeState, .missingSource); XCTAssertNotNil(model.warning)
        model.pauseKeeping()
        XCTAssertEqual(model.runtimeState, .paused); XCTAssertNil(model.warning)
        store.loadError = true; model.refresh()
        XCTAssertEqual(model.runtimeState, .error); XCTAssertNotNil(model.warning)
    }

    func testChangedTargetDiscardsOldWarningAndCallback() {
        let store = Store(); store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); model.choose("ime"); store.callbacks[0](.failed("temporary"))
        store.config.sourceID = "abc"; model.refresh()
        XCTAssertNil(model.warning); XCTAssertEqual(model.runtimeState, .keeping)
        model.choose("ime"); store.config.sourceID = "abc"
        store.callbacks[1](.failed("outdated"))
        XCTAssertNil(model.warning); XCTAssertFalse(model.switching)
        XCTAssertEqual(model.runtimeState, .keeping)
    }

    func testSecureInputStateUsesSystemSignalAndClearsWhenItEnds() {
        let store = Store(); store.config.enabled = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); XCTAssertEqual(model.runtimeState, .keeping)
        store.secure = true; model.refresh()
        XCTAssertEqual(model.runtimeState, .secureInput)
        model.receiveAutomaticOutcome(.secureInput)
        store.secure = false; model.refresh()
        XCTAssertEqual(model.runtimeState, .keeping); XCTAssertNil(model.warning)
        store.secure = true; model.pauseKeeping()
        XCTAssertEqual(model.runtimeState, .paused)
    }

    func testAutomaticWorkIsReportedAsSwitchingAndCannotOverridePause() {
        let store = Store(); store.config.enabled = true; store.activeSwitch = true
        let model = AppModel(services: store.services, isPreview: true)
        model.refresh(); XCTAssertEqual(model.runtimeState, .switching)
        store.config.enabled = false; model.refresh()
        XCTAssertEqual(model.runtimeState, .paused)
        XCTAssertEqual(store.cancellations, 1)
    }

}
