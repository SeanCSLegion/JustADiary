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
}
