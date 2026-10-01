import XCTest

/// 日历（连续月历流）的无障碍约定。
///
/// 整条流对旁白是**一个**元素（逐个日期建元素会把转子淹掉），它挂着：
/// - 「可调节」动作：上下轻扫 = 选中相邻的一天；
/// - 两条**具名动作**：后一天 / 前一天。
///
/// 之所以要具名动作：「可调节」这个动作本身在旁白里没有名字，只会念「可调整」+ 当前
/// 日期，用户不知道上下轻扫会做什么。具名动作会进「操作」转子，念得出「后一天 /
/// 前一天」—— 这两条文案曾经因为零引用被当作无用键删掉过，接回时一并补上这个测试，
/// 免得再被清掉。
final class CalendarAccessibilityTests: XCTestCase {

    /// 两条文案必须在**编译产物**的两种语言里都存在且非空。
    ///
    /// `Localizable.xcstrings` 是唯一真源，但真源里有、包里没有（或某个语言漏了）都会
    /// 让旁白念出 key 本身，所以这里读的是 App bundle 里编译好的 `.lproj` 表。
    func testCalendarDayActionsAreLocalizedInBothLanguages() throws {
        for locale in ["zh-Hans", "en"] {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                subdirectory: nil, localization: locale),
                "应有 \(locale).lproj/Localizable.strings")
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                                      "\(locale) 的 Localizable.strings 应该能读成字典")

            for key in ["a11y_next_day", "a11y_prev_day"] {
                let value = table[key]
                XCTAssertNotNil(value, "\(locale) 缺少「\(key)」（日历的具名无障碍动作要用）")
                XCTAssertFalse((value ?? "").isEmpty, "\(locale) 的「\(key)」是空的")
            }
        }
    }

    /// 两条文案的语义不能反：`a11y_next_day` 是后一天、`a11y_prev_day` 是前一天。
    func testDayActionKeysKeepTheirMeaning() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                            subdirectory: nil, localization: "zh-Hans"))
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertEqual(table["a11y_next_day"], "后一天")
        XCTAssertEqual(table["a11y_prev_day"], "前一天")
    }
}
