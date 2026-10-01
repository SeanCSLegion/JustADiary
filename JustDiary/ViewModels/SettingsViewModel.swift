import Foundation
import Observation
import SwiftUI
import os

@Observable
final class SettingsViewModel {
    var settings = SettingsStore.load()
    var showDayStartPicker = false
    var showRemindPicker = false
    var busyText: String?
    var resultAlert: AppAlertItem?
    var importModeShowing = false
    var showImportPicker = false
    var importURL: URL?
    var exportURL: URL?
    var showExportSheet = false
    var locStatusText = ""
    var notifStatusText = ""

    func refreshSettings() {
        settings = SettingsStore.load()
    }

    func refreshStatus() async {
        switch LocStatus.current() {
        case .authorizedAlways, .authorizedWhenInUse:
            locStatusText = LocStatus.isPrecise ? L10n.str("settings_loc_exact") : L10n.str("settings_loc_fuzzy")
        default:
            locStatusText = L10n.str("settings_loc_none")
        }
        let enabled = await ReminderService.notificationEnabled()
        notifStatusText = enabled ? L10n.str("settings_notif_on") : L10n.str("settings_notif_off")
    }

    /// 只改需要的字段并落盘。
    ///
    /// 以前是「整份 `settings` 写回去」，而这一页的 `settings` 只是进入本页时的一份
    /// 快照（TabView 会一直留着这一页）：在别处改过的设置项会被这份过期副本悄悄写回
    /// 旧值。现在以 `SettingsStore` 里的当前值打底，只动要动的那一项。
    private func update(_ mutate: (inout AppSettings) -> Void) {
        var s = SettingsStore.load()
        mutate(&s)
        SettingsStore.save(s)
        settings = s
    }

    func setTheme(_ mode: String) {
        update { $0.themeMode = mode }
        AppConfigService.applyAll()
    }

    func setLanguage(_ lang: String) {
        update { $0.appLanguage = lang }
        DiaryRepository.shared.bumpUiTick()
        Task { await ReminderService.rearm() }
    }

    func setWeekStart(_ value: String) {
        update { $0.weekStart = value }
        DiaryRepository.shared.bumpUiTick()
    }

    func setAutoTime(_ value: Bool) {
        update { $0.autoTime = value }
        // `auto_time` 现在决定开始时间是否显示（编辑器 / 阅读页 / 首页 / 分享长图），
        // 必须和其他显示类设置一样广播 UI tick，否则常驻的首页会保持旧值。
        // 注意：这里只刷新显示，`start_time_utc` 的记录与存储完全不受影响。
        DiaryRepository.shared.bumpUiTick()
    }

    func setAutoLoc(_ value: Bool) {
        update { $0.autoLoc = value }
        if value {
            LocationService.shared.requestPermission()
            Task { await DiaryRepository.shared.backfillBlockRegions() }
        }
    }

    /// 分享长图里的地点精度上限（隐藏 / 区县 / 城市 / 省份）。
    ///
    /// 取值由 `AppSettings.normalize()` 收在「可分享」的那几级里。这里**不广播**
    /// 任何刷新：分享时按当时的值渲染（`DiaryViewModel.shareDiary()` 直接读设置），
    /// 页面没有一处常驻显示它，不必为它惊动别的界面。
    func setShareLocPrecision(_ value: String) {
        update { $0.shareLocPrecision = value }
    }

    var shareLocPrecisionLabel: String {
        L10n.sharePrecisionLabel(settings.shareLocPrecision)
    }

    func setAllowHistoryEdit(_ value: Bool) {
        update { $0.allowHistoryEdit = value }
    }

    func setRemindEnabled(_ value: Bool) {
        update { $0.remindEnabled = value }
        if value {
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

    func handleLocPermission() {
        switch LocStatus.current() {
        case .notDetermined:
            LocationService.shared.requestPermission()
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await refreshStatus()
        }
    }

    func applyDayStart() {
        // 选择器直接绑在 `settings.dayStartHour` 上，所以取本页刚选好的值，
        // 但只把这一项写回库里（见 `update`）。
        let newHour = settings.dayStartHour
        update { $0.dayStartHour = newHour }
        Task {
            let conflicts = await DiaryRepository.shared.recomputeDayKeys(dayStartHour: newHour)
            DiaryRepository.shared.bumpDiaryVersion()
            if conflicts > 0 {
                resultAlert = AppAlertItem(title: L10n.str("settings_day_recalc_title"),
                                           message: L10n.fmt("settings_day_recalc_msg", conflicts))
            }
        }
    }

    func applyRemindTime() {
        let hour = settings.remindHour
        let minute = settings.remindMinute
        update {
            $0.remindHour = hour
            $0.remindMinute = minute
        }
        Task { await ReminderService.rearm() }
    }

    func requestNotificationPermission() {
        Task {
            _ = await ReminderService.requestEnable()
            await refreshStatus()
        }
    }

    func runExport(includeSettings: Bool) {
        busyText = L10n.str("settings_export_busy")
        Task {
            do {
                let url = try await BackupService.exportBackup(includeSettings: includeSettings)
                busyText = nil
                exportURL = url
                showExportSheet = true
            } catch {
                Log.backup.error("export failed: \(String(describing: error), privacy: .public)")
                busyText = nil
                resultAlert = AppAlertItem(title: L10n.str("settings_export_failed_title"),
                                           message: L10n.str("settings_export_failed_msg"))
            }
        }
    }

    func runImport(mode: String) {
        guard let url = importURL else { return }
        busyText = L10n.str("settings_import_busy")
        Task {
            do {
                let stats = try await BackupService.importBackup(fileURL: url, mode: mode)
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
                resultAlert = AppAlertItem(title: L10n.str("settings_import_success_title"),
                                           message: message)
            } catch {
                Log.backup.error("import failed: \(String(describing: error), privacy: .public)")
                busyText = nil
                resultAlert = AppAlertItem(title: L10n.str("settings_import_failed_title"),
                                           message: L10n.str("settings_import_failed_msg"))
            }
        }
    }
}
