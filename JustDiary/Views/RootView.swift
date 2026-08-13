import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home
    case map
    case search
    case settings

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .map: return "map.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return L10n.str("index_title")
        case .map: return L10n.str("map_title")
        case .search: return L10n.str("search_title")
        case .settings: return L10n.str("settings_title")
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    private var activeTab: Binding<AppTab> {
        Binding(get: { appState.activeTab }, set: { appState.activeTab = $0 })
    }

    var body: some View {
        TabView(selection: activeTab) {
            Tab(L10n.str("index_title"), systemImage: "house.fill", value: AppTab.home) {
                HomeView(openEditor: { dayKey in
                    appState.editorDayKey = dayKey
                    appState.presentEditor = true
                })
                .diaryBackground()
            }
            Tab(L10n.str("map_title"), systemImage: "map.fill", value: AppTab.map) {
                MapView(openDiary: { dayKey in
                    appState.editorDayKey = dayKey
                    appState.presentEditor = true
                })
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
        .environment(\.locale, AppLanguage.locale)
        .id(AppLanguage.current)
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
                case "map": appState.activeTab = .map
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
}
