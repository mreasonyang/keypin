import Foundation

/// Bounds automatic mutations within one app/target context. Successful selections and
/// their notification echoes do not refill the budget: an opposing manager can undo them.
struct AutomaticSwitchGuard {
    static let attemptWindow: TimeInterval = 15
    static let attemptLimit = 3
    static let initialPause: TimeInterval = 15
    static let maximumPause: TimeInterval = 120
    static let stableInterval: TimeInterval = 30

    private var target: String?
    private var appPID: Int32?
    private var attempts: [TimeInterval] = []
    private var pausedUntil: TimeInterval = 0
    private var nextPause = Self.initialPause
    private var satisfiedSince: TimeInterval?

    mutating func updateContext(target: String?, enabled: Bool, appPID: Int32?) {
        guard enabled else { self = Self(); return }
        // nil represents our own UI/helper or an unavailable frontmost app. It must
        // not reset a pause when our focus workaround briefly activates itself.
        if self.target != target || (appPID != nil && self.appPID != appPID) {
            reset()
        }
        self.target = target
        if let appPID { self.appPID = appPID }
    }

    mutating func reset() {
        attempts.removeAll()
        pausedUntil = 0
        nextPause = Self.initialPause
        satisfiedSince = nil
    }

    func isPaused(at uptime: TimeInterval) -> Bool { uptime < pausedUntil }

    mutating func observeCurrent(matchesTarget: Bool, at uptime: TimeInterval) {
        guard matchesTarget else { satisfiedSince = nil; return }
        if let since = satisfiedSince {
            if uptime - since >= Self.stableInterval { reset() }
        } else {
            satisfiedSince = uptime
        }
    }

    /// Call only immediately before a real automatic select/helper launch, after
    /// secure-input, availability, current-source and helper-cooldown checks.
    mutating func permitsAttempt(at uptime: TimeInterval) -> Bool {
        guard !isPaused(at: uptime) else { return false }
        satisfiedSince = nil
        attempts.removeAll { uptime - $0 >= Self.attemptWindow }
        guard attempts.count < Self.attemptLimit else {
            pausedUntil = uptime + nextPause
            nextPause = min(nextPause * 2, Self.maximumPause)
            return false
        }
        attempts.append(uptime)
        return true
    }
}
