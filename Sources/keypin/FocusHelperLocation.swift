import Foundation

/// A different bundle identity keeps Sparkle's host-process lookup unambiguous.
/// The helper must never fall back to the GUI executable, even for local builds.
enum FocusHelperLocation {
    static let bundleIdentifier = "app.keypin.focus-helper"
    static let bundlePath = "Contents/Helpers/KeyPin Focus Helper.app"
    static let executableName = "keypin-focus"

    enum Failure: Error, Equatable, LocalizedError {
        case applicationRequired
        case helperUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationRequired: L10n.text("enf.helper-app-required")
            case .helperUnavailable: L10n.text("enf.helper-unavailable")
            }
        }
    }

    static func executable(in application: Bundle, fileManager: FileManager = .default) throws -> URL {
        guard application.bundleURL.pathExtension == "app", application.bundleIdentifier == "app.keypin" else {
            throw Failure.applicationRequired
        }
        let helperURL = application.bundleURL.resolvingSymlinksInPath().appendingPathComponent(bundlePath, isDirectory: true)
        let expected = helperURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard let helper = Bundle(url: helperURL), helper.bundleIdentifier == bundleIdentifier,
              helper.executableURL?.standardizedFileURL == expected.standardizedFileURL,
              expected.resolvingSymlinksInPath() == expected.standardizedFileURL,
              fileManager.isExecutableFile(atPath: expected.path) else {
            throw Failure.helperUnavailable
        }
        return expected
    }
}

enum FocusHelperInvocation: Equatable {
    case application
    case focus(sourceID: String)
    case reject

    /// Runs before configuration loading or AppKit initialization. Opening the
    /// nested bundle cannot start another GUI, CLI, updater, or preview process.
    static func resolve(bundleIdentifier: String?, arguments: [String]) -> Self {
        guard bundleIdentifier == FocusHelperLocation.bundleIdentifier else {
            return arguments.first == "focus" ? .reject : .application
        }
        guard arguments.first == "focus", (2...3).contains(arguments.count), !arguments[1].isEmpty,
              arguments.count == 2 || arguments[2] == "--automatic" else { return .reject }
        return .focus(sourceID: arguments[1])
    }
}
