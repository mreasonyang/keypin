import Darwin
import Foundation

struct Config: Codable, Equatable {
    var sourceID: String?
    var enabled: Bool
    var language: String? = nil
    var onboardingCompleted = false
    var needsOnboarding: Bool { !onboardingCompleted }
    static let empty = Config(sourceID: nil, enabled: false, language: nil)
}

enum ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/KeyPin")
    static let file = directory.appendingPathComponent("config.json")
    static let changed = Notification.Name("app.keypin.configChanged")
    static let openWindow = Notification.Name("app.keypin.openWindow")

    /// Background enforcement fails closed. Editors use loadChecked so a damaged file is never overwritten.
    static func load() -> Config { (try? loadChecked()) ?? .empty }

    static func loadChecked(from directory: URL = directory) throws -> Config {
        let file = directory.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: file.path) {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: file))
        }
        return .empty
    }

    /// Apply an edit to the latest disk state under one cross-process transaction.
    @discardableResult
    static func update(_ edit: (inout Config) throws -> Void) throws -> Config {
        let config = try mutate(in: directory, edit: edit)
        DistributedNotificationCenter.default().post(name: changed, object: nil)
        return config
    }

    /// Isolated directory variant; intentionally sends no distributed notification.
    @discardableResult
    static func mutate(in directory: URL, edit: (inout Config) throws -> Void) throws -> Config {
        try withExclusiveLock(in: directory) {
            var config = try loadChecked(from: directory)
            try edit(&config)
            try writeUnlocked(config, to: directory)
            return config
        }
    }

    /// Write a complete configuration. Edits to existing state use update instead.
    static func save(_ config: Config) throws {
        try write(config, to: directory)
        DistributedNotificationCenter.default().post(name: changed, object: nil)
    }

    static func write(_ config: Config, to directory: URL) throws {
        try withExclusiveLock(in: directory) { try writeUnlocked(config, to: directory) }
    }

    private static func writeUnlocked(_ config: Config, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: directory.appendingPathComponent("config.json"), options: .atomic)
    }

    private static func withExclusiveLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Never lock config.json itself: atomic replacement changes that file's inode.
        // This persistent sibling also coordinates independent GUI and CLI processes.
        let lock = directory.appendingPathComponent("config.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw lockError(path: lock.path, code: errno) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            let code = errno
            if code == EINTR { continue }
            throw lockError(path: lock.path, code: code)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func lockError(path: String, code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }
}
