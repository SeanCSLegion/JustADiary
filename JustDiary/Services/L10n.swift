import Foundation
import SwiftUI

nonisolated enum AppLanguage {
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

nonisolated enum L10n {
    // NOTE: These must NOT be built on String(localized:locale:). On iOS that
    // initializer resolves strings against the app's *active* language (the
    // AppleLanguages preference) and ignores the passed locale, so the UI would
    // stay in the launch language no matter what AppLanguage says — exactly the
    // "language only half switches after a restart" bug. Reading the compiled
    // Localizable.strings table of the requested .lproj bundle is deterministic.
    static func str(_ key: String) -> String {
        lookup(key, locale: AppLanguage.current)
    }

    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        let format = lookup(key, locale: AppLanguage.current)
        return String(format: format, arguments: args)
    }

    private static func lookup(_ key: String, locale: String) -> String {
        let loc = normalizedLocale(locale)
        if let value = table(for: loc)[key] { return value }
        // Fall back to the catalog's source language (en) before returning the key.
        if loc != "en", let value = table(for: "en")[key] { return value }
        return key
    }

    private static let tableLock = NSLock()
    private static var tables: [String: [String: String]] = [:]

    private static func table(for locale: String) -> [String: String] {
        tableLock.lock()
        defer { tableLock.unlock() }
        if let cached = tables[locale] { return cached }
        var result: [String: String] = [:]
        if let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                     subdirectory: nil, localization: locale),
           let dict = NSDictionary(contentsOf: url) as? [String: String] {
            result = dict
        }
        tables[locale] = result
        return result
    }

    /// Maps a locale identifier to the closest bundle localization. The system
    /// language is usually region-qualified ("zh-Hans-CN", "en-CN"), but the
    /// bundle only ships generic localizations ("zh-Hans", "en").
    private static let availableLocalizations: [String] = Bundle.main.localizations

    private static func normalizedLocale(_ locale: String) -> String {
        let lower = locale.lowercased()
        if availableLocalizations.contains(locale) { return locale }
        let parts = lower.split(separator: "-").map(String.init)
        guard let lang = parts.first else { return "en" }
        let candidates = availableLocalizations.filter { $0.lowercased().hasPrefix(lang) }
        if !candidates.isEmpty {
            if parts.count >= 2,
               let scriptMatch = candidates.first(where: { $0.lowercased().contains(parts[1]) }) {
                return scriptMatch
            }
            return candidates[0]
        }
        return "en"
    }

    // Locale-dependent formatters/calculators are cached per locale identifier so
    // that an in-app language switch takes effect immediately. The old `static let`
    // instances were created once per process and kept the launch locale forever,
    // leaving calendar headers / month names / timestamps in the previous language
    // until the app was restarted.
    private static let lock = NSLock()
    private static var calendars: [String: Calendar] = [:]
    private static var formatters: [String: DateFormatter] = [:]

    private static func calendar() -> Calendar {
        let id = AppLanguage.current
        lock.lock()
        defer { lock.unlock() }
        if let cached = calendars[id] { return cached }
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: id)
        cal.timeZone = .current
        calendars[id] = cal
        return cal
    }

    private static func formatter(_ dateFormat: String) -> DateFormatter {
        let id = "\(AppLanguage.current)|\(dateFormat)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[id] { return cached }
        let f = DateFormatter()
        f.locale = Locale(identifier: AppLanguage.current)
        f.dateFormat = dateFormat
        formatters[id] = f
        return f
    }

    /// Clock-time formatter that follows both the app language and the system
    /// 24-hour setting.
    ///
    /// This used to be a literal `dateFormat = "HH:mm"`, which hard-codes a
    /// 24-hour clock: an English user saw "Started at 21:00" on a card while
    /// the day-start row on the settings screen said "4:00 AM". The hour cycle
    /// now comes from the *device* locale (`j` is the skeleton symbol for "the
    /// locale's preferred hour cycle", which honours 设置 › 通用 › 日期与时间 ›
    /// 24 小时制) while AM/PM symbols still come from the app language.
    private static func timeFormatter() -> DateFormatter {
        let id = "time|\(AppLanguage.current)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[id] { return cached }
        let appLocale = Locale(identifier: AppLanguage.current)
        let deviceFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h"
        let uses24Hour = deviceFormat.contains("H") || deviceFormat.contains("k")
        let f = DateFormatter()
        f.locale = appLocale
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: uses24Hour ? "Hmm" : "hmm",
                                                options: 0, locale: appLocale)
        formatters[id] = f
        return f
    }

    static func weekdayShort(_ weekdayIndex: Int) -> String {
        let symbols = calendar().veryShortWeekdaySymbols
        guard symbols.indices.contains(weekdayIndex) else { return "" }
        return symbols[weekdayIndex]
    }

    static func weekdayName(_ weekdayIndex: Int) -> String {
        let symbols = calendar().shortWeekdaySymbols
        guard symbols.indices.contains(weekdayIndex) else { return "" }
        return symbols[weekdayIndex]
    }

    static func weekdayNames(weekStart: String) -> [String] {
        let symbols = calendar().veryShortWeekdaySymbols
        let base = weekStart == "sunday" ? 0 : 1
        return (0..<7).map { symbols[(base + $0) % 7] }
    }

    static func monthName(_ month: Int) -> String {
        let symbols = calendar().shortMonthSymbols
        guard symbols.indices.contains(month - 1) else { return "" }
        return symbols[month - 1]
    }

    static func dayTitle(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let wd = cal.component(.weekday, from: date)
        return fmt("date_day_title", monthName(month), day, weekdayName(wd - 1))
    }

    static func dateOnly(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return fmt("date_day_only", monthName(month), day)
    }

    static func dateRange(_ from: Date, _ to: Date) -> String {
        // Was string-concatenated with a "~" separator while the week header
        // used an en dash for a different job; ranges now share one localized
        // en-dash pattern.
        fmt("date_range", dateOnly(from), dateOnly(to))
    }

    static func monthFull(_ date: Date) -> String {
        formatter("MMMM").string(from: date)
    }

    static func weekHeaderTitle(_ date: Date) -> String {
        let cal = DateUtil.calendar
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let wd = cal.component(.weekday, from: date)
        return fmt("index_week_head", y, monthName(m), d, weekdayName(wd - 1))
    }

    static func formatDayKey(_ dayKey: String) -> String {
        guard let date = DateUtil.parseDayKey(dayKey) else { return dayKey }
        return dayTitle(date)
    }

    static func timeOf(_ utcMs: Int64) -> String {
        timeFormatter().string(from: Date(timeIntervalSince1970: Double(utcMs) / 1000))
    }

    /// Clock time for a bare hour/minute pair (reminder time, day-start time).
    static func timeLabel(hour: Int, minute: Int) -> String {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = 1
        comps.day = 1
        comps.hour = hour
        comps.minute = minute
        let date = DateUtil.calendar.date(from: comps) ?? Date()
        return timeFormatter().string(from: date)
    }

    /// Capsule label for the selected day: 今天 / 昨天 / 明天 / N天前 / N天后.
    static func relativeDayLabel(from date: Date, to today: Date) -> String {
        let diff = DateUtil.relativeDays(from: date, to: today)
        switch diff {
        case 0: return str("index_today")
        case -1: return str("index_yesterday")
        case 1: return str("index_tomorrow")
        case ..<0: return fmt("index_days_ago", -diff)
        default: return fmt("index_days_later", diff)
        }
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
