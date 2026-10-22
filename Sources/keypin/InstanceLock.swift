import Foundation
import Darwin

/// Only the long-lived GUI acquires this lock. The nested focus helper has a separate bundle ID.
final class InstanceLock {
    private var descriptor: Int32 = -1

    /// Observe the GUI's exclusive lock without creating a file or becoming its owner.
    static func isHeld(at url: URL) throws -> Bool {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return false }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.EINVAL) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK { return true }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        flock(fd, LOCK_UN)
        return false
    }

    func acquire(at url: URL) throws -> Bool {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK { return false }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
        return true
    }
    deinit { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
}
