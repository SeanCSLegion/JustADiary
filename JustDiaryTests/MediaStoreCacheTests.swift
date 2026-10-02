import XCTest
import UIKit
import SwiftUI
@testable import JustDiary

/// 图片缓存：编辑器的内容装配每次都要求一遍「圆角图」。
///
/// `DiaryImageStore.rounded` 是一次完整的位图渲染 —— 1200×900 的图渲成 340×255@3x 实测
/// 17.7ms（`ScratchImageCostTests` 那次量的），而 `PartsCodec` **每装配一次内容**就要给
/// 每张图来一次：进出编辑各一次、换字号一次、旋转一次、分享长图一次。几张图叠起来就是
/// 「进编辑态卡一下」里能直接省掉的那一份。
final class MediaStoreCacheTests: XCTestCase {

    private let src = "images/unit-test-cache.jpg"

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: ImagePathUtil.resolveImagePath(src))
    }

    private func writeTestImage() throws {
        let path = ImagePathUtil.resolveImagePath(src)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: URL(fileURLWithPath: path))
    }

    private func imageParts() -> [ContentPart] {
        [ContentPart(style: ContentPartStyle.image, src: src, w: 1200, h: 900)]
    }

    private func attachmentImage(in attributed: NSAttributedString) -> UIImage? {
        var found: UIImage?
        attributed.enumerateAttribute(.attachment,
                                      in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let attachment = value as? PayloadAttachment else { return }
            found = attachment.image
            stop.pointee = true
        }
        return found
    }

    /// 同样的 src + 尺寸再装配一次：圆角图必须来自缓存（**同一个实例**）。
    func testRoundedImageComesFromTheCacheOnRebuild() throws {
        try writeTestImage()
        let first = try XCTUnwrap(attachmentImage(in: PartsCodec.attributedString(from: imageParts(),
                                                                                  imageMaxWidth: 340)))
        let second = try XCTUnwrap(attachmentImage(in: PartsCodec.attributedString(from: imageParts(),
                                                                                   imageMaxWidth: 340)))
        XCTAssertTrue(first === second, "第二次装配要复用缓存里的圆角图，而不是再渲染一张")
    }

    /// 尺寸变了（旋转 / 换字号）要按新尺寸重新渲染，不能拿旧图凑合。
    func testRoundedImageIsRenderedAgainForANewSize() throws {
        try writeTestImage()
        let wide = try XCTUnwrap(attachmentImage(in: PartsCodec.attributedString(from: imageParts(),
                                                                                 imageMaxWidth: 340)))
        let narrow = try XCTUnwrap(attachmentImage(in: PartsCodec.attributedString(from: imageParts(),
                                                                                   imageMaxWidth: 200)))
        XCTAssertFalse(wide === narrow, "列宽变了要重画")
        XCTAssertEqual(wide.size.width, 340, accuracy: 1)
        XCTAssertEqual(narrow.size.width, 200, accuracy: 1)
    }
}
