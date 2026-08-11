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
        let mode = SettingsStore.load().themeMode
        let style: UIUserInterfaceStyle
        switch mode {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    static func applyAll() {
        applyThemeMode()
        DiaryRepository.shared.bumpUiTick()
    }
}
