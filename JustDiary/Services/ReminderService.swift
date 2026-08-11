import Foundation
import UserNotifications

enum ReminderService {
    static func notificationEnabled() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    static func requestEnable() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    static func ensureDailyReminder() async {
        let settings = SettingsStore.load()
        guard settings.remindEnabled else { return }
        let hasWrittenToday = await DiaryRepository.shared.getDiaryByDay(DateUtil.dayKeyOf(Date())) != nil
        let targetDate = nextTriggerDate(hour: settings.remindHour, minute: settings.remindMinute, skipIfTodayWritten: hasWrittenToday)
        guard let targetDate else { return }
        schedule(id: "daily_reminder", at: targetDate)
    }

    static func markTodayWritten() async {
        let settings = SettingsStore.load()
        guard settings.remindEnabled else { return }
        guard let targetDate = nextTriggerDate(hour: settings.remindHour, minute: settings.remindMinute, skipIfTodayWritten: true) else { return }
        schedule(id: "daily_reminder", at: targetDate)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["daily_reminder"])
    }

    static func rearm() async {
        let settings = SettingsStore.load()
        if !settings.remindEnabled {
            cancelAll()
            return
        }
        await ensureDailyReminder()
    }

    private static func nextTriggerDate(hour: Int, minute: Int, skipIfTodayWritten: Bool) -> Date? {
        let date = Date()
        var today = Calendar.current.dateComponents([.year, .month, .day], from: date)
        today.hour = hour
        today.minute = minute
        today.second = 0
        guard var target = Calendar.current.date(from: today) else { return nil }
        if skipIfTodayWritten || date >= target {
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: target) else { return nil }
            target = next
        }
        return target
    }

    private static func schedule(id: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = L10n.str("reminder_title")
        content.body = L10n.str("reminder_content")
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
