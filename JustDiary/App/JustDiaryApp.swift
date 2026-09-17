import SwiftUI
import os

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
        if ProcessInfo.processInfo.arguments.contains("-ui-test-no-autoloc") {
            // UI-test hook: an entry with no location now asks before saving, so
            // tests that are not about location turn the lookup off and stay
            // independent of the simulator's simulated position.
            var settings = SettingsStore.load()
            settings.autoLoc = false
            SettingsStore.save(settings)
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
