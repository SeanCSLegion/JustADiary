import Foundation
import Observation
import SwiftUI

struct CameraAnimation {
    var from: GeoCamera
    var to: GeoCamera
    var start: Date
    var duration: Double
}

@Observable
final class MapViewModel {
    var geoData = GeoDataSet()
    var camera = GeoCamera()
    var level = 1
    var focusProvince: String?
    var focusFeature: GeoFeature?
    var focusCountry: GeoFeature?
    var levelExpanded = false
    var points: [MapPoint] = []
    var unlocated = 0
    var yearFilter = "all"
    var timeKind: TimeRangeKind = .all
    var customFrom: Date?
    var customTo: Date?
    var years: [String] = []
    var stats = TravelStats()
    var cameraAnimation: CameraAnimation?
    var isAnimating: Bool { cameraAnimation != nil }

    private var loaded = false
    private var lastMaxTimeUtc: Int64 = 0
    private var animationToken = 0

    var locatedCount: Int {
        points.filter { $0.lat != 0 || $0.lng != 0 }.count
    }

    var timeRangeLabel: String {
        if timeKind == .custom, let from = customFrom, let to = customTo {
            return L10n.dateRange(from, to)
        }
        return L10n.str("map_time_custom")
    }

    func applyTimeKind(_ kind: TimeRangeKind) {
        timeKind = kind
        if kind != .custom {
            customFrom = nil
            customTo = nil
        }
    }

    func clearTimeFilter() {
        timeKind = .all
        customFrom = nil
        customTo = nil
    }

    func applyCustomTime() {
        timeKind = .custom
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        geoData = await GeoMap.loadGeoDataAsync()
        await reloadPoints()
    }

    func reloadPoints() async {
        let rows = await DiaryRepository.shared.getAllMapPoints()
        let build = MapDataService.buildMapPoints(rows)
        var filtered = yearFilter == "all" ? build.points : build.points.filter { $0.dayKey.hasPrefix(yearFilter) }
        if timeKind != .all {
            let range = timeKind.dayKeyRange(customFrom: customFrom, customTo: customTo)
            filtered = filtered.filter { $0.dayKey >= range.0 && $0.dayKey <= range.1 }
        }
        points = filtered
        unlocated = build.unlocated
        var yearSet = Set<String>()
        for p in build.points {
            if p.dayKey.count >= 4 {
                yearSet.insert(String(p.dayKey.prefix(4)))
            }
        }
        years = yearSet.sorted(by: >)
        computeStats()
        let maxTime = rows.map { $0.startTimeUtc }.max() ?? 0
        let isFirst = lastMaxTimeUtc == 0
        let animated = !isFirst
        if maxTime > lastMaxTimeUtc {
            lastMaxTimeUtc = maxTime
            if !isFirst, let newest = rows.first(where: { $0.startTimeUtc == maxTime }) {
                flyToPoint(lat: newest.latitude, lng: newest.longitude)
            } else {
                frameToFirstDiary(rows, animated: animated)
            }
        } else {
            frameToFirstDiary(rows, animated: animated)
        }
    }

    private func computeStats() {
        var s = TravelStats()
        for p in points {
            if !p.country.isEmpty { s.countries.insert(p.country) }
            if !p.region1.isEmpty { s.provinces.insert(p.country + p.region1) }
            if !p.region2.isEmpty { s.cities.insert(p.country + p.region1 + p.region2) }
            s.blocks += 1
            s.days.insert(p.dayKey)
        }
        stats = s
    }

    private func frameToFirstDiary(_ rows: [MapPointRow], animated: Bool) {
        let located = rows.filter { $0.latitude != 0 || $0.longitude != 0 }
        guard !located.isEmpty else {
            frameChinaOrFallback(animated: animated)
            return
        }
        level = 1
        focusCountry = nil
        focusProvince = nil
        focusFeature = nil
        if let newest = located.max(by: { $0.startTimeUtc < $1.startTimeUtc }),
           isInChina(lat: newest.latitude, lng: newest.longitude) {
            flyTo(lng: newest.longitude, lat: newest.latitude,
                  zoom: zoomRange().min + 0.8, animated: animated)
        } else {
            frameChinaOrFallback(animated: animated)
        }
    }

    private func frameChinaOrFallback(animated: Bool) {
        if let china = chinaFallback() {
            flyToFeatureBounds(china, animated: animated)
        } else {
            flyTo(lng: 104, lat: 35, zoom: zoomRange().min + 0.3, animated: animated)
        }
    }

    private func isInChina(lat: Double, lng: Double) -> Bool {
        guard let b = chinaFallback() else { return true }
        let x = GeoMath.lngToX(lng)
        let y = GeoMath.latToY(lat)
        return x >= b.minX && x <= b.maxX && y >= b.minY && y <= b.maxY
    }

    private func flyToPoint(lat: Double, lng: Double) {
        if lat == 0 && lng == 0 { return }
        guard isInChina(lat: lat, lng: lng) else { return }
        flyTo(lng: lng, lat: lat, zoom: 4.5)
    }

