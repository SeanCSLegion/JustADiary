import XCTest
import SwiftUI
@testable import JustDiary

/// 版面判定的回归测试。
///
/// 这套判定的**唯一**依据是「可用宽度/高度」，不看机型、不看方向、不读
/// `UIScreen.main`（Duo 展开后仍是 iPhone，但宽高都是 regular，按机型分支必错）。
/// 所以这里测的是「给定一组真实尺寸，该落哪一档、分不分栏、卡片几列」。
///
/// 尺寸取真实设备值（见 docs/adaptive-layout-plan.md §2.1）：
/// iPhone 竖屏 402×874、iPhone 横屏 874×402、iPad mini 744×1133、
/// iPad 竖屏 1032×1376、iPad 横屏 1376×1032、分屏 320×1032、Mac 窗口 1432×900、
/// iPhone Duo 内屏 ≈664×750。
final class AdaptiveLayoutTests: XCTestCase {

    private func layout(_ w: CGFloat, _ h: CGFloat,
                        top: CGFloat = 0, leading: CGFloat = 0,
                        bottom: CGFloat = 0, trailing: CGFloat = 0) -> AdaptiveLayout {
        AdaptiveLayout(size: CGSize(width: w, height: h),
                       safeArea: EdgeInsets(top: top, leading: leading,
                                            bottom: bottom, trailing: trailing))
    }

    // MARK: 档位

    func testTierBoundaries() {
        XCTAssertEqual(layout(402, 874).tier, .compact)
        XCTAssertEqual(layout(664, 750).tier, .compact, "Duo 内屏展开仍是紧凑档")
        XCTAssertEqual(layout(699, 1000).tier, .compact)
        XCTAssertEqual(layout(700, 1000).tier, .medium, "700 是分栏阈值")
        XCTAssertEqual(layout(874, 402).tier, .medium, "iPhone 横屏落在中等档")
        XCTAssertEqual(layout(1032, 1376).tier, .wide)
        XCTAssertEqual(layout(999, 1000).tier, .medium)
        XCTAssertEqual(layout(1000, 1000).tier, .wide)
    }

    // MARK: 分栏

    func testSplitDecisions() {
        let portrait = layout(402, 874)
        XCTAssertFalse(portrait.splitsMasterDetail, "竖屏不分栏，保持原有 morph 交互")

        // 横屏真实安全区：左 62（系统浮条在左边缘）、右 62、下 20
        let landscape = layout(874, 402, leading: 62, bottom: 20, trailing: 62)
        XCTAssertEqual(landscape.contentWidth, 750, "可用内容宽度要扣掉左右系统占位")
        XCTAssertTrue(landscape.splitsMasterDetail, "首页：750 ≥ 700 → 分栏")
        XCTAssertFalse(landscape.splitsDashboard, "足迹：750 < 900 → 单栏")
        XCTAssertFalse(landscape.splitsSearch, "搜索：750 < 800 → 单栏 + 关键词栏")

        let duo = layout(664, 750)
        XCTAssertFalse(duo.splitsMasterDetail, "664pt 不到分栏阈值，Duo 走单栏")
        XCTAssertFalse(duo.splitsSearch, "800 以下不切搜索分栏")

        let splitScreen = layout(320, 1032)
        XCTAssertFalse(splitScreen.splitsMasterDetail, "iPad 1/3 分屏退回单栏")
        XCTAssertEqual(splitScreen.cardColumns, 1)
    }

    // MARK: 主栏宽度

    func testMasterWidthStaysUsable() {
        // 月历 7 列每格至少 ~40pt 才好点，所以主栏要夹在 280…440。
        for width in stride(from: CGFloat(700), through: 1600, by: 10) {
            let w = layout(width, 1000).masterWidth
            XCTAssertGreaterThanOrEqual(w, 280, "width=\(width)")
            XCTAssertLessThanOrEqual(w, 440, "width=\(width)")
        }
        XCTAssertEqual(layout(874, 402, leading: 62, trailing: 62).masterWidth, 345,
                       "iPhone 横屏：0.46 × 750 = 345")
    }

    // MARK: 卡片列数

    func testCardColumns() {
        XCTAssertEqual(layout(402, 874).cardColumns, 1)
        XCTAssertEqual(layout(680, 1000).cardColumns, 2)
        XCTAssertEqual(layout(874, 402).cardColumns, 2, "iPhone 横屏设置页两列")
        XCTAssertEqual(layout(1000, 1000).cardColumns, 3)
    }

    // MARK: 正文列宽

