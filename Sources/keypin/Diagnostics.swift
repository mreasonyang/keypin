import AppKit
import Darwin
import Foundation
import IOKit
import OSLog

enum DiagnosticPreferences {
    static let metadataKey = "diagnosticsIncludeApplicationMetadata"
    static var includeApplicationMetadata: Bool { UserDefaults.standard.bool(forKey: metadataKey) }
}

/// Deliberately excludes input text, source names/IDs, window titles, paths and error messages.
struct DiagnosticSnapshot: Codable, Equatable {
    let state: RuntimeState
    let secureInput: Bool
    let keepingEnabled: Bool
    let targetAvailable: Bool
    let currentMatchesTarget: Bool
    let configurationError: Bool
}

struct DiagnosticApplication: Codable, Equatable {
    let pid: Int32
    let bundleIdentifier: String?

    init(pid: Int32, bundleIdentifier: String? = nil) {
        self.pid = pid
        // Bundle identifiers are public app metadata, never a display/window/process title.
        self.bundleIdentifier = bundleIdentifier.flatMap { value in
            guard value.utf8.count <= 160, !value.isEmpty,
                  value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                      || (48...57).contains($0) || [45, 46, 95].contains($0) }) else { return nil }
            return value
        }
    }

    static func running(_ app: NSRunningApplication?) -> Self? {
        app.map { Self(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier) }
    }
}

struct DiagnosticContext: Codable, Equatable {
    enum OwnerLookup: String, Codable { case reportedPID = "reported_pid", unavailable }
    let frontmostApplication: DiagnosticApplication?
    /// Best effort, undocumented system metadata; the frontmost app is NEVER used as a fallback owner.
    let systemReportedOwner: DiagnosticApplication?
    var ownerLookup: OwnerLookup { systemReportedOwner == nil ? .unavailable : .reportedPID }

    static func live() -> Self {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        var ownerPID: Int32?
        if root != IO_OBJECT_NULL {
            defer { IOObjectRelease(root) }
            // Read one property locally. Only a PID from our on-console session is retained.
            if let sessions = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] {
                ownerPID = reportedOwnerPID(in: sessions, uid: getuid())
            }
        }
        let owner = ownerPID.map { pid in
            DiagnosticApplication(pid: pid, bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
        }
        return Self(frontmostApplication: DiagnosticApplication.running(NSWorkspace.shared.frontmostApplication),
                    systemReportedOwner: owner)
    }

