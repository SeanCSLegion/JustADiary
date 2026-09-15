import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home
    case footprint
    case search
    case settings

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .footprint: return "figure.walk"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return L10n.str("index_title")
        case .footprint: return L10n.str("footprint_title")
        case .search: return L10n.str("search_title")
        case .settings: return L10n.str("settings_title")
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appState = AppState()

    private var activeTab: Binding<AppTab> {
        Binding(get: { appState.activeTab }, set: { appState.activeTab = $0 })
    }

    var body: some View {
        // Read the ui tick inside body so a .uiTickChanged notification (language,
        // theme, week start, …) invalidates RootView and re-evaluates the modifiers
        // below (.preferredColorScheme / .environment(\.locale) / .id). Without the
        // read, @Observable invalidation would not reach RootView and language/theme
        // changes would only take effect after the app is restarted.
        let settingsTick = appState.uiTick
        return TabView(selection: activeTab) {
            Tab(L10n.str("index_title"), systemImage: "house.fill", value: AppTab.home) {
                HomeView(openEditor: { dayKey in
                    appState.editorDayKey = dayKey
                    appState.presentEditor = true
                })
                .diaryBackground()
            }
            Tab(L10n.str("footprint_title"), systemImage: "figure.walk", value: AppTab.footprint) {
                FootprintView()
                    .diaryBackground()
            }
            Tab(L10n.str("search_title"), systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView(openDiary: { dayKey in
                    appState.editorDayKey = dayKey
                    appState.presentEditor = true
                })
                .diaryBackground()
            }
            Tab(L10n.str("settings_title"), systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
                    .diaryBackground()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.primary())
        .preferredColorScheme(AppConfigService.colorScheme)
        // Publish the system text-size scale so the explicit design sizes can
        // follow 设置 › 显示与亮度 › 文字大小.
        .environment(\.diaryTypeScale, DynamicTypeScale.value(for: dynamicTypeSize))
        .environment(\.locale, AppLanguage.locale)
        // Rebuild the whole tree whenever the language or any settings-driven UI
        // tick changes. This guarantees all L10n strings, the color scheme and the
        // canvas layers re-render immediately instead of after an app restart.
        .id("\(AppLanguage.current)#\(settingsTick)")
        .overlay(alignment: .topLeading) {
            // UI-test-only probe that exposes the live app language/theme through
            // the accessibility tree. It reads the ui tick so it always reflects
            // the latest app state, independent of whether the tab tree rebuilt.
            if ProcessInfo.processInfo.arguments.contains("-ui-test-state") {
                Text(appStateProbeText())
                    .diaryFont(1)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("app.state")
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { appState.presentEditor },
            set: { appState.presentEditor = $0 }), onDismiss: {
            DiaryRepository.shared.bumpDiaryVersion()
        }) {
            DiaryPageView(dayKey: appState.editorDayKey)
        }
        .task {
            await DiaryRepository.shared.prepare()
            await ReminderService.rearm()
            if let tabIdx = ProcessInfo.processInfo.arguments.firstIndex(of: "-ui-test-tab"),
               ProcessInfo.processInfo.arguments.count > tabIdx + 1 {
                let tab = ProcessInfo.processInfo.arguments[tabIdx + 1]
                switch tab {
                case "footprint", "map": appState.activeTab = .footprint
                case "search": appState.activeTab = .search
                case "settings": appState.activeTab = .settings
                default: appState.activeTab = .home
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-test-open-editor") {
                LaunchIntent.openEditor(dayKey: DateUtil.dayKeyOf(Date()))
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-test-import") {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    await BackupService.runAutoImport()
                    DiaryRepository.shared.bumpDiaryVersion()
                    DiaryRepository.shared.bumpUiTick()
                }
            }
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-ui-test-open-day"),
               ProcessInfo.processInfo.arguments.count > idx + 1 {
                let key = ProcessInfo.processInfo.arguments[idx + 1]
                appState.editorDayKey = key
                appState.presentEditor = true
            }
            consumeLaunchIntent()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await ReminderService.rearm() }
            consumeLaunchIntent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            appState.uiTick += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await ReminderService.rearm() }
                consumeLaunchIntent()
            }
        }
    }

    private func consumeLaunchIntent() {
        guard LaunchIntent.target == "editor" else { return }
        let dayKey = LaunchIntent.dayKey.isEmpty ? nil : LaunchIntent.dayKey
        LaunchIntent.clear()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            appState.editorDayKey = dayKey
            appState.presentEditor = true
        }
    }

    /// UI-test-only: live language/theme snapshot used by `-ui-test-state`.
    private func appStateProbeText() -> String {
        let scheme: String
        switch AppConfigService.colorScheme {
        case .light: scheme = "light"
        case .dark: scheme = "dark"
        default: scheme = "nil"
        }
        return "L:\(AppLanguage.current)|T:\(scheme)|tick:\(appState.uiTick)"
    }
}
