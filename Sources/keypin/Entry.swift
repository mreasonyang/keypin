import AppKit
import Darwin

@main
@MainActor
enum Entry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch FocusHelperInvocation.resolve(bundleIdentifier: Bundle.main.bundleIdentifier, arguments: arguments) {
        case .focus(let sourceID):
            FocusHelper.run(id: sourceID)
        case .reject:
            fputs("KeyPin's focus helper must be launched by the installed application.\n", stderr)
            exit(EX_USAGE)
        case .application:
            break
        }
        #if DEBUG
        if arguments.first == "preview" || (Bundle.main.bundleIdentifier?.hasPrefix("app.keypin.preview") == true) {
            let previewArguments = arguments.first == "preview" ? arguments : (Bundle.main.object(forInfoDictionaryKey: "KeyPinPreviewArguments") as? [String] ?? ["preview", "active", "zh-Hans", "light"])
            Preview.configure(arguments: previewArguments)
            launchGUI()
            return
        }
        #endif
        L10n.languageCode = L10n.normalized(ConfigStore.load().language)
        // background：登录项悄悄留在菜单栏，不弹窗口。
        // gui，或从访达 / open 启动：菜单栏加上设置窗口。
        if arguments.first == "gui" || arguments.first == "background" {
            AppController.shared.openWindowOnLaunch = arguments.first == "gui"
            launchGUI()
            return
        }
        if arguments.isEmpty && launchedFromDesktop() {
            AppController.shared.openWindowOnLaunch = true
            launchGUI()
            return
        }
        CLI.main(arguments)
    }

    /// 从访达、程序坞或 open 启动时没有参数，父进程是 launchd（路径是 /sbin/launchd，不是名字 launchd）。
    /// 终端里运行则父进程是 shell，走命令行。
    private static func launchedFromDesktop() -> Bool {
        let parent = parentExecutableName()
        return parent == "launchd" || parent == "open" || parent == "Finder" || parent == "Dock"
    }

    private static func parentExecutableName() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(getppid(), &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    private static func launchGUI() {
        let app = NSApplication.shared
        app.delegate = AppController.shared
        app.run()
    }
}