    static func reportedOwnerPID(in sessions: [[String: Any]], uid: uid_t) -> Int32? {
        for session in sessions {
            guard (session["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue == true,
                  (session["kCGSSessionUserIDKey"] as? NSNumber)?.uint64Value == UInt64(uid),
                  let pid = session["kCGSSessionSecureInputPID"] as? NSNumber,
                  pid.int64Value > 0, pid.int64Value <= Int64(Int32.max),
                  pid.doubleValue == Double(pid.int32Value) else { continue }
            return pid.int32Value
        }
        return nil
    }
}

struct DiagnosticSwitch: Codable, Equatable {
    enum Outcome: String, Codable { case success, secureInput = "secure_input", missingSource = "missing_source", failed, busy }
    enum Reason: String, Codable {
        case launchFailed = "launch_failed", selectionFailed = "selection_failed", unconfirmed
        case helperTimeout = "helper_timeout", helperCancelled = "helper_cancelled", helperExit = "helper_exit"
    }
    let automatic: Bool
    let outcome: Outcome
    var reason: Reason? = nil
    var statusCode: Int32? = nil

    init(automatic: Bool, outcome: SwitchOutcome, reason: Reason? = nil, statusCode: Int32? = nil) {
        self.automatic = automatic
        switch outcome {
        case .success: self.outcome = .success
        case .secureInput: self.outcome = .secureInput
        case .missingSource: self.outcome = .missingSource
        case .failed: self.outcome = .failed // Never retain arbitrary error descriptions.
        case .busy: self.outcome = .busy
        }
        self.reason = reason
        self.statusCode = statusCode
    }
}

struct DiagnosticEvent: Codable {
    enum Kind: String, Codable {
        case sessionStarted = "session_started", sessionEnded = "session_ended"
        case runtimeChanged = "runtime_changed"
        case secureInputStarted = "secure_input_started", secureInputEnded = "secure_input_ended"
        case secureInputStillActive = "secure_input_still_active", secureInputContextChanged = "secure_input_context_changed"
        case switchCompleted = "switch_completed", switchRecovered = "switch_recovered"
        case eventsSuppressed = "events_suppressed"
    }
    let schemaVersion: Int
    let timestamp: Date
    let sessionID: UUID
    let processID: Int32
    let event: Kind
    var snapshot: DiagnosticSnapshot?
    var previousState: RuntimeState?
    var secureEpisodeID: UUID?
    var observedDurationSeconds: TimeInterval?
    var activeAtSessionStart: Bool?
    var context: DiagnosticContext?
    var ownerLookup: DiagnosticContext.OwnerLookup?
    var switchResult: DiagnosticSwitch?
    var appVersion: String?
    var appBuild: String?
    var macOSVersion: String?
    var applicationMetadataEnabled: Bool?
    var suppressedEventCounts: [String: Int]?

    /// Defense in depth at the write boundary, also used when cleaning older records.
    func sanitized(includeApplicationMetadata: Bool) -> Self {
        var record = self
        if !includeApplicationMetadata { record.context = nil; record.ownerLookup = nil }
        for key in [\Self.appVersion, \Self.appBuild, \Self.macOSVersion] {
            record[keyPath: key] = record[keyPath: key].flatMap { value in
                guard !value.isEmpty, value.utf8.count <= 32,
                      value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else { return nil }
                return value
            }
        }
        record.suppressedEventCounts = record.suppressedEventCounts?.filter {
            Kind(rawValue: $0.key) != nil && $0.value > 0 && $0.value <= 1_000_000
        }
        return record
    }
}

/// GUI-owned observer. Stable polling is silent; clocks, context and output are injectable.
final class RuntimeDiagnostics {
    static let shared = RuntimeDiagnostics(write: { DiagnosticLogStore.shared.append($0) },
        includeApplicationMetadata: { DiagnosticPreferences.includeApplicationMetadata })
    private let write: (DiagnosticEvent) -> Void
    private let uptime: () -> TimeInterval
    private let date: () -> Date
    private let context: () -> DiagnosticContext
    private let includeApplicationMetadata: () -> Bool
    private let lock = NSLock()
    private let sessionID = UUID()
    private var started = false
    private var finished = false
    private var previous: DiagnosticSnapshot?
    private var secureStart: TimeInterval?
    private var secureEpisodeID: UUID?
    private var nextProgress: TimeInterval = 0
    private var previousContext: DiagnosticContext?
    private var automaticFailure: DiagnosticSwitch?
    private var nextContextSample: TimeInterval = 0
    private var emittedAt: [TimeInterval] = []
    private var suppressed: [String: Int] = [:]
    private var suppressionStarted: TimeInterval?

    init(write: @escaping (DiagnosticEvent) -> Void,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         date: @escaping () -> Date = Date.init,
         context: @escaping () -> DiagnosticContext = DiagnosticContext.live,
         includeApplicationMetadata: @escaping () -> Bool = { false }) {
        self.write = write; self.uptime = uptime; self.date = date; self.context = context
        self.includeApplicationMetadata = includeApplicationMetadata
    }

    func observe(_ snapshot: DiagnosticSnapshot) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        let now = uptime()
        if !started {
            started = true
            var event = make(.sessionStarted, snapshot: snapshot)
            event.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            event.appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            let os = ProcessInfo.processInfo.operatingSystemVersion
            event.macOSVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            emit(event)
        }
        let metadataEnabled = includeApplicationMetadata()
        if !metadataEnabled { previousContext = nil; nextContextSample = 0 }
        if snapshot.secureInput {
            var currentContext = previousContext
            if metadataEnabled && (secureStart == nil || now >= nextContextSample) {
                currentContext = context(); nextContextSample = now + 2
            }
            if secureStart == nil {
                secureStart = now; secureEpisodeID = UUID(); nextProgress = now + 30
                var event = secureEvent(.secureInputStarted, snapshot: snapshot, now: now, context: currentContext)
                event.activeAtSessionStart = previous == nil
                emit(event)
            } else {
                if currentContext != previousContext {
                    emit(secureEvent(.secureInputContextChanged, snapshot: snapshot, now: now, context: currentContext))
                }
                if now >= nextProgress {
                    emit(secureEvent(.secureInputStillActive, snapshot: snapshot, now: now, context: currentContext))
                    nextProgress = now + 300
                }
            }
            previousContext = currentContext
        } else if secureStart != nil {
            emit(secureEvent(.secureInputEnded, snapshot: snapshot, now: now, context: previousContext))
            secureStart = nil; secureEpisodeID = nil; previousContext = nil
        }
        if snapshot != previous {
            var event = make(.runtimeChanged, snapshot: snapshot)
            event.previousState = previous?.state
            emit(event)
        }
        previous = snapshot
        flushSuppressionIfDue(now: now)
    }

    func recordSwitch(_ result: DiagnosticSwitch) {
        lock.lock(); defer { lock.unlock() }
        // CLI/status/helper processes never create a separate writer or race GUI rotation.
        guard started, !finished else { return }
        var kind = DiagnosticEvent.Kind.switchCompleted
        if result.automatic {
            guard result.outcome != .busy else { return }
            if result.outcome == .success {
                guard automaticFailure != nil else { return }
                automaticFailure = nil; kind = .switchRecovered
            } else {
                guard result != automaticFailure else { return }
                automaticFailure = result
            }
        }
        var event = make(kind, snapshot: previous)
        event.switchResult = result
        event.secureEpisodeID = secureEpisodeID
        emit(event)
        flushSuppressionIfDue(now: uptime())
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard started, !finished else { return }
        // Ending the process does not prove that another app released secure input.
        var event = secureEvent(.sessionEnded, snapshot: previous, now: uptime(), context: previousContext)
        if !suppressed.isEmpty { event.suppressedEventCounts = suppressed }
        emit(event)
        finished = true
    }

    private func make(_ kind: DiagnosticEvent.Kind, snapshot: DiagnosticSnapshot?) -> DiagnosticEvent {
        DiagnosticEvent(schemaVersion: 1, timestamp: date(), sessionID: sessionID,
                        processID: getpid(), event: kind, snapshot: snapshot,
                        applicationMetadataEnabled: includeApplicationMetadata())
    }

    private func secureEvent(_ kind: DiagnosticEvent.Kind, snapshot: DiagnosticSnapshot?, now: TimeInterval,
                             context: DiagnosticContext?) -> DiagnosticEvent {
        var event = make(kind, snapshot: snapshot)
        event.secureEpisodeID = secureEpisodeID
        event.observedDurationSeconds = secureStart.map { (max(0, now - $0) * 1_000).rounded() / 1_000 }
        event.context = context
        event.ownerLookup = context?.ownerLookup
        return event
    }

    private func emit(_ event: DiagnosticEvent) {
        let now = uptime()
        emittedAt.removeAll { now - $0 >= 60 }
        let important: Bool
        switch event.event {
        case .sessionStarted, .sessionEnded, .secureInputStarted, .secureInputEnded, .switchRecovered, .eventsSuppressed:
            important = true
        default: important = false
        }
        // A strict rolling-minute ceiling, with 20 slots reserved for episode boundaries/recovery.
        guard emittedAt.count < (important ? 60 : 40) else {
            suppressed[event.event.rawValue] = min(1_000_000, (suppressed[event.event.rawValue] ?? 0) + 1)
            if suppressionStarted == nil { suppressionStarted = now }
            return
        }
        emittedAt.append(now)
        write(event.sanitized(includeApplicationMetadata: includeApplicationMetadata()))
    }

    private func flushSuppressionIfDue(now: TimeInterval) {
        guard let start = suppressionStarted, now - start >= 60 else { return }
        emittedAt.removeAll { now - $0 >= 60 }
        guard emittedAt.count < 60 else { return }
        var event = make(.eventsSuppressed, snapshot: previous)
        event.suppressedEventCounts = suppressed
        suppressed = [:]; suppressionStarted = nil
        emit(event)
    }
}

/// Three private JSONL files, at most 512 KiB each. Disk work never blocks enforcement.
final class DiagnosticLogStore {
    static let shared = DiagnosticLogStore(directory: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/KeyPin", isDirectory: true),
        includeApplicationMetadata: { DiagnosticPreferences.includeApplicationMetadata })
    let directory: URL
    private let maximumFileBytes: Int
    private let queue = DispatchQueue(label: "app.keypin.diagnostics", qos: .utility)
    private let fileManager = FileManager.default
    private let date: () -> Date
    private let includeApplicationMetadata: () -> Bool
    private let retentionSeconds: TimeInterval
    private let pendingSlots = DispatchSemaphore(value: 64)
    private var nextMaintenance = Date.distantPast
    private var maintenanceTimer: DispatchSourceTimer?
    private var reportedFailure = false
    private let logger = Logger(subsystem: "app.keypin", category: "diagnostics")

