import SwiftUI
import CoreGraphics

struct GeoMapCanvas: View {
    var geoData: GeoDataSet
    var camera: GeoCamera
    var level: Int
    var focusProvince: GeoFeature?
    var focusCountry: GeoFeature?
    var points: [MapPoint]
    var isZh: Bool
    var isDark: Bool

    var body: some View {
        Canvas { context, size in
            let vpW = size.width
            let vpH = size.height
            let s = GeoMath.camScale(camera.zoom)
            let centerX = GeoMath.lngToX(camera.centerLng)
            let centerY = GeoMath.latToY(camera.centerLat)
            let dark = isDark
            let water = dark ? UIColor(hex: 0x20242C) : UIColor(hex: 0xDCE8F2)

            context.fill(Path(CGRect(x: 0, y: 0, width: vpW, height: vpH)), with: .color(Color(uiColor: water)))

            let screenRect = CGRect(x: -40, y: -40, width: vpW + 80, height: vpH + 80)

            func toScreen(_ wx: Double, _ wy: Double) -> CGPoint {
                CGPoint(x: (wx - centerX) * s + vpW / 2, y: (wy - centerY) * s + vpH / 2)
            }

            func isVisible(_ f: GeoFeature) -> Bool {
                let a = toScreen(f.minX, f.minY)
                let b = toScreen(f.maxX, f.maxY)
                let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                  width: abs(b.x - a.x), height: abs(b.y - a.y))
                return rect.intersects(screenRect)
            }

            if level == 0 {
                drawWorld(context, isZh: isZh, dark: dark, s: s, centerX: centerX, centerY: centerY, vpW: vpW, vpH: vpH)
            } else if level == 1 {
                if let country = focusCountry, country.name != "China" {
                    drawForeignCountry(context, country, dark: dark, s: s, centerX: centerX, centerY: centerY,
                                       vpW: vpW, vpH: vpH, isVisible: isVisible, toScreen: toScreen)
                } else {
                    drawChina(context, dark: dark, s: s, centerX: centerX, centerY: centerY, vpW: vpW, vpH: vpH, isVisible: isVisible, toScreen: toScreen)
                }
            } else {
                drawProvince(context, dark: dark, s: s, centerX: centerX, centerY: centerY, vpW: vpW, vpH: vpH, isVisible: isVisible, toScreen: toScreen)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Level 0

    private func drawWorld(_ context: GraphicsContext, isZh: Bool, dark: Bool,
                           s: Double, centerX: Double, centerY: Double, vpW: Double, vpH: Double) {
        let land = dark ? UIColor(hex: 0x2A2F38) : UIColor(hex: 0xEFECE3)
        let borderColor = dark ? UIColor(hex: 0x3D4350) : UIColor(hex: 0xC8C4BC)
        let counts = countriesWithCounts()
        let maxCount = max(1, counts.values.max() ?? 1)
        for f in geoData.world {
            let a = CGPoint(x: (f.minX - centerX) * s + vpW / 2, y: (f.minY - centerY) * s + vpH / 2)
            let b = CGPoint(x: (f.maxX - centerX) * s + vpW / 2, y: (f.maxY - centerY) * s + vpH / 2)
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            guard rect.intersects(CGRect(x: -40, y: -40, width: vpW + 80, height: vpH + 80)) else { continue }
            var path = Path()
            for ring in f.rings {
                let pts = ring.pts
                guard pts.count >= 6 else { continue }
                path.move(to: CGPoint(x: (pts[0] - centerX) * s + vpW / 2, y: (pts[1] - centerY) * s + vpH / 2))
                var i = 2
                while i < pts.count {
                    path.addLine(to: CGPoint(x: (pts[i] - centerX) * s + vpW / 2, y: (pts[i + 1] - centerY) * s + vpH / 2))
                    i += 2
                }
                path.closeSubpath()
            }
            let count = counts[f.name] ?? 0
            let fill = heatColor(count: count, maxCount: maxCount, dark: dark, fallback: land)
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(Color(uiColor: borderColor)), lineWidth: 0.5)
        }
        let labelColor = dark ? UIColor(hex: 0x9AA3B2) : UIColor(hex: 0x667085)
        let counted = counts
        for f in geoData.world where counted[f.name] != nil {
            let p = CGPoint(x: (f.cx - centerX) * s + vpW / 2, y: (f.cy - centerY) * s + vpH / 2)
            guard p.x > -20, p.x < vpW + 20, p.y > -20, p.y < vpH + 20 else { continue }
            let name = GeoMap.countryName(f.name, isZh: isZh)
            let count = counted[f.name] ?? 0
            drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 8), size: 14, color: labelColor, stroke: true)
            drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + 12), size: 18, color: labelColor, stroke: false)
        }
    }

    private func countriesWithCounts() -> [String: Int] {
        var map: [String: Int] = [:]
        for p in points where !p.country.isEmpty {
            map[GeoMap.countryKey(p.country), default: 0] += 1
        }
        return map
    }

    // MARK: - Level 1

    private func drawChina(_ context: GraphicsContext, dark: Bool, s: Double, centerX: Double, centerY: Double,
                           vpW: Double, vpH: Double, isVisible: (GeoFeature) -> Bool, toScreen: (Double, Double) -> CGPoint) {
        let land = dark ? UIColor(hex: 0x2A2F38) : UIColor(hex: 0xEFECE3)
        let borderColor = dark ? UIColor(hex: 0x3D4350) : UIColor(hex: 0xC8C4BC)
        let counts = provinceCounts()
        let maxCount = max(1, counts.values.max() ?? 1)
        for f in geoData.china {
            guard isVisible(f) else { continue }
            var path = Path()
            for ring in f.rings {
                let pts = ring.pts
                guard pts.count >= 6 else { continue }
                path.move(to: toScreen(pts[0], pts[1]))
                var i = 2
                while i < pts.count {
                    path.addLine(to: toScreen(pts[i], pts[i + 1]))
                    i += 2
                }
                path.closeSubpath()
            }
            let count = counts[f.name] ?? 0
            let fill = heatColor(count: count, maxCount: maxCount, dark: dark, fallback: land)
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(Color(uiColor: borderColor)), lineWidth: 0.8)
            if count > 0 {
                let p = toScreen(f.cx, f.cy)
                if p.x > -20, p.x < vpW + 20, p.y > -20, p.y < vpH + 20 {
                    let fontSize = s < 32 ? 13.0 : (s < 64 ? 15.0 : 17.0)
                    let countSize = s < 32 ? 14.0 : (s < 64 ? 18.0 : 22.0)
                    let labelColor = dark ? UIColor(hex: 0xF5F6F8) : UIColor(hex: 0x191C20)
                    let name = GeoMap.displayName(f.name, isZh: isZh, level: "province")
                    drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 10), size: fontSize, color: labelColor, stroke: true)
                    drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + fontSize / 2 + 8), size: countSize, color: labelColor, stroke: false)
                }
            }
        }
    }

    private func provinceCounts() -> [String: Int] {
        var map: [String: Int] = [:]
        for p in points where !p.region1.isEmpty {
            map[p.region1, default: 0] += 1
        }
        return map
    }

    // MARK: - Foreign country (drill-down target at national level)

    private func drawForeignCountry(_ context: GraphicsContext, _ f: GeoFeature, dark: Bool,
                                    s: Double, centerX: Double, centerY: Double, vpW: Double, vpH: Double,
                                    isVisible: (GeoFeature) -> Bool, toScreen: (Double, Double) -> CGPoint) {
        let land = dark ? UIColor(hex: 0x2A2F38) : UIColor(hex: 0xEFECE3)
        guard isVisible(f) else { return }
        var path = Path()
        for ring in f.rings {
            let pts = ring.pts
            guard pts.count >= 6 else { continue }
            path.move(to: toScreen(pts[0], pts[1]))
            var i = 2
            while i < pts.count {
                path.addLine(to: toScreen(pts[i], pts[i + 1]))
                i += 2
            }
            path.closeSubpath()
        }
        context.fill(path, with: .color(Color(uiColor: land)))
        context.stroke(path, with: .color(Theme.primary()), lineWidth: 2)
        let p = toScreen(f.cx, f.cy)
        let labelColor = dark ? UIColor(hex: 0xF5F6F8) : UIColor(hex: 0x191C20)
        let name = GeoMap.countryName(f.name, isZh: isZh)
        drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 10), size: 17, color: labelColor, stroke: true)
    }

    private func heatColor(count: Int, maxCount: Int, dark: Bool, fallback: UIColor) -> Color {
        guard count > 0 else { return Color(uiColor: fallback) }
        let ratio = Double(count) / Double(maxCount)
        let k = sqrt(ratio)
        let r: CGFloat = dark ? lerp(42, 90, k) : lerp(43, 80, k)
        let g: CGFloat = dark ? lerp(47, 70, k) : lerp(93, 100, k)
        let b: CGFloat = dark ? lerp(56, 183, k) : lerp(183, 210, k)
        let alpha: CGFloat = dark ? lerp(0.3, 0.9, k) : lerp(0.15, 0.85, k)
        return Color(red: r/255, green: g/255, blue: b/255).opacity(alpha)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    // MARK: - Level 2

    private func drawProvince(_ context: GraphicsContext, dark: Bool, s: Double, centerX: Double, centerY: Double,
                              vpW: Double, vpH: Double, isVisible: (GeoFeature) -> Bool, toScreen: (Double, Double) -> CGPoint) {
        let land = dark ? UIColor(hex: 0x2A2F38) : UIColor(hex: 0xEFECE3)
        let cityBorderColor = dark ? UIColor(hex: 0x5A6370) : UIColor(hex: 0xA09C94)
        let cityFillColor = dark ? UIColor(hex: 0x333A44) : UIColor(hex: 0xE8E5DC)
        let target = focusProvince ?? nearestFeatureAtCenter(s: s, centerX: centerX, centerY: centerY)
        guard let target else { return }
        var path = Path()
        for ring in target.rings {
            let pts = ring.pts
            guard pts.count >= 6 else { continue }
            path.move(to: toScreen(pts[0], pts[1]))
            var i = 2
            while i < pts.count {
                path.addLine(to: toScreen(pts[i], pts[i + 1]))
                i += 2
            }
            path.closeSubpath()
        }
        context.fill(path, with: .color(Color(uiColor: land)))
        context.stroke(path, with: .color(Theme.primary()), lineWidth: 2)

        let counts = cityCounts(target)
        let maxCount = max(1, counts.values.max() ?? 1)
        let cities = geoData.cities[target.adcode] ?? []
        if !cities.isEmpty {
            for f in cities {
                guard isVisible(f) else { continue }
                var cpath = Path()
                for ring in f.rings {
                    let pts = ring.pts
                    guard pts.count >= 6 else { continue }
                    cpath.move(to: toScreen(pts[0], pts[1]))
                    var i = 2
                    while i < pts.count {
                        cpath.addLine(to: toScreen(pts[i], pts[i + 1]))
                        i += 2
                    }
                    cpath.closeSubpath()
                }
                let count = counts[f.name] ?? 0
                let fill = count > 0
                    ? heatColor(count: count, maxCount: maxCount, dark: dark, fallback: land)
                    : Color(uiColor: cityFillColor)
                context.fill(cpath, with: .color(fill))
                context.stroke(cpath, with: .color(Color(uiColor: cityBorderColor)), lineWidth: 1.0)
                if count > 0 {
                    let p = toScreen(f.cx, f.cy)
                    let labelColor = dark ? UIColor(hex: 0xF5F6F8) : UIColor(hex: 0x191C20)
                    let name = GeoMap.displayName(f.name, isZh: isZh, level: "city")
                    drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 8), size: 13, color: labelColor, stroke: true)
                    drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + 10), size: 16, color: labelColor, stroke: false)
                }
            }
        } else {
            let p = toScreen(target.cx, target.cy)
            let labelColor = dark ? UIColor(hex: 0xF5F6F8) : UIColor(hex: 0x191C20)
            let isForeign = focusCountry.map { $0.name != "China" } ?? false
            let name = isForeign
                ? GeoMap.countryName(target.name, isZh: isZh)
                : GeoMap.displayName(target.name, isZh: isZh, level: "province")
            let count = provinceCounts()[target.name] ?? 0
            drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 10), size: 17, color: labelColor, stroke: true)
            drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + 18), size: 22, color: labelColor, stroke: false)
        }
    }

    private func cityCounts(_ province: GeoFeature) -> [String: Int] {
        var map: [String: Int] = [:]
        for p in points where p.region1 == province.name && !p.region2.isEmpty {
            map[p.region2, default: 0] += 1
        }
        return map
    }

    private func nearestFeatureAtCenter(s: Double, centerX: Double, centerY: Double) -> GeoFeature? {
        GeoMath.nearestFeature(geoData.china, wx: centerX, wy: centerY)
    }

    private func drawText(_ context: GraphicsContext, text: String, at point: CGPoint, size: Double, color: UIColor, stroke: Bool = false) {
        if stroke {
            let strokeColor = color == UIColor(hex: 0xF5F6F8) || color == UIColor(hex: 0x191C20)
                ? UIColor.white.withAlphaComponent(0.8)
                : UIColor.black.withAlphaComponent(0.3)
            let strokeResolved = context.resolve(Text(text)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Color(uiColor: strokeColor)))
            context.draw(strokeResolved, at: point, anchor: .center)
        }
        let resolved = context.resolve(Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Color(uiColor: color)))
        context.draw(resolved, at: point, anchor: .center)
    }
}
