import Foundation

enum Agent {
    static let label = "app.keypin"
    private static let controller = AgentController(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        domain: "gui/\(getuid())"
    )

    static func install(executable: URL, installCLICommand: Bool = true) throws {
        try controller.install(executable: executable, installCLICommand: installCLICommand)
    }

    /// Turning off login startup in the GUI must leave the current application open.
    /// The CLI's explicit uninstall also stops the registered background instance.
    static func uninstall(stopRunningAgent: Bool = true) throws {
        try controller.uninstall(stopRunningAgent: stopRunningAgent)
    }

    static var isLoginEnabled: Bool { controller.isLoginEnabled }
}

struct LaunchctlResult {
    let status: Int32
    var output = ""
}

/// All paths and process execution are injectable so tests never touch the user's job.
struct AgentController {
    let homeDirectory: URL
    let domain: String
    var fileManager = FileManager.default
    var runLaunchctl: ([String]) -> LaunchctlResult = AgentController.launchctl

    var plist: URL { homeDirectory.appendingPathComponent("Library/LaunchAgents/app.keypin.plist") }
    var symlink: URL { homeDirectory.appendingPathComponent(".local/bin/keypin") }
    private var service: String { "\(domain)/\(Agent.label)" }

    var isLoaded: Bool { runLaunchctl(["print", service]).status == 0 }

    /// A loaded job can remain running after login startup is turned off.
    /// Conversely, a plist may exist while launchd has explicitly disabled its job.
    var isLoginEnabled: Bool {
        guard fileManager.fileExists(atPath: plist.path),
              let disabled = try? isDisabled() else { return false }
        return !disabled
    }

    func install(executable: URL, installCLICommand: Bool = true) throws {
        let binary = executable.resolvingSymlinksInPath()
        guard fileManager.isExecutableFile(atPath: binary.path) else {
            throw AgentError(L10n.format("agent.executable", binary.path))
        }

        let previousPlist = fileManager.fileExists(atPath: plist.path) ? try Data(contentsOf: plist) : nil
        let shouldCreateCommand = installCLICommand ? try needsCommand(binary: binary) : false

        let wasDisabled = try isDisabled()
        let wasLoaded = isLoaded
        let data = try Self.agentPlist(binary: binary)
        var wrotePlist = false
        var createdCommand = false
        var enabled = false
        do {
            try fileManager.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plist, options: .atomic)
            wrotePlist = true
            if shouldCreateCommand {
                try fileManager.createDirectory(at: symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Creation fails if another file appears after the conflict check.
                try fileManager.createSymbolicLink(at: symlink, withDestinationURL: binary)
                createdCommand = true
            }
            // A previous uninstall persists a disabled override; enable before bootstrap.
            try requireSuccess(["enable", service])
            enabled = true
            // Never boot out a live job here: it may be this very GUI process. Updated
            // executable paths take effect on the next login when the plist is loaded.
            if !wasLoaded {
                try requireSuccess(["bootstrap", domain, plist.path])
            }
        } catch {
            var cleanupErrors: [String] = []
            if wrotePlist {
                do {
                    if let previousPlist {
                        try previousPlist.write(to: plist, options: .atomic)
                    } else {
                        try fileManager.removeItem(at: plist)
                    }
                } catch { cleanupErrors.append(String(describing: error)) }
            }
            if createdCommand {
                do { try removeCreatedCommand(binary: binary) }
                catch { cleanupErrors.append(String(describing: error)) }
            }
            if enabled && wasDisabled {
                do { try requireSuccess(["disable", service]) }
                catch { cleanupErrors.append(String(describing: error)) }
            }
            if !cleanupErrors.isEmpty {
                throw AgentError(L10n.format("agent.rollback", String(describing: error), cleanupErrors.joined(separator: "; ")))
            }
            throw error
        }
    }

    /// Only an absent command or a link to this exact executable is usable.
    private func needsCommand(binary: URL) throws -> Bool {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: symlink.path) {
            let target = URL(fileURLWithPath: destination, relativeTo: symlink.deletingLastPathComponent())
                .standardizedFileURL.resolvingSymlinksInPath()
            guard target == binary else {
                throw AgentError(L10n.format("agent.command-conflict", symlink.path))
            }
            return false
        }
        guard !fileManager.fileExists(atPath: symlink.path) else {
            throw AgentError(L10n.format("agent.command-conflict", symlink.path))
        }
        return true
    }

    private func removeCreatedCommand(binary: URL) throws {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: symlink.path) {
            guard destination == binary.path else {
                throw AgentError(L10n.format("agent.command-conflict", symlink.path))
            }
            try fileManager.removeItem(at: symlink)
        } else if fileManager.fileExists(atPath: symlink.path) {
            // Preserve a file that another process replaced during installation.
            throw AgentError(L10n.format("agent.command-conflict", symlink.path))
        }
    }

    func uninstall(stopRunningAgent: Bool = true) throws {
        // Finish durable cleanup before any operation that might terminate this process.
        if fileManager.fileExists(atPath: plist.path) {
            let values = try plist.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else {
                throw AgentError(L10n.format("agent.plist-conflict", plist.path))
            }
            try fileManager.removeItem(at: plist)
        }
        try requireSuccess(["disable", service])
        if stopRunningAgent && isLoaded {
            try requireSuccess(["bootout", service])
        }
    }

    static func agentPlist(binary: URL) throws -> Data {
        // PropertyListSerialization escapes &, <, > and other legal path characters.
        try PropertyListSerialization.data(fromPropertyList: [
            "Label": Agent.label,
            "ProgramArguments": [binary.path, "background"],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "KeepAlive": ["SuccessfulExit": false],
        ], format: .xml, options: 0)
    }

    private func isDisabled() throws -> Bool {
        let result = runLaunchctl(["print-disabled", domain])
        guard result.status == 0 else {
            throw AgentError(L10n.format("agent.command-failed", "print-disabled", result.status))
        }
        // launchctl does not offer a structured API for this state. Reject unrecognized
        // output instead of claiming login startup is enabled after an inspection error.
        guard result.output.contains("disabled services = {"), result.output.contains("}") else {
            throw AgentError(L10n.text("agent.state-unavailable"))
        }
        let escaped = NSRegularExpression.escapedPattern(for: Agent.label)
        let expression = try NSRegularExpression(pattern: "\"\(escaped)\"\\s*=>\\s*([^\\s,;}]+)")
        let range = NSRange(result.output.startIndex..., in: result.output)
        guard let match = expression.firstMatch(in: result.output, range: range),
              let valueRange = Range(match.range(at: 1), in: result.output) else {
            return false // Absence of an override means enabled.
        }
        switch result.output[valueRange] {
        case "true", "disabled": return true
        case "false", "enabled": return false
        default: throw AgentError(L10n.text("agent.state-unavailable"))
        }
    }

    private func requireSuccess(_ arguments: [String]) throws {
        let result = runLaunchctl(arguments)
        guard result.status == 0 else {
            throw AgentError(L10n.format("agent.command-failed", arguments[0], result.status))
        }
    }

    private static func launchctl(_ arguments: [String]) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { return LaunchctlResult(status: 1) }
        // Drain the pipe before waiting, so larger diagnostic output cannot fill it.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return LaunchctlResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

struct AgentError: Error, CustomStringConvertible, LocalizedError {
    let description: String
    var errorDescription: String? { description }
    init(_ description: String) { self.description = description }
}
