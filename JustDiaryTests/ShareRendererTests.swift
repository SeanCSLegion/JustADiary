import XCTest
import UIKit
@testable import JustDiary

/// 分享长图渲染器的回归。
///
/// 不比对像素（那种断言在换字体 / 换系统版本时会无意义地红），只守住四件容易坏的事：
/// 各种块样式都画得出来、尺寸跟着内容走、`auto_time` 关闭时图会变矮、
/// 空白的一天不会画出一张空卡片或崩掉。
final class ShareRendererTests: XCTestCase {

    private let dayKey = "2026-09-08"

    private func richBlocks() -> [ShareBlock] {
        [ShareBlock(time: 1788700000000, loc: "南山区 · 深圳市 · 广东省 · 中国",
                    parts: ContentFlatten.parseContent("""
                    {"v":2,"parts":[
                      {"style":"title","text":"字体样式自检"},
                      {"style":"body","text":"这一段是正文，用来和下面的标题、引用对比字号与行距。"},
                      {"style":"heading","text":"小标题"},
                      {"style":"quote","text":"引用块比正文小一级，并且有自己的底色。"},
                      {"style":"list","items":["新宿御苑","思い出横丁","都厅展望台"]},
                      {"style":"todo","items":["验证标题层级","验证引用底色","验证行距"],"done":[true,true,false]},
                      {"style":"image","src":"images/test-share.png","w":1200,"h":800}
                    ]}
                    """))]
    }

    private var testImageURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images")
        return dir.appendingPathComponent("test-share.png")
    }

    override func setUpWithError() throws {
        // 图片部件从 Documents/images 读，先放一张进去（测完删掉）。
        let url = testImageURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let size = CGSize(width: 1200, height: 800)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            ctx.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        try image.pngData()?.write(to: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testImageURL)
    }

    /// 每种块样式 + 浅色 / 深色都要画得出来，宽度固定、高度随内容增长。
    func testRendersEveryBlockStyleInBothThemes() throws {
        for isDark in [false, true] {
            let image = try XCTUnwrap(ShareRenderer.render(dayKey: dayKey, blocks: richBlocks(), isDark: isDark),
                                      "isDark=\(isDark)：应该渲染成功")
            XCTAssertEqual(image.size.width, ShareRenderer.width, "分享图宽度固定 720pt")
            XCTAssertGreaterThan(image.size.height, 900, "浅色 / 深色都应该按内容撑开高度")
            XCTAssertNotNil(image.pngData())
        }
    }

    /// `auto_time` 关闭时隐藏头部起始行与每条记录的时间，图应该明显变矮（数据不受影响）。
    func testHidingTimeMakesTheImageShorter() throws {
        let shown = try XCTUnwrap(ShareRenderer.render(dayKey: dayKey, blocks: richBlocks(),
                                                       isDark: false, showTime: true))
        let hidden = try XCTUnwrap(ShareRenderer.render(dayKey: dayKey, blocks: richBlocks(),
                                                        isDark: false, showTime: false))
        XCTAssertLessThan(hidden.size.height, shown.size.height,
                          "关掉时间显示后不该还留着时间占的高度")
    }

    /// 空白的一天：只剩品牌页眉与页脚，不该画出空卡片，也不该崩。
    func testEmptyDayRendersHeaderAndFooterOnly() throws {
        let image = try XCTUnwrap(ShareRenderer.render(dayKey: dayKey, blocks: [], isDark: false))
        XCTAssertEqual(image.size.width, ShareRenderer.width)
        XCTAssertGreaterThan(image.size.height, 200, "页眉 + 页脚也要占高度")
        XCTAssertLessThan(image.size.height, 420, "没有内容时不该撑出一张长图")
    }
}
