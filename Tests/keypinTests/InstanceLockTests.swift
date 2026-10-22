import Foundation
import XCTest
@testable import keypin

final class InstanceLockTests: XCTestCase {
    func testReadOnlyProbeDoesNotCreateMissingDirectoryAndTracksLockRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("gui.lock")
        XCTAssertFalse(try InstanceLock.isHeld(at: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        var owner: InstanceLock? = InstanceLock()
        XCTAssertTrue(try owner!.acquire(at: path))
        XCTAssertTrue(try InstanceLock.isHeld(at: path))
        XCTAssertTrue(try InstanceLock.isHeld(at: path))
        owner = nil
        XCTAssertFalse(try InstanceLock.isHeld(at: path))
        let nextOwner = InstanceLock()
        XCTAssertTrue(try nextOwner.acquire(at: path), "The probe must not keep the lock")
    }

    func testOnlyOneGUIOwnsLockAndExitReleasesIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("gui.lock")
        var first: InstanceLock? = InstanceLock()
        XCTAssertTrue(try first!.acquire(at: path))
        let second = InstanceLock()
        XCTAssertFalse(try second.acquire(at: path))
        first = nil
        XCTAssertTrue(try second.acquire(at: path))
    }
    func testLockRefusesSymbolicLink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try Data("preserve".utf8).write(to: target)
        let link = directory.appendingPathComponent("gui.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try InstanceLock().acquire(at: link))
        XCTAssertThrowsError(try InstanceLock.isHeld(at: link))
        XCTAssertEqual(try Data(contentsOf: target), Data("preserve".utf8))
    }
    func testProbeRejectsDirectoryAtLockPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try InstanceLock.isHeld(at: directory))
    }
}
