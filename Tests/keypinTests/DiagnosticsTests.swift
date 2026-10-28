import Carbon
import Darwin
import Foundation
import XCTest
@testable import keypin

final class DiagnosticsTests: XCTestCase {
    private final class Harness {
        var events: [DiagnosticEvent] = []
        var time: TimeInterval = 100
        var wallClock = Date()
        var includeMetadata = false
        var contextCalls = 0
        var context = DiagnosticContext(frontmostApplication: DiagnosticApplication(pid: 123, bundleIdentifier: "test.frontmost"),
                                        systemReportedOwner: nil)
        lazy var recorder = RuntimeDiagnostics(write: { self.events.append($0) }, uptime: { self.time },
            date: { self.wallClock }, context: { self.contextCalls += 1; return self.context },
            includeApplicationMetadata: { self.includeMetadata })
    }

    private func snapshot(secure: Bool = false, state: RuntimeState? = nil) -> DiagnosticSnapshot {
        DiagnosticSnapshot(state: state ?? (secure ? .secureInput : .keeping), secureInput: secure,
            keepingEnabled: true, targetAvailable: true, currentMatchesTarget: true, configurationError: false)
    }

    func testStablePollingDoesNotWriteOrCollectApplicationMetadata() {
        let h = Harness()
        for _ in 0..<200 { h.recorder.observe(snapshot()) }
        XCTAssertEqual(h.events.map(\.event), [.sessionStarted, .runtimeChanged])
        XCTAssertEqual(h.contextCalls, 0, "Ordinary app usage must not become a foreground-app history")
        for _ in 0..<200 { h.recorder.recordSwitch(DiagnosticSwitch(automatic: true, outcome: .success)) }
        XCTAssertEqual(h.events.count, 2)
    }

    func testDefaultPrivacyNeverCallsTheContextProviderDuringSecureInput() {
        let h = Harness()
        for index in 0..<200 {
            h.time = 100 + Double(index) * 2
            h.recorder.observe(snapshot(secure: true))
        }
        h.recorder.observe(snapshot()); h.recorder.finish()
        XCTAssertEqual(h.contextCalls, 0)
        XCTAssertTrue(h.events.allSatisfy { $0.context == nil && $0.ownerLookup == nil })
        XCTAssertTrue(h.events.allSatisfy { $0.applicationMetadataEnabled == false })
    }

    func testMetadataOptInIsSampledAtMostEveryTwoSecondsAndOffStopsCollection() {
        let h = Harness(); h.includeMetadata = true
        for index in 0..<200 {
            h.time = 100 + Double(index) / 1_000
            h.recorder.observe(snapshot(secure: true))
        }
        XCTAssertEqual(h.contextCalls, 1)
        h.time = 102; h.recorder.observe(snapshot(secure: true))
        XCTAssertEqual(h.contextCalls, 2)
        h.includeMetadata = false
        let prior = h.events.count
        h.time = 104; h.recorder.observe(snapshot(secure: true)); h.recorder.observe(snapshot()); h.recorder.finish()
        XCTAssertEqual(h.contextCalls, 2)
        XCTAssertTrue(h.events.dropFirst(prior).allSatisfy { $0.context == nil && $0.ownerLookup == nil })
    }

