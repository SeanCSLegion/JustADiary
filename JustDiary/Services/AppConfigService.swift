import SwiftUI

enum AppConfigService {
    static var colorScheme: ColorScheme? {
        switch SettingsStore.load().themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    static func applyThemeMode() {}

    static func applyAll() {
        DiaryRepository.shared.bumpUiTick()
    }
}
