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
    @State private var activeTab: AppTab = .home
    @State private var presentEditor = false
    @State private var editorDayKey: String?

    var body: some View {
        TabView(selection: $activeTab) {
            Tab(L10n.str("index_title"), systemImage: "house.fill", value: AppTab.home) {
                HomeView(openEditor: { dayKey in
                    editorDayKey = dayKey
                    presentEditor = true
                })
                .diaryBackground()
            }
            Tab(L10n.str("map_title"), systemImage: "map.fill", value: AppTab.map) {
                MapView(openDiary: { dayKey in
                    editorDayKey = dayKey
                    presentEditor = true
                })
                .diaryBackground()
            }
            Tab(L10n.str("search_title"), systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView(openDiary: { dayKey in
                    editorDayKey = dayKey
                    presentEditor = true
                })
                .diaryBackground()
            }
            Tab(L10n.str("settings_title"), systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
                    .diaryBackground()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(AppConfigService.colorScheme)
        .fullScreenCover(isPresented: $presentEditor, onDismiss: {
            DiaryRepository.shared.bumpDiaryVersion()
        }) {
            DiaryPageView(dayKey: editorDayKey)
        }
        .task {
            await DiaryRepository.shared.prepare()
            await ReminderService.rearm()
            if ProcessInfo.processInfo.arguments.contains("-ui-test-open-editor") {
                LaunchIntent.openEditor(dayKey: DateUtil.dayKeyOf(Date()))
            }
            consumeLaunchIntent()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await ReminderService.rearm() }
            consumeLaunchIntent()
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
            editorDayKey = dayKey
            presentEditor = true
        }
    }
}
