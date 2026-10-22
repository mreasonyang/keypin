import Foundation
import XCTest
@testable import keypin

final class ConfigTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testMissingConfigurationIsPaused() throws {
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory), .empty)
    }
    func testConfigurationRoundTripRequiresCompletionState() throws {
        let config = Config(sourceID: "abc", enabled: false, language: "ja", onboardingCompleted: true)
        try ConfigStore.write(config, to: directory)
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory), config)
        let incomplete = Data(#"{"sourceID":"abc","enabled":false}"#.utf8)
        try incomplete.write(to: directory.appendingPathComponent("config.json"))
        XCTAssertThrowsError(try ConfigStore.loadChecked(from: directory))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("config.json")), incomplete)
    }

    func testMutationReadsLatestConfigurationAndPreservesOtherFields() throws {
        try ConfigStore.write(Config(sourceID: "abc", enabled: true, language: "ja"), to: directory)
        let result = try ConfigStore.mutate(in: directory) { $0.sourceID = "next" }
        XCTAssertEqual(result, Config(sourceID: "next", enabled: true, language: "ja"))
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory), result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.lock").path))
    }

    func testMutationDoesNotEditOrOverwriteDamagedConfiguration() throws {
        let file = directory.appendingPathComponent("config.json")
        let damaged = Data("{ broken".utf8)
        try damaged.write(to: file)
        var editRan = false
        XCTAssertThrowsError(try ConfigStore.mutate(in: directory) { config in
            editRan = true
            config.enabled = true
        })
        XCTAssertFalse(editRan)
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testLockOpenFailurePropagatesWithoutChangingConfiguration() throws {
        let config = Config(sourceID: "abc", enabled: false)
        try ConfigStore.write(config, to: directory)
        let lock = directory.appendingPathComponent("config.lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ConfigStore.mutate(in: directory) { $0.enabled = true }) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
        }
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory), config)
    }

    func testWriteFailureReleasesLockForNextMutation() throws {
        let file = directory.appendingPathComponent("config.json")
        var injectedError: Error?
        XCTAssertThrowsError(try ConfigStore.mutate(in: directory) { config in
            config.enabled = true
            // Introduce the failure after a successful checked read, before atomic writing.
            do { try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false) }
            catch { injectedError = error }
        })
        XCTAssertNil(injectedError)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try ConfigStore.mutate(in: directory) { $0.enabled = true }.enabled, true)
    }

    func testConcurrentProcessesDoNotLoseReadModifyWriteUpdates() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/keypin/Config.swift")
        let workerSource = directory.appendingPathComponent("main.swift")
        let worker = directory.appendingPathComponent("config-worker")
        // Compile the actual production ConfigStore into an isolated test process.
        try """
        import Darwin
        import Foundation
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let iterations = Int(CommandLine.arguments[2])!
        do {
            for _ in 0..<iterations {
                try ConfigStore.mutate(in: directory) { config in
                    let count = Int(config.sourceID ?? "0")!
                    usleep(2_000) // Widen the race window while the transaction owns the lock.
                    config.sourceID = String(count + 1)
                }
            }
        } catch {
            fputs(String(describing: error), stderr)
            exit(1)
        }
        """.write(to: workerSource, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", source.path, workerSource.path, "-o", worker.path]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }

        try ConfigStore.write(Config(sourceID: "0", enabled: true, language: "ko"), to: directory)
        let children = (0..<4).map { _ in Process() }
        defer { children.filter(\.isRunning).forEach { $0.terminate() } }
        for child in children {
            child.executableURL = worker
            child.arguments = [directory.path, "30"]
            try child.run()
        }
        let deadline = Date().addingTimeInterval(10)
        while children.contains(where: \.isRunning) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        for child in children {
            XCTAssertFalse(child.isRunning, "Worker exceeded its test deadline")
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
            XCTAssertEqual(child.terminationStatus, 0)
        }
        XCTAssertEqual(try ConfigStore.loadChecked(from: directory),
                       Config(sourceID: "120", enabled: true, language: "ko"))
    }

}
