import SwiftUI

enum AppConfigService {
    static var colorScheme: ColorScheme? {
        switch SettingsStore.load().themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    static func applyThemeMode() {
        // Colors resolve against UIKit traits; nothing to apply statically.
    }

    static func applyAll() {
        // The calendar canvases cache resolved text with the color baked in.
        // Drop it on every settings change so a theme switch re-resolves the
        // dynamic colors immediately instead of keeping the previous scheme.
        DayDraw.clearCache()
        DiaryRepository.shared.bumpUiTick()
    }
}
