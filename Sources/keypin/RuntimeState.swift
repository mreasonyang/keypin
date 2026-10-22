import Foundation

/// The same observable state is used by the menu, panel, and automation snapshots.
enum RuntimeState: String, Codable, CaseIterable {
    case setup
    case paused
    case keeping
    case switching
    case waiting
    case secureInput = "secure_input"
    case missingSource = "missing_source"
    case error
    case stopped

    static func resolve(config: Config, currentID: String, targetAvailable: Bool,
                        secureInput: Bool, switching: Bool = false, failed: Bool = false,
                        configurationError: Bool = false, isRunning: Bool = true) -> RuntimeState {
        if configurationError { return .error }
        if !isRunning { return .stopped }
        // Following the system needs no target, including one remembered for CLI resume.
        if !config.enabled && !switching && !failed { return .paused }
        guard let target = config.sourceID, !target.isEmpty else { return .setup }
        if !targetAvailable { return .missingSource }
        if secureInput { return .secureInput }
        if switching { return .switching }
        if failed { return .error }
        return currentID == target ? .keeping : .waiting
    }

    var localizationKey: String {
        switch self {
        case .setup: return "state.setup"
        case .paused: return "state.paused"
        case .keeping: return "state.active"
        case .switching: return "state.switching"
        case .waiting: return "state.waiting"
        case .secureInput: return "state.secure"
        case .missingSource: return "state.missing"
        case .error: return "state.error"
        case .stopped: return "state.stopped"
        }
    }

    var symbol: String {
        switch self {
        case .setup: return "keyboard.badge.ellipsis"
        case .paused: return "pause.circle"
        case .keeping: return "pin.fill"
        case .switching: return "arrow.triangle.2.circlepath"
        case .waiting: return "clock"
        case .secureInput: return "lock.shield"
        case .missingSource: return "keyboard.badge.ellipsis"
        case .error: return "exclamationmark.triangle"
        case .stopped: return "stop.circle"
        }
    }
}
