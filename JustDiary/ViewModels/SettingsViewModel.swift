import Foundation
import Observation
import SwiftUI
import os

@Observable
final class SettingsViewModel {
    var settings = SettingsStore.load()
    var showDayStartPicker = false
    var showRemindPicker = false
    var themeMenuShowing = false
    var langMenuShowing = false
    var weekMenuShowing = false
    var busyText: String?
    var resultAlert: AppAlertItem?
    var exportChooserShowing = false
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

    func save() {
        SettingsStore.save(settings)
    }

    func setTheme(_ mode: String) {
        settings.themeMode = mode
        save()
        AppConfigService.applyAll()
    }

    func setLanguage(_ lang: String) {
        settings.appLanguage = lang
        save()
        settings = SettingsStore.load()
        DiaryRepository.shared.bumpUiTick()
        Task { await ReminderService.rearm() }
    }

    func setWeekStart(_ value: String) {
        settings.weekStart = value
        save()
        DiaryRepository.shared.bumpUiTick()
    }

    func setAutoTime(_ value: Bool) {
        settings.autoTime = value
        save()
    }

    func setAutoLoc(_ value: Bool) {
        settings.autoLoc = value
        save()
        if value {
            LocationService.shared.requestPermission()
            Task { await DiaryRepository.shared.backfillBlockRegions() }
        }
    }

    func setAllowHistoryEdit(_ value: Bool) {
        settings.allowHistoryEdit = value
        save()
    }

    func setRemindEnabled(_ value: Bool) {
        settings.remindEnabled = value
        save()
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
        save()
        let newHour = settings.dayStartHour
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
        save()
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
