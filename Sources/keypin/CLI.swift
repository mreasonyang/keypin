import AppKit
import Darwin
import Foundation

enum CLI {
    static var automation: Automation { Automation(services: .live) }

    static var usage: String {
        [
            "cli.usage.header", "cli.usage.status", "cli.usage.list", "cli.usage.pause",
            "cli.usage.resume", "cli.usage.toggle", "cli.usage.set", "cli.usage.apply",
            "cli.usage.open", "cli.usage.install", "cli.usage.uninstall",
        ].map(L10n.text).joined(separator: "\n")
    }

    static func main(_ arguments: [String]) {
        let request: CLIRequest
        do { request = try CLIRequest.parse(arguments) }
        catch {
            fail(failure(error), command: arguments.first(where: { $0 != "--json" }) ?? "status",
                 json: arguments.contains("--json"), human: usage)
        }
        do {
            switch request.command {
            case .status:
                report(try automation.status(), for: request)
            case .pause, .resume, .toggle:
                report(try automation.setKeeping(request.command), for: request)
            case .list:
                let sources = Catalog.choices().map { AutomationSource(id: $0.id, name: $0.name) }
                if request.json {
                    emit(AutomationResponse(ok: true, command: "list", sources: sources))
                } else {
                    let current = Catalog.current().id
                    for source in sources { print("\(source.id == current ? "*" : " ") \(source.id)  \(source.name)") }
                }
            case .set:
                let id = request.sourceID!
                try automation.requireTarget(id)
                _ = try automation.editConfig { $0.sourceID = id; $0.onboardingCompleted = true }
                runOnce(request)
            case .apply:
                try automation.requireTarget(automation.readConfig().sourceID)
                runOnce(request)
            case .install:
                let id = request.sourceID!
                try automation.requireTarget(id)
                _ = try automation.editConfig { $0.sourceID = id; $0.enabled = true; $0.onboardingCompleted = true }
                do { try Agent.install(executable: executableURL()) }
                catch { fail(AutomationFailure(code: "install_failed", message: "Unable to install the login item."), for: request, human: String(describing: error)) }
                if request.json { report(try automation.status(), for: request) }
                else {
                    print(L10n.format("cli.msg.pinned", id))
                    print(L10n.format("cli.msg.login", L10n.text("app.name")))
                }
            case .uninstall:
                do { try Agent.uninstall() }
                catch { fail(AutomationFailure(code: "uninstall_failed", message: "Unable to remove the login item."), for: request, human: String(describing: error)) }
                if request.json { report(try automation.status(), for: request) }
                else { print(L10n.format("cli.msg.uninstalled", ConfigStore.file.path)) }
            case .open:
                try openApp()
                if request.json { report(try automation.status(), for: request) }
            case .help:
                print(usage)
            }
        } catch {
            fail(failure(error), for: request)
        }
    }

    static func report(_ status: AutomationStatus, for request: CLIRequest) {
        if request.json { emit(AutomationResponse(ok: true, command: request.command.rawValue, status: status)) }
        else { printStatus(status) }
    }

    static func printStatus(_ status: AutomationStatus) {
        let onOff: (Bool) -> String = { L10n.text($0 ? "cli.on" : "cli.off") }
        let line: (String, String) -> Void = { print(L10n.format("cli.line", L10n.text($0), $1)) }
        line("cli.label.state", L10n.text(status.state.localizationKey))
        line("cli.label.running", onOff(status.running))
        line("cli.label.current", "\(status.current.name)  \(status.current.id)")
        if let target = status.target {
            line("cli.label.pinned", target.name.map { "\($0)  \(target.id)" } ?? target.id)
        } else { line("cli.label.pinned", L10n.text("cli.unset")) }
        line("cli.label.keep", onOff(status.enabled))
        line("cli.label.login", onOff(status.loginEnabled))
        if !status.running { print(L10n.text("cli.msg.stopped")) }
    }

    static func openApp() throws {
        let app = executableURL().resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else {
            throw AutomationFailure(code: "not_app_bundle", message: "This command must run from the packaged KeyPin application.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", app.path, "--args", "gui"]
        do { try process.run() }
        catch { throw AutomationFailure(code: "open_failed", message: "Unable to open KeyPin.") }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AutomationFailure(code: "open_failed", message: "Unable to open KeyPin.")
        }
    }

    static func executableURL() -> URL {
        if let bundled = Bundle.main.executableURL, Bundle.main.bundleURL.pathExtension == "app" { return bundled }
        return URL(fileURLWithPath: CommandLine.arguments[0])
    }

    static func runOnce(_ request: CLIRequest) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            Enforcer.shared.enforce(force: true) { outcome in
                switch outcome {
                case .success:
                    if request.json {
                        do { report(try automation.status(), for: request) }
                        catch { fail(failure(error), for: request) }
                    }
                    exit(0)
                case .secureInput:
                    fail(AutomationFailure(code: "secure_input", message: "Switching is temporarily paused during secure input."), for: request, human: L10n.text("enf.secure"))
                case .missingSource:
                    fail(AutomationFailure(code: "missing_source", message: "The selected input source is not available."), for: request, human: L10n.text("warn.missing"))
                case .failed(let message):
                    fail(AutomationFailure(code: "switch_failed", message: "The input source could not be switched."), for: request, human: message)
                case .busy:
                    fail(AutomationFailure(code: "busy", message: "Another switching operation is in progress."), for: request, human: L10n.text("warn.busy"))
                }
            }
        }
        app.run()
        fail(AutomationFailure(code: "switch_failed", message: "The switching operation ended without a result."), for: request)
    }

    static func failure(_ error: Error) -> AutomationFailure {
        (error as? AutomationFailure) ?? AutomationFailure(code: "operation_failed", message: "The operation could not be completed.")
    }

    static func emit(_ response: AutomationResponse) {
        // All stored values are JSON-safe scalars and strings; encoding cannot fail in practice.
        do { print(try response.encoded()) }
        catch { print("{\"schemaVersion\":1,\"ok\":false,\"command\":\"unknown\",\"error\":{\"code\":\"encoding_failed\",\"message\":\"Unable to encode the response.\"}}") }
    }

    static func fail(_ error: AutomationFailure, for request: CLIRequest, human: String? = nil) -> Never {
        fail(error, command: request.command.rawValue, json: request.json, human: human)
    }

    static func fail(_ error: AutomationFailure, command: String, json: Bool, human: String? = nil) -> Never {
        if json { emit(AutomationResponse(ok: false, command: command, error: error)) }
        else {
            let message: String
            if let human { message = human }
            else {
                switch error.code {
                case "invalid_config": message = L10n.text("warn.config")
                case "no_target": message = L10n.text("cli.err.no-pin")
                case "missing_source": message = L10n.text("warn.missing")
                case "not_app_bundle": message = L10n.text("cli.err.not-app")
                case "runtime_unavailable": message = L10n.text("cli.err.runtime")
                case "config_write_failed": message = L10n.format("cli.err.write", error.message)
                case "open_failed": message = L10n.format("cli.err.open", error.message)
                default: message = error.message
                }
            }
            fputs(message + "\n", stderr)
        }
        exit(1)
    }
}