    func testContentColumnIsCapped() {
        XCTAssertEqual(layout(402, 874).contentColumn(), 322, "窄屏取屏宽 − 80")
        XCTAssertEqual(layout(1376, 1032).contentColumn(), 660, "宽屏必须限宽")
        XCTAssertEqual(layout(1376, 1032).contentColumn(620), 620)
    }

    // MARK: 系统占位

    func testSystemInsetsComeFromSafeArea() {
        // 横屏实测：浮条在左边缘、灵动岛也在左侧 → leading = 62；trailing 同为 62。
        let landscape = layout(874, 402, leading: 62, bottom: 20, trailing: 62)
        XCTAssertEqual(landscape.contentInset, 62)
        XCTAssertEqual(landscape.trailingInset, 62)
        XCTAssertEqual(landscape.bottomInset, 20)

        let portrait = layout(402, 874, top: 62, bottom: 34)
        XCTAssertEqual(portrait.contentInset, 0, "竖屏左右没有系统占位")
        XCTAssertEqual(portrait.bottomInset, 34)
    }

    /// 页面自己的水平边距**不能**再加一遍安全区。
    ///
    /// 几何原点已经在安全区内（横屏 x = 62），`adaptiveLayoutReader()` 读到的
    /// 就是那个原点。第一版把 `safeArea.leading` 又加进 `leadingPagePadding`，
    /// 于是横屏所有页面的内容相对页头右移 62pt（页头 78、卡片 140），左半屏白掉。
    func testPagePaddingDoesNotDoubleCountTheSafeArea() {
        let landscape = layout(874, 402, leading: 62, bottom: 20, trailing: 62)
        XCTAssertEqual(landscape.leadingPagePadding, AdaptiveLayout.pagePadding,
                       "横屏页面边距只应是 16，安全区已经由几何原点承担")
        XCTAssertEqual(landscape.trailingPagePadding, AdaptiveLayout.pagePadding)

        let portrait = layout(402, 874, top: 62, bottom: 34)
        XCTAssertEqual(portrait.leadingPagePadding, AdaptiveLayout.pagePadding)
    }

    // MARK: 日历密度

    func testCalendarDensityFallsBackWhenHeightIsTight() {
        // 五周、每行 ≥60pt：402pt 高的横屏（扣掉标题与星期栏 ≈300）够用。
        XCTAssertEqual(CalendarDensity.resolve(availableHeight: 300, rows: 5,
                                                wantsLunar: true),
                       .month(lunar: true))

        // 每行只够最小行高 → 牺牲农历行，而不是压扁格子。
        XCTAssertEqual(CalendarDensity.resolve(availableHeight: 240, rows: 5,
                                                wantsLunar: true),
                       .month(lunar: false))

        // 连最小行高都不够 → 降级为周条。
        XCTAssertEqual(CalendarDensity.resolve(availableHeight: 200, rows: 5,
                                                wantsLunar: true),
                       .weekStrip)
        XCTAssertEqual(CalendarDensity.resolve(availableHeight: 60, rows: 5,
                                                wantsLunar: true),
                       .weekStrip)
    }

    func testCalendarDensityRowsAndLunarFlags() {
        XCTAssertEqual(CalendarDensity.month(lunar: true).rows(monthWeeks: 5), 5)
        XCTAssertEqual(CalendarDensity.month(lunar: false).rows(monthWeeks: 6), 6)
        XCTAssertEqual(CalendarDensity.weekStrip.rows(monthWeeks: 6), 1)
        XCTAssertTrue(CalendarDensity.month(lunar: true).showsLunar)
        XCTAssertFalse(CalendarDensity.weekStrip.showsLunar)
        XCTAssertTrue(CalendarDensity.weekStrip.isWeekStrip)
    }

    /// 大字号下每行需要更高，密度应更早降级。
    func testCalendarDensityAccountsForLargeText() {
        // 同样高度下，行数越多每行越矮 —— 6 行时会先放弃农历
        XCTAssertEqual(CalendarDensity.resolve(availableHeight: 300, rows: 6,
                                                wantsLunar: true).showsLunar, false)
        XCTAssertEqual(CalendarDensity.resolve(availableHeight: 300, rows: 5,
                                                wantsLunar: true).showsLunar, true)
    }

    // MARK: 日号字号

