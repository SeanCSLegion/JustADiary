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
        AppConfigService.applyThemeMode()
        Log.app.info("app launched v\(SettingsStore.appVersion, privacy: .public)")
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task {
            await DiaryRepository.shared.prepare()
            await ReminderService.rearm()
            if ProcessInfo.processInfo.arguments.contains("-ui-test-import") {
                await runAutoImport()
            }
        }
    }

    private func runAutoImport() async {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ui-test-import"), args.count > idx + 1 else { return }
        let path = args[idx + 1]
        let mode = args.contains("-ui-test-import-overwrite") ? "overwrite" : "skip"
        let resultLog = NSHomeDirectory() + "/Documents/import-result.log"
        try? "start import \(path) mode=\(mode)\n".write(toFile: resultLog, atomically: true, encoding: .utf8)
        do {
            let stats = try await BackupService.importBackup(fileURL: URL(fileURLWithPath: path), mode: mode)
            let msg = """
            OK importedDays=\(stats.importedDays) skippedDays=\(stats.skippedDays) overwrittenDays=\(stats.overwrittenDays) blocks=\(stats.importedBlocks) images=\(stats.importedImages) settings=\(stats.settingsRestored)
            """
            try? msg.appendToFile2(resultLog)
            try? msg.write(toFile: NSHomeDirectory() + "/Documents/import-ok.log", atomically: true, encoding: .utf8)
        } catch {
            try? "FAIL \(error)\n".write(toFile: NSHomeDirectory() + "/Documents/import-fail.log", atomically: true, encoding: .utf8)
            try? "FAIL \(error)\n".appendToFile2(resultLog)
        }
    }
}
