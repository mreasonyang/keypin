import Foundation

enum L10n {
    /// 从 `~/.local/bin` 的符号链接启动时，Bundle.main 不是 .app，字符串会退回键名。
    static let appBundle: Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let app = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if app.pathExtension == "app", let bundle = Bundle(url: app) {
            return bundle
        }
        return Bundle.main
    }()

    /// 空表示跟随系统。只接受应用里带了文案的五种语言。
    static var languageCode: String?

    static func normalized(_ code: String?) -> String? {
        switch code {
        case "en", "zh-Hans", "zh-Hant", "ja", "ko":
            return code
        default:
            return nil
        }
    }

    private static var strings: Bundle {
        // Read the system preference independently of an old per-app AppleLanguages override.
        let systemLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
        let code = languageCode ?? Bundle.preferredLocalizations(from: ["en", "zh-Hans", "zh-Hant", "ja", "ko"], forPreferences: systemLanguages).first ?? "en"
        guard let url = appBundle.url(forResource: code, withExtension: "lproj"), let bundle = Bundle(url: url) else { return appBundle }
        return bundle
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: strings, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: args)
    }
}
