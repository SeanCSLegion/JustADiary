import SwiftUI

/// The four root tabs.
///
/// Only the case values are used: each `Tab` in `RootView` supplies its own
/// title and `systemImage` inline, so the former `icon` / `label` helpers (and
/// the unused `CaseIterable` conformance) were dead code.
enum AppTab: Hashable {
    case home
    case footprint
    case search
    case settings
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
        // 导航形态用系统默认的底部浮条，不引入第二套导航。实测（见
        // docs/adaptive-layout-plan.md §2.2）系统在横屏仍把浮条留在底部居中，
        // 所以横屏不需要我们做任何导航侧的改动。
        .tint(Theme.primary())
        .preferredColorScheme(AppConfigService.colorScheme)
        // Publish the system text-size category so the explicit design sizes can
        // follow 设置 › 显示与亮度 › 文字大小. The category (not a pre-multiplied
        // factor) is what lets `DynamicTypeMetrics` scale each role on Apple's
        // own curve for its text style.
        .environment(\.diaryDynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, AppLanguage.locale)
        // 版面判定只在这里读一次几何：所有页面用 @Environment(\.adaptiveLayout)。
        .adaptiveLayoutReader()
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
            // The cover inherits the environment from the view it is attached
            // to, but the `.environment(\.diaryDynamicTypeSize, …)` above is
            // applied further in, so the editor was reading the default
            // category and none of its text followed 设置 › 文字大小. Inject it
            // explicitly here as well.
            DiaryPageView(dayKey: appState.editorDayKey)
                .environment(\.diaryDynamicTypeSize, dynamicTypeSize)
                .environment(\.locale, AppLanguage.locale)
                // 与上面同理：presentation 不会从更内层继承环境，这里补上版面判定
                // （编辑器在横屏要限宽、格式栏要贴右侧）。
                .adaptiveLayoutReader()
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
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-ui-test-open-day"),
               ProcessInfo.processInfo.arguments.count > idx + 1 {
                let key = ProcessInfo.processInfo.arguments[idx + 1]
                if ProcessInfo.processInfo.arguments.contains("-ui-test-reset-data") {
                    // UI-test hook: start the editor round-trip tests from a
                    // clean day. Only the day being opened is touched, so the
                    // sample data other screens' tests use survives.
                    await DiaryRepository.shared.deleteDiaryByDay(key)
                    DiaryRepository.shared.bumpDiaryVersion()
                }
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
