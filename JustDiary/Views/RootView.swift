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

    /// 决定整棵 tab 树是否换 identity（SwiftUI 的 `.id`）。
    ///
    /// **只有语言与主题**在 identity 里：文案与配色是全局的，改一次就得整棵树重建
    /// （画布里缓存的文字颜色也一起换）。
    ///
    /// 其余设置项（周起始、时间显示、分享精度、历史编辑…）**不换 identity** ——
    /// 它们只广播 `uiTickChanged`，常驻的那几页收到后刷新自己那份 `settings`，
    /// 由 `@Observable` 决定到底重画哪一块。以前把 tick 也塞进 `.id`，于是改任何一个
    /// 开关都会把四个 tab（连同搜索关键词、结果、滚动位置）整个重建掉。
    ///
    /// 读一下 `uiTick` 是为了订阅「设置有变化」这件事本身：语言 / 主题变化也会 bump 它，
    /// body 才会重新求值、`AppLanguage.current` 与 `themeID` 的新值才会进到 identity 里。
    private var treeIdentity: String {
        let _ = appState.uiTick
        return "\(AppLanguage.current)#\(AppConfigService.themeID)"
    }

    var body: some View {
        return NavigationStack(path: $appState.diaryPath) {
            TabView(selection: activeTab) {
                Tab(L10n.str("index_title"), systemImage: "house.fill", value: AppTab.home) {
                    HomeView(openEditor: { dayKey in
                        appState.openDiary(dayKey: dayKey)
                    })
                    .diaryBackground()
                }
                Tab(L10n.str("footprint_title"), systemImage: "figure.walk", value: AppTab.footprint) {
                    FootprintView()
                        .diaryBackground()
                }
                Tab(L10n.str("search_title"), systemImage: "magnifyingglass", value: AppTab.search) {
                    SearchView(openDiary: { dayKey in
                        appState.openDiary(dayKey: dayKey)
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
            .id(treeIdentity)
            // 日记页：系统的从右往左推进 + 边缘右滑返回，顶栏按钮由页面自己画
            // （见 `DiaryPageView.topBarOverlay`），所以把导航栏整条藏起来。
            .navigationDestination(for: DiaryRoute.self) { route in
                DiaryPageView(dayKey: route.dayKey)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .tint(Theme.primary())
        .preferredColorScheme(AppConfigService.colorScheme)
        // Publish the system text-size category so the explicit design sizes can
        // follow 设置 › 显示与亮度 › 文字大小. The category (not a pre-multiplied
        // factor) is what lets `DynamicTypeMetrics` scale each role on Apple's
        // own curve for its text style.
        .environment(\.diaryDynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, AppLanguage.locale)
        // 版面判定只在这里读一次几何：所有页面用 @Environment(\.adaptiveLayout)。
        // 挂在导航栈上（而不是 TabView 上）：推进出来的日记页是栈的兄弟节点，
        // 挂在里层它就读不到。
        .adaptiveLayoutReader()
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
                appState.openDiary(dayKey: key)
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
        // 从日记页回到日历（点返回、右滑返回都一样走这里）：主页日历要重画
        // 那一天的小圆点。以前这活挂在 cover 的 `onDismiss` 上。
        .onChange(of: appState.diaryPath) { _, path in
            if path.isEmpty {
                DiaryRepository.shared.bumpDiaryVersion()
            }
        }
    }

    private func consumeLaunchIntent() {
        guard LaunchIntent.target == "editor" else { return }
        let dayKey = LaunchIntent.dayKey.isEmpty ? nil : LaunchIntent.dayKey
        LaunchIntent.clear()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            appState.openDiary(dayKey: dayKey)
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