    init(directory: URL, maximumFileBytes: Int = 512 * 1_024,
         retentionSeconds: TimeInterval = 7 * 24 * 60 * 60,
         date: @escaping () -> Date = Date.init,
         includeApplicationMetadata: @escaping () -> Bool = { false }) {
        self.directory = directory; self.maximumFileBytes = maximumFileBytes
        self.retentionSeconds = retentionSeconds; self.date = date
        self.includeApplicationMetadata = includeApplicationMetadata
    }

    deinit { maintenanceTimer?.cancel() }

    func append(_ event: DiagnosticEvent) {
        guard pendingSlots.wait(timeout: .now()) == .success else { return }
        queue.async { [self] in
            defer { pendingSlots.signal() }
            do {
                let now = date()
                guard event.timestamp >= now.addingTimeInterval(-retentionSeconds),
                      event.timestamp <= now.addingTimeInterval(300) else { return }
                try ensureDirectory()
                try pruneExpired(force: false)
                startMaintenanceTimer()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                var line = try encoder.encode(event.sanitized(includeApplicationMetadata: includeApplicationMetadata()))
                line.append(10)
                guard line.count <= maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
                try write(line)
                reportedFailure = false
            } catch {
                if !reportedFailure { logger.error("Diagnostic log unavailable; input switching continues.") }
                reportedFailure = true
            }
        }
    }