    // MARK: - Gestures

    func pinch(by scale: CGFloat) {
        guard !isAnimating else { return }
        let range = zoomRange()
        let target = camera.zoom + log2(max(0.25, scale))
        camera.zoom = min(max(target, range.min), range.max)
    }

    func pan(by dx: CGFloat, dy: CGFloat) {
        guard !isAnimating else { return }
        let s = GeoMath.camScale(camera.zoom)
        camera.centerLng = GeoMath.xToLng(GeoMath.lngToX(camera.centerLng) - Double(dx) * 0.7 / s)
        camera.centerLat = GeoMath.yToLat(GeoMath.latToY(camera.centerLat) - Double(dy) * 0.7 / s)
    }

    func panDecelerate(velocity: CGPoint) {
        guard !isAnimating else { return }
        let magnitude = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        guard magnitude > 250 else { return }
        let s = GeoMath.camScale(camera.zoom)
        let decay: CGFloat = 0.21
        var dx = velocity.x * decay / CGFloat(s)
        var dy = velocity.y * decay / CGFloat(s)
        let maxDelta = Double(Screen.width) * 1.2 / s
        let mag = hypot(dx, dy)
        if mag > maxDelta {
            dx = CGFloat(maxDelta) * dx / mag
            dy = CGFloat(maxDelta) * dy / mag
        }
        let targetLng = GeoMath.xToLng(GeoMath.lngToX(camera.centerLng) - Double(dx))
        let targetLat = GeoMath.yToLat(GeoMath.latToY(camera.centerLat) - Double(dy))
        flyTo(lng: targetLng, lat: max(-85, min(85, targetLat)), zoom: camera.zoom)
    }

    func zoomBarSet(pct: CGFloat) {
        let range = zoomRange()
        if cameraAnimation != nil {
            animationToken += 1
            cameraAnimation = nil
        }
        camera.zoom = min(max(range.max - Double(pct) * (range.max - range.min), range.min), range.max)
    }

    func tap(at point: CGPoint, viewport: CGSize) {
        guard !isAnimating else { return }
        let world = GeoMath.screenToWorld(Double(point.x), Double(point.y), cam: camera,
                                          vpW: Double(viewport.width), vpH: Double(viewport.height))
        let s = GeoMath.camScale(camera.zoom)
        drillDown(at: world, scale: s)
    }

    // MARK: - Drill-down

    private func drillDown(at world: GeoXY, scale s: Double) {
        let tolerance = 12.0 / s
        switch level {
        case 0:
            if let country = hitFeature(geoData.world, at: world, tolerance: tolerance) {
                Haptics.medium()
                focusCountry = country
                focusFeature = country
                level = 1
                flyToFeatureBounds(country)
            }
        case 1:
            if let province = hitFeature(geoData.china, at: world, tolerance: tolerance) {
                Haptics.medium()
                focusCountry = nil
                focusFeature = province
                level = 2
                loadCityDataIfNeeded(province)
                flyToFeatureBounds(province)
            }
        default:
            break
        }
    }

    private func hitFeature(_ list: [GeoFeature], at world: GeoXY, tolerance: Double) -> GeoFeature? {
        for f in list where GeoMath.pointInFeature(world.wx, world.wy, f) {
            return f
        }
        var best: GeoFeature?
        var bestD = tolerance * tolerance
        for f in list {
            let dx = f.cx - world.wx
            let dy = f.cy - world.wy
            let d = dx * dx + dy * dy
            if d < bestD {
                bestD = d
                best = f
            }
        }
        return best
    }

    // MARK: - Camera

    func flyToFeatureBounds(_ f: GeoFeature, animated: Bool = true) {
        flyTo(lng: GeoMath.xToLng((f.minX + f.maxX) / 2),
              lat: GeoMath.yToLat((f.minY + f.maxY) / 2),
              zoom: fitZoom(of: f),
              animated: animated)
    }

    func fitZoom(of f: GeoFeature) -> Double {
        let vpW = Screen.width - 32
        let vpH = Screen.height * 0.55
        return min(log2(vpW * 0.75 / max(f.maxX - f.minX, 1)),
                   log2(vpH * 0.75 / max(f.maxY - f.minY, 1)))
    }

    func chinaFallback() -> GeoFeature? {
        guard let first = geoData.china.first else { return nil }
        var minX = first.minX, maxX = first.maxX, minY = first.minY, maxY = first.maxY
        for f in geoData.china.dropFirst() {
            minX = min(minX, f.minX); maxX = max(maxX, f.maxX)
            minY = min(minY, f.minY); maxY = max(maxY, f.maxY)
        }
        return GeoFeature(name: "", adcode: "", level: "", rings: [],
                          minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                          cx: (minX + maxX) / 2, cy: (minY + maxY) / 2)
    }

    func loadCityDataIfNeeded(_ feature: GeoFeature?) {
        guard let feature, !feature.adcode.isEmpty else { return }
        if geoData.cities[feature.adcode] == nil {
            _ = GeoMap.loadCityData(&geoData, provinceAdcode: feature.adcode)
        }
    }

