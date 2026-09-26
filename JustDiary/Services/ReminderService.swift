import Foundation
import UserNotifications
import os

enum ReminderService {
    static func notificationEnabled() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// 可以排队通知吗？`notDetermined` 时顺手申请一次 —— 用户既然开着提醒开关，
    /// 这一步就该由这里补上，不然「开关是开的、提醒却永远不会来」。
    private static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
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
        // 没拿到通知权限就别去排队：`UNUserNotificationCenter.add` 会返回
        // `UNErrorDomain Code=2003 "Source is not authorized"`，控制台里每条都是一次
        // 红色 error（用户拒绝过通知就会一直刷）。权限状态是用户的选择，不是错误。
        guard await ensureAuthorized() else {
            Log.app.debug("daily reminder skipped: notifications not authorized")
            return
        }
        let hasWrittenToday = await DiaryRepository.shared.getDiaryByDay(DateUtil.dayKeyOf(Date())) != nil
        let targetDate = nextTriggerDate(hour: settings.remindHour, minute: settings.remindMinute, skipIfTodayWritten: hasWrittenToday)
        guard let targetDate else { return }
        schedule(id: "daily_reminder", at: targetDate)
    }

    static func markTodayWritten() async {
        let settings = SettingsStore.load()
        guard settings.remindEnabled else { return }
        guard await ensureAuthorized() else {
            Log.app.debug("daily reminder skipped: notifications not authorized")
            return
        }
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                // 权限是被撤销（用户中途关掉通知）时也没必要刷 error：那是用户的选择。
                // 其余失败才算异常。
                if (error as NSError).code == 2003 {
                    Log.app.debug("schedule reminder skipped: not authorized")
                } else {
                    Log.app.error("schedule reminder failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
}
