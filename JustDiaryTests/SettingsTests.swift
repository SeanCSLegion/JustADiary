import XCTest
import UIKit
@testable import JustDiary

/// 设置项的默认值与兼容性。
///
/// 新增设置项时最容易坏的两件事：旧备份（缺键）整份解不出来、以及设置项的值
/// 越界（例如分享精度被写成 `exact`）。
final class SettingsTests: XCTestCase {

    /// 设置页每一行的**说明**（`settings_*_sub`）在标准字号下都必须一行放得下。
    ///
    /// 行长这样：图标 38 + 间距 12 ｜ 标题 + 说明 ｜ 值 + 箭头。最窄的 iPhone
    /// （375pt）扣掉页边距 / 卡片内边距 / 行内边距 / 图标 / 右侧的值与箭头之后，
    /// 说明这一列只剩 ~170pt；超了就会折成两行，行高跟着跳（`settings_share_loc_sub`
    /// 第一版写了 29 个字，整整两行）。
    ///
    /// 只卡中文：英文同字号的字宽更大，现有条目本来就在 200–260pt，
    /// 靠 `rowLabel` 的 `lineLimit(2)` 兜底。
    func testSettingsRowDescriptionsFitOneLine() throws {
        let table = try stringsTable(locale: "zh-Hans")
        let font = UIFont.systemFont(ofSize: TypeSize.rowSub)
        let budget: CGFloat = 170
        for (key, text) in table where key.hasPrefix("settings_") && key.hasSuffix("_sub") {
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, budget,
                                     "「\(key)」=「\(text)」在标准字号下宽 \(Int(width))pt，超过 \(Int(budget))pt 会折行")
        }
    }

    private func stringsTable(locale: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                                subdirectory: nil, localization: locale),
                                "应有 \(locale).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    // MARK: - 默认值

    func testShareLocationDefaultsToDistrict() {
        let s = AppSettings()
        XCTAssertEqual(s.shareLocPrecision, LocPrecision.district,
                       "分享位置精度默认区县：精确地点与街道不默认外泄")
        XCTAssertEqual(s.defaultLocPrecision, LocPrecision.auto,
                       "记录精度默认跟随定位权限")
    }

    // MARK: - 与旧备份的兼容

    /// 旧版本导出的备份里没有新键。合成解码器遇到缺键会整份抛错，
    /// 而 `BackupService` 用的是 `try?` —— 表现是「导入成功但设置没恢复」。
    func testBackupWithoutTheNewKeysStillDecodes() throws {
        let json = #"{"auto_time":false,"auto_loc":false,"theme_mode":"dark","week_start":"sunday"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertFalse(s.autoTime, "旧键照常恢复")
        XCTAssertFalse(s.autoLoc)
        XCTAssertEqual(s.themeMode, "dark")
        XCTAssertEqual(s.weekStart, "sunday")
        XCTAssertEqual(s.shareLocPrecision, LocPrecision.district, "缺的键用默认值")
        XCTAssertEqual(s.defaultLocPrecision, LocPrecision.auto)
    }

    func testRoundTripThroughJSON() throws {
        var s = AppSettings()
        s.shareLocPrecision = LocPrecision.city
        s.defaultLocPrecision = LocPrecision.province
        s.dayStartHour = 2
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), s)
    }

    // MARK: - 值域

    /// 分享精度只接受「可分享」的级别：备份里塞进来的精确地点 / 街道会被收到区县。
    func testSharePrecisionCannotBeFinerThanDistrict() {
        for bad in [LocPrecision.exact, LocPrecision.street, "garbage", ""] {
            var s = AppSettings()
            s.shareLocPrecision = bad
            s.normalize()
            XCTAssertEqual(s.shareLocPrecision, LocPrecision.district,
                           "「\(bad)」不是可分享的级别，应收到区县")
        }
        for good in [LocPrecision.none] + LocPrecision.shareable {
            var s = AppSettings()
            s.shareLocPrecision = good
            s.normalize()
            XCTAssertEqual(s.shareLocPrecision, good)
        }
    }

    func testRememberedPrecisionOnlyAcceptsLadderValues() {
        var s = AppSettings()
        s.defaultLocPrecision = "garbage"
        s.normalize()
        XCTAssertEqual(s.defaultLocPrecision, LocPrecision.auto)
        s.defaultLocPrecision = LocPrecision.district
        s.normalize()
        XCTAssertEqual(s.defaultLocPrecision, LocPrecision.district)
        // 「上一次手动选的精度」不会是「没有地点」。
        s.defaultLocPrecision = LocPrecision.none
        s.normalize()
        XCTAssertEqual(s.defaultLocPrecision, LocPrecision.auto)
    }

    // MARK: - 存取

    /// `SettingsStore` 的读写要带上两个新键（读回时坏值同样被收口）。
    func testStorePersistsShareAndRecordedPrecision() {
        let original = SettingsStore.load()
        defer { SettingsStore.save(original) }

        var s = original
        s.shareLocPrecision = LocPrecision.none
        s.defaultLocPrecision = LocPrecision.city
        SettingsStore.save(s)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.shareLocPrecision, LocPrecision.none)
        XCTAssertEqual(loaded.defaultLocPrecision, LocPrecision.city)

        var bad = loaded
        bad.shareLocPrecision = LocPrecision.exact
        SettingsStore.save(bad)
        XCTAssertEqual(SettingsStore.load().shareLocPrecision, LocPrecision.district,
                       "写进去的坏值也要在读取路径上被收口")
    }
}