    func flyTo(lng: Double, lat: Double, zoom: Double, animated: Bool = true) {
        let range = zoomRange()
        let z = min(max(zoom, range.min), range.max)
        let target = GeoCamera(centerLng: lng, centerLat: lat, zoom: z)
        if animated {
            animateCamera(to: target)
        } else {
            animationToken += 1
            camera = target
            cameraAnimation = nil
        }
    }

    func animateCamera(to target: GeoCamera) {
        animationToken += 1
        let token = animationToken
        let from = camera
        let s = GeoMath.camScale(camera.zoom)
        let distPts = hypot(GeoMath.lngToX(target.centerLng) - GeoMath.lngToX(from.centerLng),
                            GeoMath.latToY(target.centerLat) - GeoMath.latToY(from.centerLat)) * s
        let duration = min(0.7, max(0.2, distPts / Screen.width * 0.6))
        cameraAnimation = CameraAnimation(from: from, to: target, start: Date(), duration: duration)
        Task {
            try? await Task.sleep(for: .seconds(duration))
            guard token == animationToken else { return }
            camera = target
            cameraAnimation = nil
        }
    }

    func interpolatedCamera(at date: Date) -> GeoCamera {
        guard let anim = cameraAnimation else { return camera }
        let t = min(1, date.timeIntervalSince(anim.start) / max(0.01, anim.duration))
        let k = t * t * (3 - 2 * t)
        var lngDelta = anim.to.centerLng - anim.from.centerLng
        while lngDelta > 180 { lngDelta -= 360 }
        while lngDelta < -180 { lngDelta += 360 }
        return GeoCamera(centerLng: anim.from.centerLng + lngDelta * k,
                         centerLat: anim.from.centerLat + (anim.to.centerLat - anim.from.centerLat) * k,
                         zoom: anim.from.zoom + (anim.to.zoom - anim.from.zoom) * k)
    }

    func stopCameraAnimation() {
        guard let anim = cameraAnimation else { return }
        camera = anim.to
        cameraAnimation = nil
    }

    // MARK: - Levels

    func switchLevel(_ lvl: Int) {
        guard lvl != level else { return }
        Haptics.medium()
        level = lvl
        if lvl == 1, !geoData.china.isEmpty {
            let chinaPoints = points.filter { isInChina(lat: $0.lat, lng: $0.lng) }
            let bounds = MapDataService.fitBounds(chinaPoints)
            if let b = bounds {
                let dx = max(GeoMath.lngToX(b.maxLng) - GeoMath.lngToX(b.minLng), 1)
                let dy = max(GeoMath.latToY(b.minLat) - GeoMath.latToY(b.maxLat), 1)
                let vpW = Screen.width - 32
                let vpH = Screen.height * 0.55
                let zoom = min(log2(vpW * 0.75 / dx), log2(vpH * 0.75 / dy))
                flyTo(lng: (b.minLng + b.maxLng) / 2, lat: (b.minLat + b.maxLat) / 2, zoom: zoom)
            } else {
                frameChinaOrFallback(animated: true)
            }
        } else if lvl == 0 {
            focusCountry = nil
            flyTo(lng: 105, lat: 30, zoom: zoomRange().min + 0.3)
        } else if lvl == 2 {
            if let feat = focusFeature {
                loadCityDataIfNeeded(feat)
                flyToFeatureBounds(feat)
            } else {
                let target = GeoMath.nearestFeature(geoData.china,
                                                    wx: GeoMath.lngToX(105),
                                                    wy: GeoMath.latToY(35))
                loadCityDataIfNeeded(target)
                flyTo(lng: 105, lat: 35, zoom: 6.0)
            }
        }
    }

    func zoomRange() -> (min: Double, max: Double) {
        let fit: Double
        switch level {
        case 0:
            fit = min(log2((Screen.width - 32) * 0.75 / 256),
                      log2(Screen.height * 0.55 * 0.75 / 256))
        case 1:
            if let c = focusCountry {
                fit = fitZoom(of: c)
            } else if let f = chinaFallback() {
                fit = fitZoom(of: f)
            } else {
                fit = 2.5
            }
        default:
            if let f = focusFeature {
                fit = fitZoom(of: f)
            } else if let f = chinaFallback() {
                fit = fitZoom(of: f)
            } else {
                fit = 5.0
            }
        }
        let minZ = max(0.5, fit - 0.35)
        return (minZ, minZ + 2.0)
    }

    func zoomBarOffset(_ height: CGFloat) -> CGFloat {
        let range = zoomRange()
        let pct = min(1, max(0, (camera.zoom - range.min) / (range.max - range.min)))
        return height * (1 - pct)
    }
}

extension GeoMap {
    static func loadGeoDataAsync() async -> GeoDataSet {
        await Task.detached(priority: .userInitiated) {
            loadGeoData()
        }.value
    }
}
