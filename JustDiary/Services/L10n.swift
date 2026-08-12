import Foundation

enum AppLanguage {
    static var current: String {
        let mode = SettingsStore.load().appLanguage
        if mode == "zh" { return "zh-Hans" }
        if mode == "en" { return "en" }
        return Locale.preferredLanguages.first ?? "zh-Hans"
    }

    static var locale: Locale {
        Locale(identifier: current)
    }

    static var isZh: Bool {
        current.lowercased().hasPrefix("zh")
    }
}

enum L10n {
    static func str(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func fmt(_ key: String, _ args: Any...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        let nsArgs: [CVarArg] = args.map { arg in
            if let s = arg as? String { return s as NSString }
            if let s = arg as? NSString { return s }
            if let i = arg as? Int { return i }
            if let i64 = arg as? Int64 { return i64 }
            if let d = arg as? Double { return d }
            if let f = arg as? Float { return f }
            if let b = arg as? Bool { return b ? 1 : 0 }
            return String(describing: arg) as NSString
        }
        return String(format: format, arguments: nsArgs)
    }

    static func weekdayShort(_ weekdayIndex: Int) -> String {
        let weekdays = ["week_sunday", "week_monday", "week_tuesday", "week_wednesday",
                        "week_thursday", "week_friday", "week_saturday"]
        return str(weekdays[(weekdayIndex + 6) % 7])
    }

    static func weekdayNames(weekStart: String) -> [String] {
        var names: [String] = []
        let base = weekStart == "sunday" ? 0 : 1
        for i in 0..<7 {
            names.append(weekdayShort(base + i))
        }
        return names
    }

    static func monthName(_ month: Int) -> String {
        let months = ["month_jan", "month_feb", "month_mar", "month_apr", "month_may", "month_jun",
                      "month_jul", "month_aug", "month_sep", "month_oct", "month_nov", "month_dec"]
        return str(months[month - 1])
    }

    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let wd = cal.component(.weekday, from: date)
        return fmt("date_day_title", monthName(month), day, weekdayShort(wd))
    }

    static func dateOnly(_ date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return fmt("date_day_only", monthName(month), day)
    }

    static func monthFull(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "MMMM"
        return f.string(from: date)
    }

    static func weekHeaderTitle(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let wd = cal.component(.weekday, from: date)
        return fmt("index_week_head", y, monthName(m), d, weekdayShort(wd))
    }

    static func formatDayKey(_ dayKey: String) -> String {
        guard let date = DateUtil.parseDayKey(dayKey) else { return dayKey }
        return dayTitle(date)
    }

    static func timeOf(_ utcMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(utcMs) / 1000)
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func startLine(_ timeMs: Int64, locText: String) -> String {
        let time = timeOf(timeMs)
        if locText.isEmpty {
            return fmt("read_start_time", time)
        }
        return fmt("read_start_time_loc", time, locText)
    }

    static func dayStartLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return fmt("time_label_midnight")
        case 1..<6: return fmt("time_label_dawn", hour)
        case 6..<12: return fmt("time_label_morning", hour)
        case 12: return fmt("time_label_noon")
        case 13..<18: return fmt("time_label_afternoon", hour)
        default: return fmt("time_label_evening", hour)
        }
    }

    static func precisionLabel(_ precision: String) -> String {
        switch precision {
        case LocPrecision.exact: return str("loc_precision_exact")
        case LocPrecision.street: return str("loc_precision_street")
        case LocPrecision.district: return str("loc_precision_district")
        case LocPrecision.city: return str("loc_precision_city")
        case LocPrecision.province: return str("loc_precision_province")
        default: return ""
        }
    }
}
