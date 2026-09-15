import Foundation

nonisolated struct AppSettings: Codable, Equatable {
    var dayStartHour: Int = 4
    var autoTime: Bool = true
    var autoLoc: Bool = true
    var allowHistoryEdit: Bool = false
    var themeMode: String = "system"
    var appLanguage: String = "system"
    var weekStart: String = "monday"
    var remindEnabled: Bool = true
    var remindHour: Int = 21
    var remindMinute: Int = 0

    enum CodingKeys: String, CodingKey {
        case dayStartHour = "day_start_hour"
        case autoTime = "auto_time"
        case autoLoc = "auto_loc"
        case allowHistoryEdit = "allow_history_edit"
        case themeMode = "theme_mode"
        case appLanguage = "app_language"
        case weekStart = "week_start"
        case remindEnabled = "remind_enabled"
        case remindHour = "remind_hour"
        case remindMinute = "remind_minute"
    }
}

nonisolated enum SettingsStore {
    static let suiteName = "group.com.cov.justdiary"
    static let defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    private static let cached = LockedBox<AppSettings?>(nil)

    static func load() -> AppSettings {
        if let value = cached.value { return value }
        let d = defaults
        var s = AppSettings()
        s.dayStartHour = d.object(forKey: "day_start_hour") as? Int ?? 4
        s.autoTime = d.object(forKey: "auto_time") as? Bool ?? true
        s.autoLoc = d.object(forKey: "auto_loc") as? Bool ?? true
        s.allowHistoryEdit = d.object(forKey: "allow_history_edit") as? Bool ?? false
        s.themeMode = d.string(forKey: "theme_mode") ?? "system"
        s.appLanguage = d.string(forKey: "app_language") ?? "system"
        s.weekStart = d.string(forKey: "week_start") ?? "monday"
        s.remindEnabled = d.object(forKey: "remind_enabled") as? Bool ?? true
        s.remindHour = d.object(forKey: "remind_hour") as? Int ?? 21
        s.remindMinute = d.object(forKey: "remind_minute") as? Int ?? 0
        if !["light", "dark", "system"].contains(s.themeMode) { s.themeMode = "system" }
        if !["system", "zh", "en"].contains(s.appLanguage) { s.appLanguage = "system" }
        if !["monday", "sunday"].contains(s.weekStart) { s.weekStart = "monday" }
        cached.value = s
        return s
    }

    static func save(_ s: AppSettings) {
        cached.value = s
        let d = defaults
        d.set(s.dayStartHour, forKey: "day_start_hour")
        d.set(s.autoTime, forKey: "auto_time")
        d.set(s.autoLoc, forKey: "auto_loc")
        d.set(s.allowHistoryEdit, forKey: "allow_history_edit")
        d.set(s.themeMode, forKey: "theme_mode")
        d.set(s.appLanguage, forKey: "app_language")
        d.set(s.weekStart, forKey: "week_start")
        d.set(s.remindEnabled, forKey: "remind_enabled")
        d.set(s.remindHour, forKey: "remind_hour")
        d.set(s.remindMinute, forKey: "remind_minute")
    }

    static var searchIndexVersion: Int {
        get { defaults.integer(forKey: "search_index_version") }
        set { defaults.set(newValue, forKey: "search_index_version") }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

nonisolated final class LockedBox<Value> {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}
