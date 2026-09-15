import Foundation
import UIKit
import ImageIO

// MARK: - Content part parse cache

final class ContentPartCache {
    static let shared = ContentPartCache()

    private let lock = NSLock()
    private var storage: [String: [ContentPart]] = [:]
    private var order: [String] = []
    private let capacity = 300

    func parts(for json: String) -> [ContentPart] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[json] {
            return cached
        }
        let parsed = ContentFlatten.parseContent(json)
        storage[json] = parsed
        order.append(json)
        if order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
        return parsed
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
    }
}

extension ContentFlatten {
    static func parseContentCached(_ json: String) -> [ContentPart] {
        ContentPartCache.shared.parts(for: json)
    }
}

// MARK: - Downsampled image store

nonisolated final class DiaryImageStore {
    static let shared = DiaryImageStore()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 150 * 1024 * 1024
    }

    func image(for src: String, maxPixel: CGFloat) -> UIImage? {
        let key = normalizeKey(src)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let image = DiaryImageStore.loadDownsampled(at: ImagePathUtil.resolveImagePath(src), maxPixel: maxPixel) else {
            return nil
        }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }

    func invalidate(src: String) {
        cache.removeObject(forKey: normalizeKey(src) as NSString)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }

    static func downsample(_ image: UIImage, maxPixel: CGFloat) -> UIImage? {
        guard maxPixel > 0 else { return image }
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxPixel else { return image }
        guard let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData() else { return image }
        return loadDownsampled(data: data, maxPixel: maxPixel)
    }

    static func rounded(_ image: UIImage, size: CGSize, radius: CGFloat) -> UIImage {
        guard radius > 0, size.width > 0, size.height > 0 else { return image }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            path.addClip()
            let scale = min(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    static func loadDownsampled(at path: String, maxPixel: CGFloat) -> UIImage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return loadDownsampled(data: data, maxPixel: maxPixel)
    }

    static func loadDownsampled(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func normalizeKey(_ src: String) -> String {
        src
    }
}
