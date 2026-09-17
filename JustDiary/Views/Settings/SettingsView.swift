import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.adaptiveLayout) private var layout
    @State private var vm = SettingsViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if layout.cardColumns > 1 {
                    // 宽屏：两列卡片。用 LazyVGrid + `.top` 对齐 —— 各卡按内容自然高度，
                    // 不强行拉平（短卡里留白比拉齐更自然）。
                    cardGrid
                } else {
                    header
                    generalCard
                    rulesCard
                    reminderCard
                    dataCard
                    aboutCard
                }
                TabBarClearance()
            }
            // 四屏统一的页面边距（左侧让开系统占位）
            .adaptivePagePadding()
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
            // Kept as a dialog on purpose: this one confirms a destructive
            // action (the file's days replace the ones already stored) rather
            // than picking a value, which is what a confirmation dialog is for.
            Button(L10n.str("settings_import_skip")) { vm.runImport(mode: "skip") }
            Button(L10n.str("settings_import_overwrite")) { vm.runImport(mode: "overwrite") }
            Button(L10n.str("cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $vm.showDayStartPicker) {
            hourPickerSheet(title: L10n.str("settings_day_start"),
                            hour: Binding(get: { vm.settings.dayStartHour },
                                          set: { vm.settings.dayStartHour = $0 }),
                            isPresented: $vm.showDayStartPicker,
                            onApply: { vm.applyDayStart() })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $vm.showRemindPicker) {
            timePickerSheet(title: L10n.str("settings_remind_time"),
                            time: Binding(get: {
                                DateUtil.referenceTime(hour: vm.settings.remindHour,
                                                       minute: vm.settings.remindMinute)
                            }, set: { date in
                                vm.settings.remindHour = DateUtil.hour(of: date)
                                vm.settings.remindMinute = DateUtil.minute(of: date)
                            }),
                            isPresented: $vm.showRemindPicker,
                            onApply: { vm.applyRemindTime() })
                .presentationDetents([.medium])
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
                            .diaryFont(TypeSize.meta, weight: .medium)
                            .foregroundStyle(Theme.onSurface())
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 26)
                    .diaryCard(cornerRadius: Radius.card)
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

    /// 宽屏：标题单独一行，卡片按列数排布、保持自然高度。
    ///
    /// 标题放在 `LazyVGrid` **外面**：`gridCellColumns(_:)` 只对 `Grid` 生效，
    /// 在 `LazyVGrid` 里是空操作 —— 之前标题只占一列，第一张卡（通用）被挤到
    /// 标题右边同一行，两列布局看起来像错位。用 VStack 包一层才是真的整行标题。
    private var cardGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                                     count: layout.cardColumns),
                      alignment: .leading,
                      spacing: 12) {
                generalCard
                rulesCard
                reminderCard
                dataCard
                aboutCard
            }
        }
    }

    // MARK: - Cards

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .diaryCard(cornerRadius: Radius.card)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .diaryFont(TypeSize.sectionTitle, weight: .medium)
            .foregroundStyle(Theme.onSurfaceVariant())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 0)
    }

    private func valueRow(icon: String, title: String, sub: String?, value: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            rowLabel(icon: icon, title: title, sub: sub, value: value)
        }
        .buttonStyle(.plain)
    }

    /// A row whose trailing value opens a menu of options.
    ///
    /// This is what a value choice should be, rather than a
    /// `confirmationDialog`: a dialog is for confirming an action, while a menu
    /// is the compact, checkmark-bearing way to pick one of a few mutually
    /// exclusive values — and on iOS 26 it gets the Liquid Glass menu
    /// presentation. (`settings_import_mode_title` stays a dialog: it confirms a
    /// destructive action.)
    private func menuRow<Content: View>(icon: String, title: String, sub: String?, value: String,
                                        @ViewBuilder options: () -> Content) -> some View {
        Menu {
            options()
        } label: {
            rowLabel(icon: icon, title: title, sub: sub, value: value)
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityValue(value)
    }

    /// One entry of a `menuRow`, with the current value marked.
    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowLabel(icon: String, title: String, sub: String?, value: String) -> some View {
        HStack(spacing: 12) {
            GlassIconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .diaryFont(TypeSize.rowTitle)
                    .foregroundStyle(Theme.onSurface())
                if let sub {
                    Text(sub)
                        .diaryFont(TypeSize.rowSub)
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            // Without these the trailing value pushed the chevron off the
            // row once the user raised the system text size.
            Text(value)
                .diaryFont(TypeSize.rowValue)
                .foregroundStyle(Theme.onSurfaceVariant())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .diaryFont(TypeSize.rowValue)
                .foregroundStyle(Theme.onSurfaceVariant())
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func switchRow(icon: String, title: String, sub: String?, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            GlassIconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .diaryFont(TypeSize.rowTitle)
                    .foregroundStyle(Theme.onSurface())
                if let sub {
                    Text(sub)
                        .diaryFont(TypeSize.rowSub)
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
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
            menuRow(icon: "globe", title: L10n.str("settings_language"),
                    sub: L10n.str("settings_language_sub"),
                    value: langLabel) {
                option(L10n.str("settings_lang_system"),
                       selected: vm.settings.appLanguage == "system") { vm.setLanguage("system") }
                option(L10n.str("settings_lang_zh"),
                       selected: vm.settings.appLanguage == "zh") { vm.setLanguage("zh") }
                option(L10n.str("settings_lang_en"),
                       selected: vm.settings.appLanguage == "en") { vm.setLanguage("en") }
            }
            RowDivider(horizontalPadding: RowDivider.textInset)
            menuRow(icon: "paintpalette", title: L10n.str("settings_theme"),
                    sub: L10n.str("settings_theme_sub"),
                    value: themeLabel) {
                option(L10n.str("settings_theme_system"),
                       selected: vm.settings.themeMode == "system") { vm.setTheme("system") }
                option(L10n.str("settings_theme_light"),
                       selected: vm.settings.themeMode == "light") { vm.setTheme("light") }
                option(L10n.str("settings_theme_dark"),
                       selected: vm.settings.themeMode == "dark") { vm.setTheme("dark") }
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
            RowDivider(horizontalPadding: RowDivider.textInset)
            menuRow(icon: "calendar", title: L10n.str("settings_week_start"),
                    sub: L10n.str("settings_week_start_sub"),
                    value: vm.settings.weekStart == "sunday" ? L10n.str("settings_week_sunday") : L10n.str("settings_week_monday")) {
                option(L10n.str("settings_week_monday"),
                       selected: vm.settings.weekStart != "sunday") { vm.setWeekStart("monday") }
                option(L10n.str("settings_week_sunday"),
                       selected: vm.settings.weekStart == "sunday") { vm.setWeekStart("sunday") }
            }
            RowDivider(horizontalPadding: RowDivider.textInset)
            switchRow(icon: "clock", title: L10n.str("settings_auto_time"),
                      sub: L10n.str("settings_auto_time_sub"),
                      isOn: Binding(get: { vm.settings.autoTime },
                                    set: { vm.setAutoTime($0) })) { _ in }
            RowDivider(horizontalPadding: RowDivider.textInset)
            switchRow(icon: "location", title: L10n.str("settings_auto_loc"),
                      sub: L10n.str("settings_auto_loc_sub"),
                      isOn: Binding(get: { vm.settings.autoLoc },
                                    set: { vm.setAutoLoc($0) })) { _ in }
            if vm.settings.autoLoc {
                RowDivider(horizontalPadding: RowDivider.textInset)
                valueRow(icon: "location.circle", title: L10n.str("settings_loc_permission"),
                         sub: L10n.str("settings_loc_permission_sub"),
                         value: vm.locStatusText) {
                    vm.handleLocPermission()
                }
            }
            RowDivider(horizontalPadding: RowDivider.textInset)
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
                RowDivider(horizontalPadding: RowDivider.textInset)
                valueRow(icon: "clock.badge", title: L10n.str("settings_remind_time"),
                         sub: L10n.str("settings_remind_time_sub"),
                         value: L10n.timeLabel(hour: vm.settings.remindHour, minute: vm.settings.remindMinute)) {
                    vm.showRemindPicker = true
                }
            }
            if vm.settings.remindEnabled && vm.notifStatusText == L10n.str("settings_notif_off") {
                RowDivider(horizontalPadding: RowDivider.textInset)
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
            menuRow(icon: "square.and.arrow.up", title: L10n.str("settings_export"),
                    sub: L10n.str("settings_export_sub"), value: "") {
                option(L10n.str("settings_export_data_only"), selected: false) {
                    vm.runExport(includeSettings: false)
                }
                option(L10n.str("settings_export_data_settings"), selected: false) {
                    vm.runExport(includeSettings: true)
                }
            }
            RowDivider(horizontalPadding: RowDivider.textInset)
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

    // MARK: - Picker sheets

    /// Hour-only wheel, for the day-start rule.
    ///
    /// The old sheet also showed a minute wheel whose binding could not change
    /// anything (the rule has no minute), and labelled the hours `0…23` — which
    /// reads wrong in a 12-hour locale. The labels are now the app's own time
    /// strings, so they follow the device's 24-hour setting and the app language
    /// like every other time in the UI.
    private func hourPickerSheet(title: String, hour: Binding<Int>,
                                 isPresented: Binding<Bool>, onApply: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            GlassSheetHeader(title: title) {
                isPresented.wrappedValue = false
            }
            Picker("", selection: hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(L10n.timeLabel(hour: h, minute: 0)).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            GlassPrimaryButton(title: L10n.str("save"), fullWidth: true) {
                onApply()
                isPresented.wrappedValue = false
            }
        }
        .padding(20)
    }

    /// Time wheel for the reminder.
    ///
    /// A `DatePicker` rather than two hand-built wheels: it formats the hour,
    /// minute and AM/PM symbol for the current language and honours the device's
    /// 12/24-hour setting, which the hand-built version did not.
    private func timePickerSheet(title: String, time: Binding<Date>,
                                 isPresented: Binding<Bool>, onApply: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            GlassSheetHeader(title: title) {
                isPresented.wrappedValue = false
            }
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, AppLanguage.locale)
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
