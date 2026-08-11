import SwiftUI
import Darwin

@main
struct JustDiaryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "justdiary" else { return }
        if url.host == "editor" {
            let dayKey = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "dayKey" })?.value
            LaunchIntent.openEditor(dayKey: dayKey)
        } else {
            LaunchIntent.openEditor()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        installCrashLogger()
        AppConfigService.applyThemeMode()
        return true
    }

    private func installCrashLogger() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let log = "EXCEPTION: \(exception.name) \(exception.reason ?? "")\n\(stack)\n"
            try? log.write(toFile: NSHomeDirectory() + "/Documents/crash.log", atomically: true, encoding: .utf8)
        }
        func crashHandler(_ sig: Int32) {
            var stack = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
            let frameCount = stack.withUnsafeMutableBufferPointer { buf in
                backtrace(buf.baseAddress, 64)
            }
            var log = "SIGNAL \(sig) at \(Date())\n"
            if let symbols = stack.withUnsafeBufferPointer({ buf in
                backtrace_symbols(buf.baseAddress, frameCount)
            }) {
                for i in 0..<Int(frameCount) {
                    if let sym = symbols[i] {
                        log += String(cString: sym) + "\n"
                    }
                }
                free(symbols)
            }
            try? log.write(toFile: NSHomeDirectory() + "/Documents/crash.log", atomically: true, encoding: .utf8)
        }
        signal(SIGABRT, crashHandler)
        signal(SIGILL, crashHandler)
        signal(SIGTRAP, crashHandler)
        signal(SIGSEGV, crashHandler)
        signal(SIGBUS, crashHandler)
        signal(SIGFPE, crashHandler)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task {
            await DiaryRepository.shared.prepare()
            await ReminderService.rearm()
        }
    }
}
