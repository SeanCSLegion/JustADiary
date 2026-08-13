import SwiftUI

struct SettingsView: View {
    @State private var vm = SettingsViewModel()

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
        .task { await vm.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            vm.refreshSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await vm.refreshStatus() }
        }
        .sheet(isPresented: $vm.showExportSheet) {
            if let url = vm.exportURL {
                ShareLink(item: url, preview: SharePreview(L10n.str("EntryAbility_label")))
                    .buttonStyle(.glassProminent)
                    .padding(24)
                    .presentationDetents([.height(170)])
            }
        }
        .sheet(isPresented: $vm.showImportPicker) {
            DocumentPicker { url in
                vm.showImportPicker = false
                guard let url else { return }
                vm.importURL = url
                vm.importModeShowing = true
            }
        }
        .confirmationDialog(L10n.str("settings_import_mode_title"),
                            isPresented: $vm.importModeShowing,
                            titleVisibility: .visible) {
            Button(L10n.str("settings_import_skip")) { vm.runImport(mode: "skip") }
            Button(L10n.str("settings_import_overwrite")) { vm.runImport(mode: "overwrite") }
            Button(L10n.str("cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $vm.showDayStartPicker) {
            hourPickerSheet(title: L10n.str("settings_day_start"),
                            hour: Binding(get: { vm.settings.dayStartHour },
                                          set: { vm.settings.dayStartHour = $0 }),
                            minute: Binding(get: { 0 }, set: { _ in }),
                            isPresented: $vm.showDayStartPicker,
                            onApply: { vm.applyDayStart() })
                .presentationDetents([.height(320)])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $vm.showRemindPicker) {
            hourPickerSheet(title: L10n.str("settings_remind_time"),
                            hour: Binding(get: { vm.settings.remindHour },
                                          set: { vm.settings.remindHour = $0 }),
                            minute: Binding(get: { vm.settings.remindMinute },
                                            set: { vm.settings.remindMinute = $0 }),
                            isPresented: $vm.showRemindPicker,
                            onApply: { vm.applyRemindTime() })
                .presentationDetents([.height(320)])
                .presentationBackground(.ultraThinMaterial)
        }
        .overlay {
            if let busyText = vm.busyText {
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
        .appAlert(item: $vm.resultAlert)
    }

    // MARK: - Header

    private var header: some View {
        PageHeader(title: L10n.str("settings_title"))
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
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                GlassIconBadge(systemName: icon)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func switchRow(icon: String, title: String, sub: String?, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            GlassIconBadge(systemName: icon)
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
                .accessibilityLabel(title)
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    Haptics.tap()
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
                vm.langMenuShowing = true
            }
            .confirmationDialog(L10n.str("settings_language"), isPresented: $vm.langMenuShowing) {
                Button(L10n.str("settings_lang_system")) { vm.setLanguage("system") }
                Button(L10n.str("settings_lang_zh")) { vm.setLanguage("zh") }
                Button(L10n.str("settings_lang_en")) { vm.setLanguage("en") }
            }
            RowDivider(horizontalPadding: 12)
            valueRow(icon: "paintpalette", title: L10n.str("settings_theme"),
                     sub: L10n.str("settings_theme_sub"),
                     value: themeLabel) {
                vm.themeMenuShowing = true
            }
            .confirmationDialog(L10n.str("settings_theme"), isPresented: $vm.themeMenuShowing) {
                Button(L10n.str("settings_theme_system")) { vm.setTheme("system") }
                Button(L10n.str("settings_theme_light")) { vm.setTheme("light") }
                Button(L10n.str("settings_theme_dark")) { vm.setTheme("dark") }
            }
        }
    }

    private var themeLabel: String {
        switch vm.settings.themeMode {
        case "light": return L10n.str("settings_theme_light")
        case "dark": return L10n.str("settings_theme_dark")
        default: return L10n.str("settings_theme_system")
        }
    }

    private var langLabel: String {
        switch vm.settings.appLanguage {
        case "zh": return "中文"
        case "en": return "English"
        default: return L10n.str("settings_lang_system")
        }
    }

    // MARK: - Rules

    private var rulesCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_rules"))
            valueRow(icon: "sun.horizon", title: L10n.str("settings_day_start"),
                     sub: L10n.str("settings_day_start_sub"),
                     value: L10n.dayStartLabel(vm.settings.dayStartHour)) {
                vm.showDayStartPicker = true
            }
            RowDivider(horizontalPadding: 12)
            valueRow(icon: "calendar", title: L10n.str("settings_week_start"),
                     sub: L10n.str("settings_week_start_sub"),
                     value: vm.settings.weekStart == "sunday" ? L10n.str("settings_week_sunday") : L10n.str("settings_week_monday")) {
                vm.weekMenuShowing = true
            }
            .confirmationDialog(L10n.str("settings_week_start"), isPresented: $vm.weekMenuShowing) {
                Button(L10n.str("settings_week_monday")) { vm.setWeekStart("monday") }
                Button(L10n.str("settings_week_sunday")) { vm.setWeekStart("sunday") }
            }
            RowDivider(horizontalPadding: 12)
            switchRow(icon: "clock", title: L10n.str("settings_auto_time"),
                      sub: L10n.str("settings_auto_time_sub"),
                      isOn: Binding(get: { vm.settings.autoTime },
                                    set: { vm.setAutoTime($0) })) { _ in }
            RowDivider(horizontalPadding: 12)
            switchRow(icon: "location", title: L10n.str("settings_auto_loc"),
                      sub: L10n.str("settings_auto_loc_sub"),
                      isOn: Binding(get: { vm.settings.autoLoc },
                                    set: { vm.setAutoLoc($0) })) { _ in }
            if vm.settings.autoLoc {
                RowDivider(horizontalPadding: 12)
                valueRow(icon: "location.circle", title: L10n.str("settings_loc_permission"),
                         sub: L10n.str("settings_loc_permission_sub"),
                         value: vm.locStatusText) {
                    vm.handleLocPermission()
                }
            }
            RowDivider(horizontalPadding: 12)
            switchRow(icon: "pencil", title: L10n.str("settings_history_edit"),
                      sub: L10n.str("settings_history_edit_sub"),
                      isOn: Binding(get: { vm.settings.allowHistoryEdit },
                                    set: { vm.setAllowHistoryEdit($0) })) { _ in }
        }
    }

    // MARK: - Reminder

    private var reminderCard: some View {
        card {
            sectionTitle(L10n.str("settings_section_remind"))
            switchRow(icon: "bell", title: L10n.str("settings_remind_enabled"),
                      sub: L10n.str("settings_remind_enabled_sub"),
                      isOn: Binding(get: { vm.settings.remindEnabled },
                                    set: { vm.setRemindEnabled($0) })) { _ in }
            if vm.settings.remindEnabled {
                RowDivider(horizontalPadding: 12)
                valueRow(icon: "clock.badge", title: L10n.str("settings_remind_time"),
                         sub: L10n.str("settings_remind_time_sub"),
                         value: DateUtil.hourMinuteLabel(vm.settings.remindHour, minute: vm.settings.remindMinute)) {
                    vm.showRemindPicker = true
                }
            }
            if vm.settings.remindEnabled && vm.notifStatusText == L10n.str("settings_notif_off") {
                RowDivider(horizontalPadding: 12)
                valueRow(icon: "bell.badge", title: L10n.str("settings_notif_permission"),
                         sub: L10n.str("settings_notif_permission_sub"),
                         value: vm.notifStatusText) {
                    vm.requestNotificationPermission()
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
                vm.exportChooserShowing = true
            }
            .confirmationDialog(L10n.str("settings_export_choice_title"), isPresented: $vm.exportChooserShowing) {
                Button(L10n.str("settings_export_data_only")) { vm.runExport(includeSettings: false) }
                Button(L10n.str("settings_export_data_settings")) { vm.runExport(includeSettings: true) }
            }
            RowDivider(horizontalPadding: 12)
            valueRow(icon: "square.and.arrow.down", title: L10n.str("settings_import"),
                     sub: L10n.str("settings_import_sub"), value: "") {
                vm.showImportPicker = true
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
            GlassSheetHeader(title: title) {
                isPresented.wrappedValue = false
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
            GlassPrimaryButton(title: L10n.str("save"), fullWidth: true) {
                onApply()
                isPresented.wrappedValue = false
            }
        }
        .padding(20)
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPick(nil)
        }
    }
}
