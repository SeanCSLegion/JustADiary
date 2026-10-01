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

    /// 当前主题模式的稳定标识，给 `RootView` 的 `.id(...)` 用。
    ///
    /// 主题与语言是**唯一**需要整棵树换 identity 的两项设置：文案与配色是全局的，
    /// 改一次就得全部重来（画布里缓存的文字颜色也一起换）。其余设置项只广播
    /// `uiTickChanged`，见 `RootView.treeIdentity` 的说明。
    static var themeID: String {
        SettingsStore.load().themeMode
    }

    static func applyAll() {
        // The calendar canvases cache resolved text with the color baked in.
        // Drop it on every settings change so a theme switch re-resolves the
        // dynamic colors immediately instead of keeping the previous scheme.
        DayDraw.clearCache()
        DiaryRepository.shared.bumpUiTick()
    }
}