    func flush() { queue.sync {} }

    func prepareDirectory() throws -> URL {
        try queue.sync {
            try ensureDirectory(); try pruneExpired(force: true); startMaintenanceTimer()
            return directory
        }
    }

    /// Also strips previously recorded app identifiers when the privacy option is turned off.
    func maintain(completion: @escaping (Bool) -> Void = { _ in }) {
        queue.async { [self] in
            guard fileManager.fileExists(atPath: directory.path) else { completion(true); return }
            do { try ensureDirectory(); try pruneExpired(force: true); completion(true) }
            catch {
                logger.error("Diagnostic cleanup incomplete; existing records may remain.")
                completion(false)
            }
        }
    }

    private func startMaintenanceTimer() {
        guard maintenanceTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3_600, repeating: 3_600, leeway: .seconds(30))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            do { try self.ensureDirectory(); try self.pruneExpired(force: true) }
            catch { /* Keep enforcement independent from storage. */ }
        }
        maintenanceTimer = timer
        timer.resume()
    }

    private func pruneExpired(force: Bool) throws {
        let now = date()
        guard force || now >= nextMaintenance else { return }
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for index in 0...2 {
            let path = url(index)
            let fd = Darwin.open(path.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if fd < 0 && errno == ENOENT { continue }
            guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_uid == getuid(), info.st_nlink == 1,
                  info.st_size <= Int64(maximumFileBytes), fchmod(fd, 0o600) == 0 else {
                Darwin.close(fd); throw CocoaError(.fileReadNoPermission)
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                if count < 0 { Darwin.close(fd); throw CocoaError(.fileReadUnknown) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
                if data.count > maximumFileBytes { Darwin.close(fd); throw CocoaError(.fileReadTooLarge) }
            }
            Darwin.close(fd)
            var retained = Data()
            for line in data.split(separator: 10) {
                guard let event = try? decoder.decode(DiagnosticEvent.self, from: Data(line)),
                      event.schemaVersion == 1, event.timestamp >= cutoff,
                      event.timestamp <= now.addingTimeInterval(300) else { continue }
                retained.append(try encoder.encode(event.sanitized(includeApplicationMetadata: includeApplicationMetadata())))
                retained.append(10)
            }
            if retained.isEmpty { try fileManager.removeItem(at: path) }
            else if retained != data { try replace(retained, at: path) }
        }
        nextMaintenance = now.addingTimeInterval(3_600)
    }

    private func replace(_ data: Data, at destination: URL) throws {
        let temporary = directory.appendingPathComponent(".maintenance-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { Darwin.close(fd); _ = Darwin.unlink(temporary.path) }
        try writeBytes(data, to: fd)
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private func url(_ index: Int = 0) -> URL {
        directory.appendingPathComponent(index == 0 ? "diagnostics.jsonl" : "diagnostics.\(index).jsonl")
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), chmod(directory.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
    }

    private func openCurrent() throws -> Int32 {
        let fd = Darwin.open(url().path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, fchmod(fd, 0o600) == 0 else {
            Darwin.close(fd); throw CocoaError(.fileWriteNoPermission)
        }
        return fd
    }

    private func write(_ line: Data) throws {
        try ensureDirectory()
        var fd = try openCurrent()
        defer { if fd >= 0 { Darwin.close(fd) } }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        if info.st_size + Int64(line.count) > Int64(maximumFileBytes) {
            Darwin.close(fd); fd = -1
            try rotate()
            fd = try openCurrent()
        }
        let originalSize = lseek(fd, 0, SEEK_END)
        guard originalSize >= 0 else { throw CocoaError(.fileWriteUnknown) }
        do {
            try writeBytes(line, to: fd)
        } catch {
            // A short write (for example, disk full) must not corrupt the next JSONL event.
            _ = ftruncate(fd, originalSize)
            throw error
        }
    }

    private func writeBytes(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += count
            }
        }
    }

    private func rotate() throws {
        // Never follow a link or replace an unexpected object during rotation.
        for index in 0...2 {
            var info = stat()
            let result = lstat(url(index).path, &info)
            if result != 0 && errno == ENOENT { continue }
            guard result == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
                  info.st_nlink == 1 else { throw CocoaError(.fileWriteNoPermission) }
        }
        if fileManager.fileExists(atPath: url(2).path) { try fileManager.removeItem(at: url(2)) }
        for index in stride(from: 1, through: 0, by: -1) {
            if fileManager.fileExists(atPath: url(index).path) {
                try fileManager.moveItem(at: url(index), to: url(index + 1))
            }
        }
    }
}
