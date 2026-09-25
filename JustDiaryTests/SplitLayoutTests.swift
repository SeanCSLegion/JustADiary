import XCTest
import SwiftUI
@testable import JustDiary

/// 首页横屏分栏的判定与几何回归。
///
/// 背景：旧判据是 `contentWidth >= 700`，它的本意是「月历 280 + 正文 320 + 边距」，
/// 但 iPhone SE 横屏只有 **667pt**（无安全区），于是同一套横屏排版在 18 Pro 上是
/// 左右分栏、在 SE 上却只是把竖屏版面横向拉长 —— 两边都不好读。现在的判据是
/// 「横屏 + 两栏各自的最低可用宽度放得下」，本文件守住这条线：
/// - 任何横屏 iPhone 都分栏；
/// - 竖屏（含 Duo 内屏那种宽但不矮的形态）一律单栏；
/// - 分栏的两栏宽度 + 页边距 + 分隔线**正好**铺满容器，任何宽度都不溢出；
/// - 18 Pro 上已验证过的 345 / 356.5 与 330pt 日历区**一个数字都不能变**。
final class SplitLayoutTests: XCTestCase {

    /// iPhone 18 Pro 横屏：左右各 62pt 系统占位，可用宽 750、屏高 402。
    private var proLandscape: AdaptiveLayout {
        AdaptiveLayout(size: CGSize(width: 874, height: 402),
                       safeArea: EdgeInsets(top: 0, leading: 62, bottom: 20, trailing: 62))
    }

    /// iPhone SE 横屏：没有刘海也没有 home indicator，整屏都能用。
    private var seLandscape: AdaptiveLayout {
        AdaptiveLayout(size: CGSize(width: 667, height: 375), safeArea: EdgeInsets())
    }

    private func layout(_ w: CGFloat, _ h: CGFloat) -> AdaptiveLayout {
        AdaptiveLayout(size: CGSize(width: w, height: h), safeArea: EdgeInsets())
    }

    // MARK: 判定

    /// 核心回归：**SE 横屏必须分栏**，和 18 Pro 一样是左右双列。
    func testEveryLandscapePhoneSplits() {
        XCTAssertTrue(seLandscape.splitsMasterDetail, "iPhone SE 横屏必须左右分栏")
        XCTAssertTrue(proLandscape.splitsMasterDetail, "iPhone 18 Pro 横屏分栏")
        for (w, h) in [(667.0, 375.0), (812, 375), (844, 390), (852, 393), (932, 430), (956, 440)] {
            XCTAssertTrue(layout(w, h).splitsMasterDetail, "\(w)×\(h) 是横屏，应分栏")
        }
    }

    /// 竖屏一律单栏：年 / 月 / 周三态 morph 不动，Duo 内屏（宽但不矮）也走单栏。
    func testPortraitNeverSplits() {
        for (w, h) in [(375.0, 667.0), (402, 874), (664, 750), (440, 956)] {
            XCTAssertFalse(layout(w, h).splitsMasterDetail,
                           "\(w)×\(h) 不是横屏，必须保持单栏")
        }
    }

    /// 横屏、但容器窄到两栏都放不下（分屏 / 折叠态）时仍然单栏：
    /// 宁可单栏滚动，也不把正文挤成每行三四个字。
    func testNarrowLandscapeStaysSingleColumn() {
        XCTAssertEqual(AdaptiveLayout.minSplitContentWidth, 548.5, accuracy: 0.01,
                       "阈值 = 260(主栏) + 240(详情栏) + 32(页边距) + 16.5(栏间距+细线)")
        XCTAssertFalse(layout(548, 300).splitsMasterDetail)
        XCTAssertTrue(layout(549, 300).splitsMasterDetail)
    }

    // MARK: 两栏宽度

    /// 阈值以上的每一档宽度：两栏 + 页边距 + 分隔线必须**正好**等于容器宽。
    /// 少了是浪费屏宽，多了右栏会被裁掉。
    func testSplitColumnsAlwaysFillTheContainerWithoutOverflow() {
        for width in stride(from: AdaptiveLayout.minSplitContentWidth, through: 1200, by: 0.5) {
            let c = layout(width, 400).splitColumns(containerWidth: width)
            XCTAssertGreaterThanOrEqual(c.master, AdaptiveLayout.minMasterWidth)
            XCTAssertGreaterThanOrEqual(c.detail, AdaptiveLayout.minDetailWidth)
            XCTAssertEqual(c.master + c.detail
                           + 2 * AdaptiveLayout.pagePadding
                           + AdaptiveLayout.splitSeparatorWidth,
                           width, accuracy: 0.01,
                           "width=\(width)：两栏之和必须正好铺满容器")
        }
    }

