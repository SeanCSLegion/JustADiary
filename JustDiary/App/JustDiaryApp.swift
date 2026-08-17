import SwiftUI

extension String {
    func appendToFile2(_ path: String) throws {
        if let data = data(using: .utf8) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
        }
    }
}

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
        if ProcessInfo.processInfo.arguments.contains("-ui-test-reset-settings") {
            SettingsStore.save(AppSettings())
        }
        AppConfigService.applyThemeMode()
        Log.app.info("app launched v\(SettingsStore.appVersion, privacy: .public)")
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task {
            await DiaryRepository.shared.prepare()
            await ReminderService.rearm()
        }
    }
}
