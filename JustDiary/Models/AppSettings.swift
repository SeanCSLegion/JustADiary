import Foundation

nonisolated struct AppSettings: Codable, Equatable {
    var dayStartHour: Int = 4
    /// 是否自动记录并**显示**「开始时间」（对应设置项 `settings_auto_time`）。
    ///
    /// 这是**显示开关**：关闭时只隐藏编辑器时间胶囊、阅读页时间、首页时间行
    /// 与分享长图时间行。`start_time_utc` **始终照常记录**，不能写 0 ——
    /// `day_key`（`DateUtil.dayKeyForUtc`）、`created_utc` / `updated_utc` 与排序
    /// 都依赖它，且它是与 Android 端共享的 `.jdiary` / SQLite 冻结契约。
    var autoTime: Bool = true
    var autoLoc: Bool = true
    /// 分享长图里的地点精度上限（`LocPrecision.none` = 不显示地点）。
    ///
    /// 这是**上限**不是「记录的精度」：日记里照常按记录时的精度保存，只在分享时
    /// 降级。取值只能是 `LocPrecision.shareable`（区县 / 城市 / 省份）或 `none` ——
    /// 精确地点与街道**不可选**，见 `LocationResolver.shareText`。
    var shareLocPrecision: String = LocPrecision.district
    /// 上一次在编辑器里手动选过的定位精度，用于**下一条**新日记
    /// （`LocPrecision.auto` = 跟随定位权限算出来的上限）。
    ///
    /// 它只会让记录更粗：实际精度 = min(这个值, 权限上限)。见
    /// `LocationResolver.effective(precision:cap:)`。
    var defaultLocPrecision: String = LocPrecision.auto
    var allowHistoryEdit: Bool = false
    var themeMode: String = "system"
    var appLanguage: String = "system"
    var weekStart: String = "monday"
    var remindEnabled: Bool = true
    var remindHour: Int = 21
    var remindMinute: Int = 0

    init() {}

    /// 每一项都用 `decodeIfPresent` 解码。
    ///
    /// 合成的 `init(from:)` 在缺键时直接抛错 —— 备份里少一个键（旧版本导出的备份
    /// 必然如此）就会让整份设置解不出来，而 `BackupService` 用的是 `try?`，
    /// 表现是「导入成功但设置没恢复」。新加设置项时不必再动这里。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? d.dayStartHour
        autoTime = try c.decodeIfPresent(Bool.self, forKey: .autoTime) ?? d.autoTime
        autoLoc = try c.decodeIfPresent(Bool.self, forKey: .autoLoc) ?? d.autoLoc
        shareLocPrecision = try c.decodeIfPresent(String.self, forKey: .shareLocPrecision) ?? d.shareLocPrecision
        defaultLocPrecision = try c.decodeIfPresent(String.self, forKey: .defaultLocPrecision) ?? d.defaultLocPrecision
        allowHistoryEdit = try c.decodeIfPresent(Bool.self, forKey: .allowHistoryEdit) ?? d.allowHistoryEdit
        themeMode = try c.decodeIfPresent(String.self, forKey: .themeMode) ?? d.themeMode
        appLanguage = try c.decodeIfPresent(String.self, forKey: .appLanguage) ?? d.appLanguage
        weekStart = try c.decodeIfPresent(String.self, forKey: .weekStart) ?? d.weekStart
        remindEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindEnabled) ?? d.remindEnabled
        remindHour = try c.decodeIfPresent(Int.self, forKey: .remindHour) ?? d.remindHour
        remindMinute = try c.decodeIfPresent(Int.self, forKey: .remindMinute) ?? d.remindMinute
    }

    enum CodingKeys: String, CodingKey {
        case dayStartHour = "day_start_hour"
        case autoTime = "auto_time"
        case autoLoc = "auto_loc"
        case shareLocPrecision = "share_loc_precision"
        case defaultLocPrecision = "default_loc_precision"
        case allowHistoryEdit = "allow_history_edit"
        case themeMode = "theme_mode"
        case appLanguage = "app_language"
        case weekStart = "week_start"
        case remindEnabled = "remind_enabled"
        case remindHour = "remind_hour"
        case remindMinute = "remind_minute"
    }

    /// 把坏值收回合法范围。`didSet` 不管用（`load()` 是逐键读的），
    /// 所以读写两条路都要过这一道。
    mutating func normalize() {
        if !["light", "dark", "system"].contains(themeMode) { themeMode = "system" }
        if !["system", "zh", "en"].contains(appLanguage) { appLanguage = "system" }
        if !["monday", "sunday"].contains(weekStart) { weekStart = "monday" }
        // 分享**只**接受「隐藏」或可分享的级别：旧备份里若存着 exact / street
        // （或任何坏值），收到区县 —— 宁可更粗，也不能因为一次导入就把地点名
        // 放进分享图。（`none` 是合法值，别把它一起收掉。）
        if shareLocPrecision != LocPrecision.none,
           !LocPrecision.shareable.contains(shareLocPrecision) {
            shareLocPrecision = LocPrecision.district
        }
        if defaultLocPrecision != LocPrecision.auto, !LocPrecision.all.contains(defaultLocPrecision) {
            defaultLocPrecision = LocPrecision.auto
        }
        dayStartHour = min(max(dayStartHour, 0), 23)
        remindHour = min(max(remindHour, 0), 23)
        remindMinute = min(max(remindMinute, 0), 59)
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
        s.shareLocPrecision = d.string(forKey: "share_loc_precision") ?? LocPrecision.district
        s.defaultLocPrecision = d.string(forKey: "default_loc_precision") ?? LocPrecision.auto
        s.allowHistoryEdit = d.object(forKey: "allow_history_edit") as? Bool ?? false
        s.themeMode = d.string(forKey: "theme_mode") ?? "system"
        s.appLanguage = d.string(forKey: "app_language") ?? "system"
        s.weekStart = d.string(forKey: "week_start") ?? "monday"
        s.remindEnabled = d.object(forKey: "remind_enabled") as? Bool ?? true
        s.remindHour = d.object(forKey: "remind_hour") as? Int ?? 21
        s.remindMinute = d.object(forKey: "remind_minute") as? Int ?? 0
        s.normalize()
        cached.value = s
        return s
    }

    static func save(_ s: AppSettings) {
        var s = s
        s.normalize()
        cached.value = s
        let d = defaults
        d.set(s.dayStartHour, forKey: "day_start_hour")
        d.set(s.autoTime, forKey: "auto_time")
        d.set(s.autoLoc, forKey: "auto_loc")
        d.set(s.shareLocPrecision, forKey: "share_loc_precision")
        d.set(s.defaultLocPrecision, forKey: "default_loc_precision")
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

    /// Storage format version of `edit_block.content_json` (see
    /// `ContentDocument`). Kept outside `AppSettings` because it versions the
    /// *data*, not a user preference — restoring a backup must not reset it.
    static var contentFormatVersion: Int {
        get { defaults.integer(forKey: "content_format_version") }
        set { defaults.set(newValue, forKey: "content_format_version") }
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