    /// 18 Pro 横屏的两栏宽度与改造前完全一致（345 / 356.5）：
    /// 这次改动只该影响窄横屏，不该顺手改掉已经验证过的版面。
    func testProLandscapeKeepsTheVerifiedWidths() {
        let c = proLandscape.splitColumns(containerWidth: proLandscape.contentWidth)
        XCTAssertEqual(c.master, 345, accuracy: 0.01)
        XCTAssertEqual(c.detail, 356.5, accuracy: 0.01)
    }

    /// SE 横屏：主栏 307pt（每格 ~44pt，点得准），右栏 311.5pt（正文约一行 15 汉字）。
    func testSELandscapeColumnsStayUsable() {
        let c = seLandscape.splitColumns(containerWidth: seLandscape.contentWidth)
        XCTAssertEqual(c.master, 307, accuracy: 0.01)
        XCTAssertEqual(c.detail, 311.5, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(c.master / 7, 40, "月历每格至少 40pt 才好点")
    }

    // MARK: 高度与日历密度

    /// 底部让出的是**浮条自身的高度**（横屏 64pt）。
    ///
    /// 旧公式 `bottomInset + 44` 只在有 home indicator 的机型上碰巧等于 64；
    /// SE 横屏 `bottomInset = 0`，只让出 44pt，最后一行日期被浮条压住 20pt。
    func testSplitPaneHeightClearsTheTabBarOnBothDevices() {
        XCTAssertEqual(proLandscape.splitPaneHeight(containerHeight: 402), 330,
                       "18 Pro：402 − 8 − 64，与改造前一致")
        XCTAssertEqual(seLandscape.splitPaneHeight(containerHeight: 375), 303,
                       "SE：375 − 8 − 64（旧公式会给出 323，最后 20pt 被浮条压住）")
    }

    /// SE 横屏的日历区必须还能画出**整月六行**，不能因为矮就降级成周条。
    func testSELandscapeStillDrawsTheWholeMonthGrid() {
        let headerH = CalendarLayout.compactMonthTitleH + CalendarLayout.compactWeekdayHeaderH
        let available = seLandscape.splitPaneHeight(containerHeight: 375) - headerH
        let density = CalendarDensity.resolve(availableHeight: available, rows: 6, wantsLunar: true)
        XCTAssertFalse(density.isWeekStrip, "SE 横屏不该退化成周条")
        XCTAssertFalse(density.showsLunar, "这个高度放不下农历行")
        let cellH = density.rowHeight(availableHeight: available, rows: 6)
        XCTAssertGreaterThanOrEqual(cellH, CalendarDensity.dayRowHeight)
        XCTAssertLessThanOrEqual(cellH * 6, available,
                                 "六行不能超出日历区（超出会把最后一行裁掉）")
    }

    /// 「判定说放得下」与「实际行高」必须一致：任何可用高度下，
    /// 选中月格密度后网格都不会高过日历区。
    func testMonthGridNeverOverflowsTheAvailableHeight() {
        let headerH = CalendarLayout.compactMonthTitleH + CalendarLayout.compactWeekdayHeaderH
        for paneH in stride(from: 220.0, through: 560, by: 0.5) {
            let available = paneH - headerH
            for rows in [5, 6] {
                let density = CalendarDensity.resolve(availableHeight: available,
                                                      rows: rows, wantsLunar: true)
                guard !density.isWeekStrip else { continue }
                let cellH = density.rowHeight(availableHeight: available, rows: rows)
                XCTAssertLessThanOrEqual(cellH * CGFloat(rows), available,
                                         "paneH=\(paneH) rows=\(rows)：网格不能超出日历区")
            }
        }
    }

    /// 高度真的不够时仍然要降级成周条（内容不被压扁这条底线没有丢）。
    func testExtremelyShortPanesStillDegradeToTheWeekStrip() {
        XCTAssertTrue(CalendarDensity.resolve(availableHeight: 180, rows: 6, wantsLunar: true).isWeekStrip)
    }

    /// 高度宽裕时农历行照旧（改动的只是「没有农历行」那一档的下限）。
    func testTallPanesStillGetTheLunarRow() {
        XCTAssertTrue(CalendarDensity.resolve(availableHeight: 380, rows: 6, wantsLunar: true).showsLunar)
    }
}
