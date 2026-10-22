import Carbon
import Foundation

struct AutomationFailure: Error, Codable, Equatable {
    let code: String
    let message: String
}

struct AutomationSource: Codable, Equatable {
    let id: String
    let name: String
}

struct AutomationTarget: Codable, Equatable {
    let id: String
    let name: String?
    let available: Bool
}

struct AutomationStatus: Codable, Equatable {
    let enabled: Bool
    let running: Bool
    let state: RuntimeState
    let current: AutomationSource
    let target: AutomationTarget?
    let loginEnabled: Bool
    let onboardingCompleted: Bool
}

/// A single JSON object is emitted on stdout for both success and failure.
struct AutomationResponse: Encodable {
    let schemaVersion = 1
    let ok: Bool
    let command: String
    var status: AutomationStatus? = nil
    var sources: [AutomationSource]? = nil
    var error: AutomationFailure? = nil

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

struct CLIRequest: Equatable {
    enum Command: String {
        case status, list, set, apply, open, install, uninstall, pause, resume, toggle, help
    }
    let command: Command
    let sourceID: String?
    let json: Bool

    static func parse(_ arguments: [String]) throws -> CLIRequest {
        let jsonCount = arguments.filter { $0 == "--json" }.count
        guard jsonCount <= 1 else { throw invalidArguments }
        let words = arguments.filter { $0 != "--json" }
        let name = words.first ?? "status"
        let command = (name == "--help" || name == "-h") ? Command.help : Command(rawValue: name)
        guard let command else { throw invalidArguments }
        let operandCount = command == .set || command == .install ? 1 : 0
        guard words.count == (words.isEmpty ? 0 : 1) + operandCount,
              !(command == .help && jsonCount > 0),
              words.dropFirst().allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") }) else {
            throw invalidArguments
        }
        return CLIRequest(command: command, sourceID: operandCount == 1 ? words[1] : nil, json: jsonCount == 1)
    }

    static let invalidArguments = AutomationFailure(code: "invalid_arguments", message: "Invalid command or arguments. Run keypin help for usage.")
}

struct AutomationServices {
    var load: () throws -> Config
    var update: (_ edit: (inout Config) throws -> Void) throws -> Config
    var choices: () -> [InputChoice]
    var current: () -> InputChoice
    var running: () throws -> Bool
    var secureInput: () -> Bool
    var loginEnabled: () -> Bool

    static var live: AutomationServices {
        AutomationServices(
            load: { try ConfigStore.loadChecked() },
            update: { try ConfigStore.update($0) },
            choices: Catalog.choices,
            current: { let source = Catalog.current(); return InputChoice(id: source.id, name: source.name) },
            running: { try InstanceLock.isHeld(at: ConfigStore.directory.appendingPathComponent("gui.lock")) },
            secureInput: { IsSecureEventInputEnabled() },
            loginEnabled: { Agent.isLoginEnabled }
        )
    }
}

struct Automation {
    let services: AutomationServices

    func status(config: Config? = nil) throws -> AutomationStatus {
        let config = try config ?? readConfig()
        let current = services.current()
        let target = config.sourceID.map { id in
            let source = services.choices().first { $0.id == id }
            return AutomationTarget(id: id, name: source?.name, available: source != nil)
        }
        let running: Bool
        do { running = try services.running() }
        catch { throw AutomationFailure(code: "runtime_unavailable", message: "Unable to inspect the running application.") }
        let state = RuntimeState.resolve(config: config, currentID: current.id,
                                         targetAvailable: target?.available == true,
                                         secureInput: services.secureInput(), isRunning: running)
        return AutomationStatus(enabled: config.enabled, running: running, state: state,
                                current: AutomationSource(id: current.id, name: current.name), target: target,
                                loginEnabled: services.loginEnabled(), onboardingCompleted: config.onboardingCompleted)
    }

    /// Mutate only the saved intent. The GUI reacts to the existing config notification.
    /// Enabling never launches another process or switches the input source in this process.
    func setKeeping(_ command: CLIRequest.Command) throws -> AutomationStatus {
        precondition(command == .pause || command == .resume || command == .toggle)
        let config = try editConfig { config in
            let enabled = command == .toggle ? !config.enabled : command == .resume
            if enabled { try requireTarget(config.sourceID) }
            config.enabled = enabled
        }
        return try status(config: config)
    }

    func readConfig() throws -> Config {
        do { return try services.load() }
        catch { throw AutomationFailure(code: "invalid_config", message: "Unable to read the configuration. The file has not been changed.") }
    }

    func editConfig(_ edit: (inout Config) throws -> Void) throws -> Config {
        do { return try services.update(edit) }
        catch let failure as AutomationFailure { throw failure }
        catch is DecodingError {
            throw AutomationFailure(code: "invalid_config", message: "Unable to read the configuration. The file has not been changed.")
        } catch {
            throw AutomationFailure(code: "config_write_failed", message: "Unable to update the configuration.")
        }
    }

    func requireTarget(_ id: String?) throws {
        guard let id, !id.isEmpty else {
            throw AutomationFailure(code: "no_target", message: "No input source is selected. Use keypin set <source-id> first.")
        }
        guard services.choices().contains(where: { $0.id == id }) else {
            throw AutomationFailure(code: "missing_source", message: "The selected input source is not available. Run keypin list and select an available source.")
        }
    }
}
