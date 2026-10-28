import Foundation

enum GUILaunchMode {
    case desktop, background, explicitWindow
}

enum LaunchPresentation {
    static let lastBuildKey = "KeyPinLastGUIBuild"

    /// Sparkle reopens the bundle just like Finder, without the original `background`
    /// argument. Record successful GUI starts so a changed build stays in the menu
    /// bar. A missing record also covers upgrades from versions predating this policy.
    /// Call only after acquiring the GUI instance lock; CLI and helpers never write it.
    static func recordLaunch(mode: GUILaunchMode, requiresAttention: Bool,
                             build: String?, defaults: UserDefaults = .standard) -> Bool {
        let previousBuild = defaults.string(forKey: lastBuildKey)
        let currentBuild = build.flatMap { $0.isEmpty ? nil : $0 }
        if let currentBuild { defaults.set(currentBuild, forKey: lastBuildKey) }

        switch mode {
        case .background:
            return false
        case .explicitWindow:
            return true
        case .desktop:
            return requiresAttention || currentBuild == nil || currentBuild == previousBuild
        }
    }
}