    func testRateLimitReservesSpaceForBoundariesAndReportsSuppressedEvents() throws {
        let h = Harness(); h.recorder.observe(snapshot())
        for _ in 0..<1_000 { h.recorder.recordSwitch(DiagnosticSwitch(automatic: false, outcome: .success)) }
        XCTAssertEqual(h.events.count, 40)
        h.recorder.observe(snapshot(secure: true)); h.recorder.observe(snapshot())
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: true, outcome: .missingSource))
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: true, outcome: .success))
        XCTAssertTrue(h.events.contains { $0.event == .secureInputStarted })
        XCTAssertTrue(h.events.contains { $0.event == .secureInputEnded })
        XCTAssertTrue(h.events.contains { $0.event == .switchRecovered })
        XCTAssertLessThanOrEqual(h.events.count, 60)
        h.time += 60; h.recorder.observe(snapshot())
        let summary = try XCTUnwrap(h.events.last { $0.event == .eventsSuppressed })
        XCTAssertGreaterThan(summary.suppressedEventCounts?["switch_completed"] ?? 0, 0)
        XCTAssertEqual(summary.snapshot?.state, .keeping)
    }

    func testEvenRepeatedCriticalEventsCannotExceedSixtyRecordsPerRollingMinute() {
        let h = Harness()
        for _ in 0..<200 { h.recorder.observe(snapshot(secure: true)); h.recorder.observe(snapshot()) }
        XCTAssertEqual(h.events.count, 60)
        h.time += 59.999; h.recorder.observe(snapshot())
        XCTAssertEqual(h.events.count, 60)
        h.time += 0.001; h.recorder.observe(snapshot())
        XCTAssertEqual(h.events.last?.event, .eventsSuppressed)
    }

    func testSecureEpisodeTracksContextProgressAndMonotonicDuration() throws {
        let h = Harness()
        h.includeMetadata = true
        h.recorder.observe(snapshot())
        h.recorder.observe(snapshot(secure: true))
        let start = try XCTUnwrap(h.events.first { $0.event == .secureInputStarted })
        XCTAssertEqual(start.activeAtSessionStart, false)
        XCTAssertEqual(start.ownerLookup, .unavailable)
        XCTAssertNil(start.context?.systemReportedOwner, "The foreground app must not be promoted to owner")
        for _ in 0..<200 { h.recorder.observe(snapshot(secure: true)) }
        XCTAssertEqual(h.events.filter { $0.event == .secureInputStarted }.count, 1)
        h.time = 105
        h.context = DiagnosticContext(frontmostApplication: DiagnosticApplication(pid: 456), systemReportedOwner: nil)
        h.recorder.observe(snapshot(secure: true))
        XCTAssertEqual(h.events.last?.event, .secureInputContextChanged)
        h.time = 129; h.recorder.observe(snapshot(secure: true))
        XCTAssertFalse(h.events.contains { $0.event == .secureInputStillActive })
        h.time = 130; h.recorder.observe(snapshot(secure: true))
        h.time = 429; h.recorder.observe(snapshot(secure: true))
        XCTAssertEqual(h.events.filter { $0.event == .secureInputStillActive }.count, 1)
        h.time = 430; h.recorder.observe(snapshot(secure: true))
        XCTAssertEqual(h.events.filter { $0.event == .secureInputStillActive }.count, 2)
        h.time = 445.125; h.wallClock = Date(timeIntervalSince1970: 500)
        h.recorder.observe(snapshot())
        let end = try XCTUnwrap(h.events.first { $0.event == .secureInputEnded })
        XCTAssertEqual(end.secureEpisodeID, start.secureEpisodeID)
        XCTAssertEqual(end.observedDurationSeconds, 345.125)
        XCTAssertEqual(end.timestamp, h.wallClock)
        h.recorder.observe(snapshot(secure: true))
        XCTAssertNotEqual(h.events.last { $0.event == .secureInputStarted }?.secureEpisodeID, start.secureEpisodeID)
    }

    func testStartupAndQuitDoNotInventAnUnknownStartOrARelease() throws {
        let h = Harness()
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: false, outcome: .success))
        XCTAssertTrue(h.events.isEmpty, "CLI/helper processes must not create a competing log writer")
        h.recorder.observe(snapshot(secure: true))
        XCTAssertEqual(h.events.first { $0.event == .secureInputStarted }?.activeAtSessionStart, true)
        h.time += 12
        h.recorder.finish(); h.recorder.finish()
        XCTAssertEqual(h.events.last?.event, .sessionEnded)
        XCTAssertEqual(h.events.last?.observedDurationSeconds, 12)
        XCTAssertFalse(h.events.contains { $0.event == .secureInputEnded })
        let count = h.events.count
        h.recorder.observe(snapshot()); h.recorder.recordSwitch(DiagnosticSwitch(automatic: false, outcome: .success))
        XCTAssertEqual(h.events.count, count)
        let next = Harness(); next.recorder.observe(snapshot())
        XCTAssertNotEqual(h.events.first?.sessionID, next.events.first?.sessionID)
    }

    func testRepeatedAutomaticErrorsAreDeduplicatedAndRecoveryIsRecorded() throws {
        let h = Harness(); h.recorder.observe(snapshot())
        let failure = DiagnosticSwitch(automatic: true, outcome: .failed("PRIVATE_DIAGNOSTIC_MESSAGE_SHOULD_NOT_BE_WRITTEN"),
                                        reason: .selectionFailed, statusCode: -50)
        for _ in 0..<200 { h.recorder.recordSwitch(failure) }
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: true, outcome: .busy))
        XCTAssertEqual(h.events.filter { $0.event == .switchCompleted }.count, 1)
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: true, outcome: .success))
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: true, outcome: .success))
        XCTAssertEqual(h.events.filter { $0.event == .switchRecovered }.count, 1)
        h.recorder.recordSwitch(DiagnosticSwitch(automatic: false, outcome: .success))
        XCTAssertEqual(h.events.filter { $0.event == .switchCompleted }.count, 2)
        let data = try JSONEncoder().encode(h.events)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE_DIAGNOSTIC_MESSAGE_SHOULD_NOT_BE_WRITTEN"))
    }

    func testOwnerLookupRejectsOtherUsersOffConsoleSessionsAndInvalidPIDs() {
        let valid: [String: Any] = ["kCGSSessionOnConsoleKey": true, "kCGSSessionUserIDKey": 501,
                                    "kCGSSessionSecureInputPID": 1234]
        var other = valid; other["kCGSSessionUserIDKey"] = 502
        var background = valid; background["kCGSSessionOnConsoleKey"] = false
        var invalid = valid; invalid["kCGSSessionSecureInputPID"] = -1
        var fractional = valid; fractional["kCGSSessionSecureInputPID"] = 123.5
        XCTAssertNil(DiagnosticContext.reportedOwnerPID(in: [other, background, invalid, fractional], uid: 501))
        XCTAssertEqual(DiagnosticContext.reportedOwnerPID(in: [other, background, valid], uid: 501), 1234)
        XCTAssertNil(DiagnosticContext.reportedOwnerPID(in: [], uid: 501))
        XCTAssertNil(DiagnosticApplication(pid: 1, bundleIdentifier: "invalid\nwindow title").bundleIdentifier)
        XCTAssertNil(DiagnosticApplication(pid: 1, bundleIdentifier: String(repeating: "a", count: 161)).bundleIdentifier)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keypin-diagnostics-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func records(at url: URL) throws -> [DiagnosticEvent] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try Data(contentsOf: url).split(separator: 10).map {
            try decoder.decode(DiagnosticEvent.self, from: Data($0))
        }
    }

    func testWriterRedactsMetadataAndUnexpectedVersionStringsEvenIfProducerIncludesThem() throws {
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"))
        let h = Harness(); h.includeMetadata = true; h.recorder.observe(snapshot(secure: true))
        var event = try XCTUnwrap(h.events.first { $0.context != nil })
        event.appVersion = "PRIVATE_VERSION_TEXT"; event.appBuild = "PRIVATE_BUILD_TEXT"
        store.append(event); store.flush()
        let written = try XCTUnwrap(records(at: store.directory.appendingPathComponent("diagnostics.jsonl")).first)
        XCTAssertNil(written.context); XCTAssertNil(written.ownerLookup)
        XCTAssertNil(written.appVersion); XCTAssertNil(written.appBuild)
    }

    func testDisablingMetadataRemovesItFromExistingLogFiles() throws {
        var enabled = true
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"),
                                       includeApplicationMetadata: { enabled })
        let h = Harness(); h.includeMetadata = true; h.recorder.observe(snapshot(secure: true))
        store.append(try XCTUnwrap(h.events.first { $0.context != nil })); store.flush()
        let current = store.directory.appendingPathComponent("diagnostics.jsonl")
        XCTAssertNotNil(try records(at: current).first?.context)
        enabled = false; store.maintain(); store.flush()
        XCTAssertNil(try records(at: current).first?.context)
        XCTAssertNil(try records(at: current).first?.ownerLookup)
    }

    func testCleanupFailureIsReportedInsteadOfClaimingOldIdentifiersWereRemoved() throws {
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"))
        let directory = try store.prepareDirectory()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("diagnostics.jsonl"),
                                                withIntermediateDirectories: false)
        var succeeded: Bool?
        store.maintain { succeeded = $0 }; store.flush()
        XCTAssertEqual(succeeded, false)
    }

    func testRetentionRemovesOldRecordsWithinAnOtherwiseFreshFileAndAllArchives() throws {
        let directory = try temporaryDirectory().appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let now = Date()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var mixed = Data()
        for days in [-8.0, -6, 1] {
            let event = DiagnosticEvent(schemaVersion: 1, timestamp: now.addingTimeInterval(days * 86_400),
                                        sessionID: UUID(), processID: 1, event: .runtimeChanged)
            mixed.append(try encoder.encode(event)); mixed.append(10)
        }
        mixed.append(Data("invalid fixture line\n".utf8))
        for name in ["diagnostics.jsonl", "diagnostics.1.jsonl", "diagnostics.2.jsonl"] {
            let url = directory.appendingPathComponent(name)
            try mixed.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
        let store = DiagnosticLogStore(directory: directory, date: { now })
        _ = try store.prepareDirectory()
        for name in ["diagnostics.jsonl", "diagnostics.1.jsonl", "diagnostics.2.jsonl"] {
            let retained = try records(at: directory.appendingPathComponent(name))
            XCTAssertEqual(retained.count, 1)
            XCTAssertEqual(try XCTUnwrap(retained.first).timestamp.timeIntervalSince1970,
                           now.addingTimeInterval(-6 * 86_400).timeIntervalSince1970, accuracy: 1)
        }
    }

    func testMaintenanceExpiresQuietLogsWithoutRequiringAnotherEvent() throws {
        var now = Date()
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"), date: { now })
        let h = Harness(); h.recorder.observe(snapshot())
        store.append(try XCTUnwrap(h.events.first)); store.flush()
        now = now.addingTimeInterval(8 * 86_400)
        store.maintain(); store.flush()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
    }

    func testPendingWriteQueueIsBoundedWhenStorageIsSlow() throws {
        let entered = expectation(description: "Writer reached the simulated slow storage boundary")
        let gate = DispatchSemaphore(value: 0)
        var first = true
        let now = Date()
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"), date: {
            if first { first = false; entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            return now
        })
        let h = Harness(); h.recorder.observe(snapshot())
        let event = try XCTUnwrap(h.events.first)
        store.append(event)
        wait(for: [entered], timeout: 2)
        for _ in 0..<1_000 { store.append(event) }
        gate.signal(); store.flush()
        XCTAssertEqual(try records(at: store.directory.appendingPathComponent("diagnostics.jsonl")).count, 64)
    }

    func testMetadataSettingUsesInjectedPreferencesWithoutChangingInputConfiguration() {
        let backing = AppModelTests.Store()
        var enabled = false
        var services = backing.services
        services.diagnosticMetadataEnabled = { enabled }
        services.setDiagnosticMetadataEnabled = { enabled = $0 }
        let model = AppModel(services: services, isPreview: true)
        model.refresh(); XCTAssertFalse(model.diagnosticMetadataEnabled)
        model.setDiagnosticMetadataEnabled(true); XCTAssertTrue(model.diagnosticMetadataEnabled)
        model.setDiagnosticMetadataEnabled(false); XCTAssertFalse(model.diagnosticMetadataEnabled)
        XCTAssertTrue(backing.savedConfigs.isEmpty)
        XCTAssertTrue(backing.callbacks.isEmpty)
    }

    func testRotationRemainsBoundedPrivateAndDecodableAcrossAllFiles() throws {
        let directory = try temporaryDirectory().appendingPathComponent("logs")
        let now = Date()
        let store = DiagnosticLogStore(directory: directory, maximumFileBytes: 2_048, date: { now })
        let h = Harness(); h.recorder.observe(snapshot())
        let template = try XCTUnwrap(h.events.first)
        for index in 0..<100 {
            store.append(DiagnosticEvent(schemaVersion: 1, timestamp: now.addingTimeInterval(Double(index) - 100),
                sessionID: template.sessionID, processID: template.processID, event: .sessionStarted))
            if index % 16 == 0 { store.flush() }
        }
        store.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["diagnostics.jsonl", "diagnostics.1.jsonl", "diagnostics.2.jsonl"])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertLessThanOrEqual(data.count, 2_048)
            XCTAssertEqual(data.last, 10)
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            for line in data.split(separator: 10) {
                XCTAssertEqual(try decoder.decode(DiagnosticEvent.self, from: Data(line)).schemaVersion, 1)
            }
        }
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        let current = try Data(contentsOf: directory.appendingPathComponent("diagnostics.jsonl"))
        let last = try XCTUnwrap(current.split(separator: 10).last)
        XCTAssertEqual(try decoder.decode(DiagnosticEvent.self, from: Data(last)).timestamp.timeIntervalSince1970,
                       floor(now.addingTimeInterval(-1).timeIntervalSince1970), accuracy: 1)
    }

    func testSymlinkWriteIsRejectedAndLoggingRecoversWithoutTouchingItsTarget() throws {
        let root = try temporaryDirectory()
        let outside = root.appendingPathComponent("outside.txt")
        let sentinel = Data("untouched fixture".utf8)
        try sentinel.write(to: outside)
        let store = DiagnosticLogStore(directory: root.appendingPathComponent("logs"))
        let directory = try store.prepareDirectory()
        let current = directory.appendingPathComponent("diagnostics.jsonl")
        try FileManager.default.createSymbolicLink(at: current, withDestinationURL: outside)
        let h = Harness(); h.recorder.observe(snapshot())
        let event = try XCTUnwrap(h.events.first)
        store.append(event); store.flush()
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
        try FileManager.default.removeItem(at: current)
        store.append(event); store.flush()
        XCTAssertGreaterThan(try Data(contentsOf: current).count, 0)
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    }

    func testUnavailableDirectoryDoesNotPreventAppModelUpdates() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("file-instead-of-directory")
        try Data().write(to: file)
        let store = DiagnosticLogStore(directory: file.appendingPathComponent("logs"))
        let diagnostics = RuntimeDiagnostics(write: { store.append($0) })
        let backing = AppModelTests.Store(); backing.config.enabled = true
        var services = backing.services
        services.recordDiagnostics = diagnostics.observe
        let model = AppModel(services: services, isPreview: true)
        model.refresh(); backing.secure = true; model.refresh(); backing.secure = false; model.refresh()
        store.flush()
        XCTAssertEqual(model.runtimeState, .keeping)
        XCTAssertNil(model.warning)
        XCTAssertTrue(backing.savedConfigs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testFIFOIsRejectedWithoutBlockingTheWriterOrShutdown() throws {
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"))
        let directory = try store.prepareDirectory()
        XCTAssertEqual(mkfifo(directory.appendingPathComponent("diagnostics.jsonl").path, 0o600), 0)
        let h = Harness(); h.recorder.observe(snapshot())
        store.append(try XCTUnwrap(h.events.first))
        let flushed = expectation(description: "A FIFO without a reader must never stall log shutdown")
        DispatchQueue.global().async { store.flush(); flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
    }

    func testNativeSecureInputCyclePersistsStartAndEndWithSystemMetadata() throws {
        guard !IsSecureEventInputEnabled() else { throw XCTSkip("Preexisting secure input; do not disturb its owner") }
        let store = DiagnosticLogStore(directory: try temporaryDirectory().appendingPathComponent("logs"),
                                       includeApplicationMetadata: { true })
        let recorder = RuntimeDiagnostics(write: { store.append($0) }, includeApplicationMetadata: { true })
        let backing = AppModelTests.Store()
        var services = backing.services
        services.secureInput = { IsSecureEventInputEnabled() }
        services.recordDiagnostics = recorder.observe
        let model = AppModel(services: services, isPreview: true)
        model.refresh()
        let enabled = EnableSecureEventInput()
        guard enabled == noErr else { return XCTFail("Could not enable the test process's secure input") }
        var released = false
        defer { if !released { _ = DisableSecureEventInput() } }
        model.refresh()
        XCTAssertTrue(model.secureInput)
        XCTAssertEqual(DisableSecureEventInput(), noErr); released = true
        model.refresh(); recorder.finish(); store.flush()
        let data = try Data(contentsOf: store.directory.appendingPathComponent("diagnostics.jsonl"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let events = try data.split(separator: 10).map { try decoder.decode(DiagnosticEvent.self, from: Data($0)) }
        let start = try XCTUnwrap(events.first { $0.event == .secureInputStarted })
        let end = try XCTUnwrap(events.first { $0.event == .secureInputEnded })
        XCTAssertEqual(start.secureEpisodeID, end.secureEpisodeID)
        XCTAssertNotNil(start.ownerLookup)
        XCTAssertEqual(events.last?.event, .sessionEnded)
        XCTAssertFalse(model.secureInput)
        XCTAssertTrue(backing.savedConfigs.isEmpty)
    }

    func testAppModelPublishesSecureInputEvenWhenFollowingSystem() throws {
        let backing = AppModelTests.Store()
        let h = Harness()
        var services = backing.services
        services.recordDiagnostics = h.recorder.observe
        let model = AppModel(services: services, isPreview: true)
        model.refresh(); backing.secure = true; model.refresh()
        XCTAssertEqual(model.runtimeState, .paused)
        XCTAssertEqual(h.events.last { $0.event == .secureInputStarted }?.snapshot?.state, .paused)
        backing.secure = false; h.time += 10; model.refresh()
        XCTAssertEqual(h.events.last { $0.event == .secureInputEnded }?.observedDurationSeconds, 10)
        XCTAssertTrue(backing.savedConfigs.isEmpty)
    }
}
