import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import JustDiary

/// 插入图片的落盘规则：**保原分辨率、只丢元数据**。
///
/// 改动前这里会先把图降到 2048 再按 q0.85 存，原图的分辨率就此丢失；
/// 现在按原始像素尺寸存 JPEG（q0.95），只保留 EXIF 方向，其余元数据（GPS、机型、
/// 拍摄时间）不落盘。
final class ImageInsertTests: XCTestCase {

    private var created: [URL] = []

    override func tearDownWithError() throws {
        for url in created { try? FileManager.default.removeItem(at: url) }
        created = []
    }

    // MARK: - Helpers

    /// 纯色合成图，**scale = 1**，让「点」与「像素」一一对应，断言才有意义。
    private func makeImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
        }
    }

    private func makeJPEG(_ image: UIImage, orientation: Int?, withGPS: Bool) throws -> Data {
        let cg = try XCTUnwrap(image.cgImage)
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        if withGPS {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 30.15,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 120.9,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any]
        }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func imagesDirNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: DiaryRepository.imagesDir().path)) ?? [])
    }

    /// 跑一次 `insertImage` 并返回它写出的那个文件。
    @MainActor
    private func insert(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let before = imagesDirNames()
        DiaryViewModel().insertImage(image)
        let added = imagesDirNames().subtracting(before)
        XCTAssertEqual(added.count, 1, "插入一张图应当只写一个文件，实际新增 \(added)", file: file, line: line)
        let name = try XCTUnwrap(added.first, "没有写出任何文件", file: file, line: line)
        let url = DiaryRepository.imagesDir().appendingPathComponent(name)
        created.append(url)
        return url
    }

    private func properties(of url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    // MARK: - Tests

    /// 核心：存下来的文件必须还是原始像素尺寸（旧实现会缩到 2048）。
    @MainActor
    func testInsertedImageKeepsItsOriginalPixelSize() throws {
        let url = try insert(makeImage(width: 3000, height: 2000))
        let props = try properties(of: url)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 3000, "长边 3000 的图不该被降到 2048")
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 2000)
        XCTAssertEqual(url.pathExtension, "jpg", "容器格式与扩展名保持 JPEG/.jpg")
    }

    /// 小图同样原样存（既不能缩，也不能被放大）。
    @MainActor
    func testSmallImageIsStoredAsIs() throws {
        let url = try insert(makeImage(width: 800, height: 600))
        let props = try properties(of: url)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 800)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 600)
    }

    /// 元数据策略：**留方向、丢其余**。
    ///
    /// 方向必须留：`UIImage.jpegData` 会把 `imageOrientation` 写进 EXIF，竖拍照片才不会
    /// 转 90°（若改成 ImageIO 直写 `cgImage`，这里会变成 1 —— 那正是要避免的回归）。
    /// GPS 必须丢：照片里的精确坐标不该跟着日记的备份与分享流出去。
    @MainActor
    func testStoredImageKeepsOrientationButDropsGPS() throws {
        // 方向 6 = 显示时顺时针转 90°（竖拍照片的常见取值）。
        let source = try makeJPEG(makeImage(width: 2400, height: 1600), orientation: 6, withGPS: true)
        let decoded = try XCTUnwrap(UIImage(data: source))
        XCTAssertEqual(decoded.imageOrientation, .right, "前置条件：源图带着方向 6")

        let url = try insert(decoded)
        let props = try properties(of: url)
        XCTAssertEqual(props[kCGImagePropertyOrientation] as? Int, 6, "方向丢了会让照片转 90°")
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        XCTAssertTrue(gps?.isEmpty ?? true, "GPS 不该落盘，实际: \(String(describing: gps))")
    }
}
