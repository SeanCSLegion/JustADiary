import Foundation

nonisolated enum DateUtil {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale.current
        cal.timeZone = .current
        return cal
    }()

    static func dayKeyOf(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    static func dayKeyForUtc(_ utc: Int64, dayStartHour: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(utc) / 1000.0)
        let hour = calendar.component(.hour, from: date)
        if hour < dayStartHour {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { return dayKeyOf(date) }
            return dayKeyOf(prev)
        }
        return dayKeyOf(date)
    }

    static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func addMonths(_ date: Date, _ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func monthFirst(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    static func weekFirst(_ date: Date) -> Date {
        let lead = weekdayIndex(date, weekStart: SettingsStore.load().weekStart)
        return calendar.date(byAdding: .day, value: -lead, to: startOfDay(date)) ?? date
    }

    static func daysInMonth(_ date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func weekdayIndex(_ date: Date, weekStart: String) -> Int {
        let wd = calendar.component(.weekday, from: date)
        if weekStart == "sunday" {
            return wd - 1
        }
        return (wd + 5) % 7
    }

    static func hourMinuteLabel(_ hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    static func relativeDays(from date: Date, to today: Date) -> Int {
        let a = calendar.startOfDay(for: date)
        let b = calendar.startOfDay(for: today)
        let diff = calendar.dateComponents([.day], from: b, to: a).day ?? 0
        return diff
    }
}
