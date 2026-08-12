import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsStore.load()
    @State private var showDayStartPicker = false
    @State private var showRemindPicker = false
    @State private var themeMenuShowing = false
    @State private var langMenuShowing = false
    @State private var weekMenuShowing = false
    @State private var busyText: String?
    @State private var resultAlert: ResultAlert?
    @State private var exportChooserShowing = false
    @State private var importModeShowing = false
    @State private var showImportPicker = false
    @State private var importURL: URL?
    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var locStatusText = ""
    @State private var notifStatusText = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                generalCard
                rulesCard
                reminderCard
                dataCard
                aboutCard
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            settings = SettingsStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatus() }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareLink(item: url, preview: SharePreview(L10n.str("EntryAbility_label")))
                    .buttonStyle(.glassProminent)
                    .padding(24)
                    .presentationDetents([.height(170)])
            }
        }
        .fileImporter(isPresented: $showImportPicker,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importURL = url
                importModeShowing = true
            }
        }
        .confirmationDialog(L10n.str("settings_import_mode_title"),
                            isPresented: $importModeShowing,
                            titleVisibility: .visible) {
            Button(L10n.str("settings_import_skip")) { runImport(mode: "skip") }
            Button(L10n.str("settings_import_overwrite")) { runImport(mode: "overwrite") }
            Button(L10n.str("cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showDayStartPicker) {
            hourPickerSheet(title: L10n.str("settings_day_start"),
                            hour: Binding(get: { settings.dayStartHour },
                                          set: { settings.dayStartHour = $0 }),
                            minute: Binding(get: { 0 }, set: { _ in }),
                            isPresented: $showDayStartPicker,
                            onApply: { applyDayStart() })
                .presentationDetents([.height(320)])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showRemindPicker) {
            hourPickerSheet(title: L10n.str("settings_remind_time"),
                            hour: Binding(get: { settings.remindHour },
                                          set: { settings.remindHour = $0 }),
                            minute: Binding(get: { settings.remindMinute },
                                            set: { settings.remindMinute = $0 }),
                            isPresented: $showRemindPicker,
                            onApply: { applyRemindTime() })
                .presentationDetents([.height(320)])
                .presentationBackground(.ultraThinMaterial)
        }
        .overlay {
            if let busyText {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Theme.primary())
                        Text(busyText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.onSurface())
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 26)
                    .diaryGlassCard(cornerRadius: 18)
                }
                .transition(.opacity)
            }
        }
        .alert(item: $resultAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    struct ResultAlert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(L10n.str("settings_title"))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.onSurface())
            Spacer()
        }
        .frame(height: 52)
    }

    // MARK: - Status

    private func refreshStatus() async {
        switch LocStatus.current() {
        case .authorizedAlways, .authorizedWhenInUse:
            locStatusText = LocStatus.isPrecise ? L10n.str("settings_loc_exact") : L10n.str("settings_loc_fuzzy")
        default:
            locStatusText = L10n.str("settings_loc_none")
        }
        let enabled = await ReminderService.notificationEnabled()
        notifStatusText = enabled ? L10n.str("settings_notif_on") : L10n.str("settings_notif_off")
    }

    // MARK: - Cards

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .diaryGlassCard(cornerRadius: 22)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.onSurfaceVariant())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private func valueRow(icon: String, title: String, sub: String?, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .glassEffect(tintedGlass(nil),
                                     in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.onSurface())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.onSurface())
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.onSurfaceVariant())
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.onSurfaceVariant())
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.onSurfaceVariant())
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
    }

    private func switchRow(icon: String, title: String, sub: String?, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.glassDim())
                    .glassEffect(tintedGlass(nil),
                                 in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: 38, height: 38)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.glassBorder(), lineWidth: 1)
                    }
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.onSurface())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onSurface())
                if let sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .lineLimit(2)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.primary())
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
    }

    // MARK: - General

    private var generalCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_general"))
            valueRow(icon: "globe", title: L10n.str("settings_language"),
                     sub: L10n.str("settings_language_sub"),
                     value: langLabel) {
                langMenuShowing = true
            }
            .confirmationDialog(L10n.str("settings_language"), isPresented: $langMenuShowing) {
                Button(L10n.str("settings_lang_system")) { setLanguage("system") }
                Button(L10n.str("settings_lang_zh")) { setLanguage("zh") }
                Button(L10n.str("settings_lang_en")) { setLanguage("en") }
            }
            Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
            valueRow(icon: "paintpalette", title: L10n.str("settings_theme"),
                     sub: L10n.str("settings_theme_sub"),
                     value: themeLabel) {
                themeMenuShowing = true
            }
            .confirmationDialog(L10n.str("settings_theme"), isPresented: $themeMenuShowing) {
                Button(L10n.str("settings_theme_system")) { setTheme("system") }
                Button(L10n.str("settings_theme_light")) { setTheme("light") }
                Button(L10n.str("settings_theme_dark")) { setTheme("dark") }
            }
        }
    }

    private var themeLabel: String {
        switch settings.themeMode {
        case "light": return L10n.str("settings_theme_light")
        case "dark": return L10n.str("settings_theme_dark")
        default: return L10n.str("settings_theme_system")
        }
    }

    private var langLabel: String {
        switch settings.appLanguage {
        case "zh": return "中文"
        case "en": return "English"
        default: return L10n.str("settings_lang_system")
        }
    }

    private func setTheme(_ mode: String) {
        settings.themeMode = mode
        SettingsStore.save(settings)
        AppConfigService.applyAll()
    }

    private func setLanguage(_ lang: String) {
        settings.appLanguage = lang
        SettingsStore.save(settings)
        resultAlert = ResultAlert(title: L10n.str("settings_language"),
                                  message: L10n.str("settings_lang_restart_msg"))
    }

    // MARK: - Rules

    private var rulesCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_rules"))
            valueRow(icon: "sun.horizon", title: L10n.str("settings_day_start"),
                     sub: L10n.str("settings_day_start_sub"),
                     value: L10n.dayStartLabel(settings.dayStartHour)) {
                showDayStartPicker = true
            }
            Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
            valueRow(icon: "calendar", title: L10n.str("settings_week_start"),
                     sub: L10n.str("settings_week_start_sub"),
                     value: settings.weekStart == "sunday" ? L10n.str("settings_week_sunday") : L10n.str("settings_week_monday")) {
                weekMenuShowing = true
            }
            .confirmationDialog(L10n.str("settings_week_start"), isPresented: $weekMenuShowing) {
                Button(L10n.str("settings_week_monday")) { setWeekStart("monday") }
                Button(L10n.str("settings_week_sunday")) { setWeekStart("sunday") }
            }
            Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
            switchRow(icon: "clock", title: L10n.str("settings_auto_time"),
                      sub: L10n.str("settings_auto_time_sub"),
                      isOn: Binding(get: { settings.autoTime },
                                    set: { settings.autoTime = $0; SettingsStore.save(settings) })) { _ in }
            Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
            switchRow(icon: "location", title: L10n.str("settings_auto_loc"),
                      sub: L10n.str("settings_auto_loc_sub"),
                      isOn: Binding(get: { settings.autoLoc },
                                    set: { settings.autoLoc = $0; SettingsStore.save(settings) })) { enabled in
                if enabled {
                    LocationService.shared.requestPermission()
                    Task { await DiaryRepository.shared.backfillBlockRegions() }
                }
            }
            if settings.autoLoc {
                Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
                valueRow(icon: "location.circle", title: L10n.str("settings_loc_permission"),
                         sub: L10n.str("settings_loc_permission_sub"),
                         value: locStatusText) {
                    handleLocPermission()
                }
            }
            Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
            switchRow(icon: "pencil", title: L10n.str("settings_history_edit"),
                      sub: L10n.str("settings_history_edit_sub"),
                      isOn: Binding(get: { settings.allowHistoryEdit },
                                    set: { settings.allowHistoryEdit = $0; SettingsStore.save(settings) })) { _ in }
        }
    }

    private func setWeekStart(_ value: String) {
        settings.weekStart = value
        SettingsStore.save(settings)
        DiaryRepository.shared.bumpUiTick()
    }

    private func handleLocPermission() {
        switch LocStatus.current() {
        case .notDetermined:
            LocationService.shared.requestPermission()
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshStatus()
        }
    }

    private func applyDayStart() {
        SettingsStore.save(settings)
        let newHour = settings.dayStartHour
        Task {
            let conflicts = await DiaryRepository.shared.recomputeDayKeys(dayStartHour: newHour)
            DiaryRepository.shared.bumpDiaryVersion()
            if conflicts > 0 {
                resultAlert = ResultAlert(title: L10n.str("settings_day_recalc_title"),
                                          message: L10n.fmt("settings_day_recalc_msg", conflicts))
            }
        }
    }

    private func applyRemindTime() {
        SettingsStore.save(settings)
        Task { await ReminderService.rearm() }
    }

    // MARK: - Reminder

    private var reminderCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_remind"))
            switchRow(icon: "bell", title: L10n.str("settings_remind_enabled"),
                      sub: L10n.str("settings_remind_enabled_sub"),
                      isOn: Binding(get: { settings.remindEnabled },
                                    set: { settings.remindEnabled = $0; SettingsStore.save(settings) })) { enabled in
                if enabled {
                    Task {
                        let granted = await ReminderService.requestEnable()
                        if granted {
                            await ReminderService.ensureDailyReminder()
                        }
                        await refreshStatus()
                    }
                } else {
                    ReminderService.cancelAll()
                }
            }
            if settings.remindEnabled {
                Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
                valueRow(icon: "clock.badge", title: L10n.str("settings_remind_time"),
                         sub: L10n.str("settings_remind_time_sub"),
                         value: DateUtil.hourMinuteLabel(settings.remindHour, minute: settings.remindMinute)) {
                    showRemindPicker = true
                }
            }
            if settings.remindEnabled && notifStatusText == L10n.str("settings_notif_off") {
                Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
                valueRow(icon: "bell.badge", title: L10n.str("settings_notif_permission"),
                         sub: L10n.str("settings_notif_permission_sub"),
                         value: notifStatusText) {
                    Task {
                        _ = await ReminderService.requestEnable()
                        await refreshStatus()
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_data"))
            valueRow(icon: "square.and.arrow.up", title: L10n.str("settings_export"),
                     sub: L10n.str("settings_export_sub"), value: "") {
                exportChooserShowing = true
            }
            .confirmationDialog(L10n.str("settings_export_choice_title"), isPresented: $exportChooserShowing) {
                Button(L10n.str("settings_export_data_only")) { runExport(includeSettings: false) }
                Button(L10n.str("settings_export_data_settings")) { runExport(includeSettings: true) }
            }
            Divider().overlay(Theme.outlineVariant().opacity(0.5)).padding(.horizontal, 12)
            valueRow(icon: "square.and.arrow.down", title: L10n.str("settings_import"),
                     sub: L10n.str("settings_import_sub"), value: "") {
                showImportPicker = true
            }
        }
    }

    private func runExport(includeSettings: Bool) {
        busyText = L10n.str("settings_export_busy")
        Task {
            do {
                let url = try await BackupService.exportBackup(includeSettings: includeSettings)
                await MainActor.run {
                    busyText = nil
                    exportURL = url
                    showExportSheet = true
                }
            } catch {
                await MainActor.run {
                    busyText = nil
                    resultAlert = ResultAlert(title: L10n.str("settings_export_failed_title"),
                                              message: L10n.str("settings_export_failed_msg"))
                }
            }
        }
    }

    private func runImport(mode: String) {
        guard let url = importURL else { return }
        busyText = L10n.str("settings_import_busy")
        Task {
            do {
                let stats = try await BackupService.importBackup(fileURL: url, mode: mode)
                await MainActor.run {
                    busyText = nil
                    settings = SettingsStore.load()
                    DiaryRepository.shared.bumpDiaryVersion()
                    DiaryRepository.shared.bumpUiTick()
                    var message = L10n.fmt("settings_import_success_msg",
                                           stats.importedDays, stats.skippedDays, stats.overwrittenDays,
                                           stats.importedBlocks, stats.importedImages)
                    if stats.settingsRestored {
                        message += "\n" + L10n.str("settings_settings_restored")
                    }
                    resultAlert = ResultAlert(title: L10n.str("settings_import_success_title"),
                                              message: message)
                }
            } catch {
                await MainActor.run {
                    busyText = nil
                    resultAlert = ResultAlert(title: L10n.str("settings_import_failed_title"),
                                              message: L10n.str("settings_import_failed_msg"))
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_about"))
            valueRow(icon: "info.circle", title: L10n.str("settings_version"),
                     sub: nil, value: SettingsStore.appVersion) {}
        }
    }

    // MARK: - Picker sheet

    private func hourPickerSheet(title: String, hour: Binding<Int>, minute: Binding<Int>,
                                 isPresented: Binding<Bool>, onApply: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
                Spacer()
            }
            HStack(spacing: 8) {
                Picker("", selection: hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text("\(h)").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 90)
                Text(":")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
                Picker("", selection: minute) {
                    ForEach(0..<60, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 90)
            }
            Button {
                onApply()
                isPresented.wrappedValue = false
            } label: {
                Text(L10n.str("save"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule().fill(Theme.primary())
                            .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                            .shadow(color: Theme.glowColor(), radius: 10, y: 3)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
}