    func testDayFontShrinksWithCellHeight() {
        // 原来写死 20pt：横屏格子只剩 ~40pt 时，20pt 日号 + 11pt 农历必然重叠。
        XCTAssertEqual(MonthPane.dayFont(for: 44), 14.96, accuracy: 0.01)
        XCTAssertEqual(MonthPane.dayFont(for: 56), 19.04, accuracy: 0.01)
        XCTAssertEqual(MonthPane.lunarFont(for: 44), 9, accuracy: 0.01)
        // 矮格子也不会小到看不见
        XCTAssertEqual(MonthPane.dayFont(for: 20), 13, accuracy: 0.01)
        XCTAssertLessThanOrEqual(MonthPane.dayFont(for: 200), 20, "上限仍是 20pt")
        XCTAssertLessThanOrEqual(MonthPane.lunarFont(for: 200), 11)
    }

    // MARK: 月历几何（年↔月 / 月↔周 morph 的终点）

    /// 竖屏 `MonthPane` 的网格起点必须与 morph 的终点重合。
    ///
    /// 回归点：横屏引入紧凑标题行时，`MonthPane` 的标题槽默认值被改成了 32pt，
    /// morph 仍按 72pt 算 —— 动画收尾时月历整体上跳 40pt。
    func testMonthGridOriginIsSharedWithMorphs() {
        // MonthPane 的默认标题槽 / 星期栏就是 morph 用的那组常量。
        XCTAssertEqual(MonthPane.portraitTitleHeight, CalendarLayout.bigTitleH)
        XCTAssertEqual(MonthPane.portraitWeekdayHeight, CalendarLayout.weekdayHeaderH)

        for height in [600, 714, 800] as [CGFloat] {
            let morph = CalendarLayout.fullMonthGridRect(in: CGSize(width: 402, height: height))
            XCTAssertEqual(morph.minY, MonthPane.portraitGridOriginY, accuracy: 0.001)
            XCTAssertEqual(morph.minY, CalendarLayout.bigTitleH + CalendarLayout.weekdayHeaderH,
                           accuracy: 0.001)
        }
    }

    /// 六行月格正好铺满日历区：标题槽 + 星期栏 + 6 行 = areaH。
    /// 若 `monthCellH` 与标题槽不是同一套常量，月历底部会留一段空白（或溢出）。
    func testMonthGridFillsCalendarArea() {
        for areaH in [600, 714, 800, 900] as [CGFloat] {
            let bottom = MonthPane.portraitGridOriginY + 6 * CalendarLayout.monthCellH(areaH: areaH)
            XCTAssertEqual(bottom, areaH, accuracy: 0.001, "areaH=\(areaH)")
        }
    }

    /// 年历迷你日期用「按格宽推导」的字号，且与 morph 起点同源。
    /// 这里守住「不再写死 11pt」这件事（写死会让 morph 收尾时日期字号突然缩一下）。
    func testMiniMonthMetricsAreGridDerived() {
        let size = CGSize(width: 402, height: 810)
        let grid = CalendarLayout.miniGridRect(month: 1, in: size)
        let m = CalendarLayout.miniMetrics(in: size)
        XCTAssertEqual(m.cellW, grid.width / 7, accuracy: 0.001)
        XCTAssertEqual(m.cellH, grid.height / 6, accuracy: 0.001)
        XCTAssertEqual(m.dayFont,
                       CalendarLayout.miniDayFont(cellW: grid.width / 7, cellH: grid.height / 6),
                       accuracy: 0.001)
        XCTAssertGreaterThan(m.dayFont, 11, "年历迷你日期不应再写死 11pt")
        XCTAssertEqual(m.lunarAlpha, 0, "迷你月不画农历")
        XCTAssertEqual(m.dividerAlpha, 0, "迷你月不画分隔线")
    }

    // MARK: 横屏分栏的垂直预算

    /// 横屏日历区（标题 + 星期栏 + 六行）必须在底部系统浮条之上结束，
    /// 否则最后一行日期会被浮条压住。
    func testLandscapeCalendarClearsTheFloatingTabBar() {
        // iPhone 18 Pro 横屏：屏幕高 402，浮条占 y 338…402（实测），底部安全区 20。
        let screenH: CGFloat = 402
        let topPad: CGFloat = 8
        let bottomInset: CGFloat = 20
        let bottomClearance = bottomInset + 44
        let paneH = screenH - topPad - bottomClearance
        let headerH = CalendarLayout.compactMonthTitleH + CalendarLayout.compactWeekdayHeaderH
        let cellH = max(CalendarDensity.minimumRowHeight, ((paneH - headerH) / 6).rounded())
        let bottom = topPad + headerH + 6 * cellH
        XCTAssertLessThanOrEqual(bottom, 338, "日历最后一行必须在浮条上沿之上")
        XCTAssertGreaterThanOrEqual(cellH, CalendarDensity.minimumRowHeight,
                                    "六行月格仍要放得下")
    }
}
