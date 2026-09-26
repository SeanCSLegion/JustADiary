import XCTest
import SwiftUI
@testable import JustDiary

/// 日记页正文列宽的回归测试。
///
/// `AdaptiveLayout.contentColumn` 返回的是**正文列本身**的宽度上限，页面内边距
/// （`adaptivePagePadding()`，左右各 16）由调用方加在它外面。窄屏不能在这里再缩
/// 一圈：原来的 `size.width - 80` 会和页面边距叠成 56pt 的左右留白，竖屏日记页的
/// 正文列只剩 290pt —— 顶部的卡片因此比下面的卡片明显偏小。
final class AdaptiveLayoutTests: XCTestCase {

    private func layout(_ w: CGFloat, _ h: CGFloat) -> AdaptiveLayout {
        AdaptiveLayout(size: CGSize(width: w, height: h), safeArea: EdgeInsets())
    }

    /// 核心回归：紧凑宽度下「正文列 + 左右页面边距」必须正好铺满屏宽。
    ///
    /// 只有宽屏才应该被 `maxWidth` 截住；窄屏多减任何一点都会让卡片的左右留白
    /// 比页面自己的 16pt 更宽。
    func testColumnPlusPagePaddingFillsCompactScreens() {
        for width in stride(from: CGFloat(300), through: 690, by: 10) {
            let column = layout(width, 874).contentColumn()
            XCTAssertEqual(column, width - 2 * AdaptiveLayout.pagePadding,
                           "width=\(width)：紧凑屏不该在页面边距之外再缩")
            XCTAssertEqual(column + 2 * AdaptiveLayout.pagePadding, width,
                           "width=\(width)：列 + 页面边距必须等于屏宽")
        }
    }

    /// 手机横屏：屏宽够宽时，阅读列按 660、编辑列按 620 截断。
    func testWideScreensAreCappedAtTheColumnLimit() {
        XCTAssertEqual(layout(874, 402).contentColumn(), 660, "手机横屏阅读列")
        XCTAssertEqual(layout(874, 402).contentColumn(620), 620, "手机横屏编辑列")
    }

    /// 极窄时列宽仍然为正，且不会掉到兜底下限以下。
    func testVeryNarrowScreensKeepAUsableMinimum() {
        XCTAssertEqual(layout(320, 874).contentColumn(), 320 - 2 * AdaptiveLayout.pagePadding)
        XCTAssertEqual(layout(200, 874).contentColumn(), 240, "兜底宽度")
    }

    // MARK: 首页单栏（竖屏）：日历区必须让开底部浮条

    /// 首页单栏的日历区必须在**底部系统浮条之上**结束。
    ///
    /// 18 Pro 竖屏实测：屏 402×874、安全区 `T62 L0 B34 R0`、浮条 `(0, 791, 402, 83)`。
    /// `HomeView` 的几何因为 `.ignoresSafeArea(edges: .bottom)` 是「屏高 − 顶部安全区」
    /// = 812，日历区顶边在屏幕上 y = 62（顶部安全区）+ 64（头部）= 126。
    /// 旧算法 `h = max(320, 几何高 − 64) = 748`：六行月格底边 = 126 + 748 = 874
    /// （正好屏底）、年历末行卡片 709→874，而浮条从 y 791 起 —— 年视图与月视图的
    /// 最后一整行日期都被浮条盖住。
    func testSingleColumnCalendarEndsAboveTheTabBar() {
        let topInset: CGFloat = 62
        let screenH: CGFloat = 874
        let tabBarTop: CGFloat = 791          // app.tabBars frame.minY（实测）
        let headerH: CGFloat = 12 + 52        // HomeView 的头部整块

        XCTAssertEqual(layout(402, 874).tabBarClearance, 83, "竖屏浮条高度（实测 83pt）")
        let h = layout(402, 874).singleColumnCalendarHeight(containerHeight: screenH - topInset,
                                                           headerHeight: headerH)
        XCTAssertEqual(h, 665, "812 − 64（头部）− 83（浮条）")

        // 月视图：六行月份正好铺满日历区，它的底边就是日历区底边。
        let gridBottom = topInset + headerH + CalendarLayout.bigTitleH
            + CalendarLayout.weekdayHeaderH + CalendarLayout.monthCellH(areaH: h) * 6
        XCTAssertLessThanOrEqual(gridBottom, tabBarTop + 0.5,
                                 "六行月格底边 \(gridBottom) 越过了浮条顶边 \(tabBarTop)")

        // 年视图：4 行迷你月也正好铺满日历区（`yearCardSize` 按容器高反推）。
        let yearBottom = topInset + headerH
            + CalendarLayout.yearCardRect(month: 12, in: CGSize(width: 402, height: h)).maxY
        XCTAssertLessThanOrEqual(yearBottom, tabBarTop + 0.5,
                                 "年历末行卡片底边 \(yearBottom) 越过了浮条顶边 \(tabBarTop)")
    }

    /// 日历区不能为了避让浮条而变得不可用：竖屏各机型上仍要放得下六行月格。
    func testSingleColumnCalendarStaysUsableOnEveryPortraitPhone() {
        // 屏宽 / 屏高 / 顶部安全区：SE、18 Pro、更大屏、Duo 内屏（按现行判据都走单栏）。
        let devices: [(w: CGFloat, h: CGFloat, top: CGFloat)] = [
            (375, 667, 20), (402, 874, 62), (440, 956, 62), (664, 750, 24)
        ]
        for device in devices {
            let h = layout(device.w, device.h)
                .singleColumnCalendarHeight(containerHeight: device.h - device.top,
                                            headerHeight: 64)
            let cellH = CalendarLayout.monthCellH(areaH: h)
            XCTAssertGreaterThanOrEqual(cellH, 40,
                                        "\(device.w)×\(device.h)：六行月格只剩 \(cellH)pt 一格")
        }
    }

    /// 横屏（还没分栏的窄窗口）也要让开横屏那枚 64pt 的浮条。
    func testSingleColumnCalendarUsesTheLandscapeTabBarHeight() {
        let landscape = layout(500, 375)
        XCTAssertEqual(landscape.tabBarClearance, 64, "横屏浮条高度（实测 64pt）")
        XCTAssertEqual(landscape.singleColumnCalendarHeight(containerHeight: 440, headerHeight: 64),
                       440 - 64 - 64)
        // 高度真的不够时不再坚持任何下限：宁可日历区变矮，也不能越过浮条
        // （窄横屏单栏：屏高 375 − 头部 64 − 浮条 64 = 247）。
        XCTAssertEqual(landscape.singleColumnCalendarHeight(containerHeight: 375, headerHeight: 64),
                       247)
    }
}
