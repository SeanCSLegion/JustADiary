import SwiftUI
import CoreGraphics

struct TravelStats {
    var provinces = Set<String>()
    var cities = Set<String>()
    var countries = Set<String>()
    var blocks = 0
    var days = Set<String>()
}

struct MapView: View {
    var openDiary: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var geoData = GeoDataSet()
    @State private var camera = GeoCamera()
    @State private var level = 1
    @State private var focusProvince: String?
    @State private var focusFeature: GeoFeature?
    @State private var points: [MapPoint] = []
    @State private var unlocated = 0
    @State private var yearFilter = "all"
    @State private var years: [String] = []
    @State private var stats = TravelStats()
    @State private var selectedPoint: MapPoint?
    @State private var loaded = false
    @State private var showLabels = false
    @State private var labelHideTask: Task<Void, Never>?
    @State private var lastMaxTimeUtc: Int64 = 0
    @State private var animating = false
    @State private var panVelocity: CGPoint = .zero
    @State private var lastPanTime: Date = .now
    @State private var panStartCenter: (lng: Double, lat: Double)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.str("map_title"))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
                Spacer()
                Text(L10n.fmt("map_summary", locatedCount, unlocated))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
            }
            .frame(height: 52)
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    yearChip(L10n.str("map_time_all"), value: "all")
                    ForEach(years, id: \.self) { year in
                        yearChip(year, value: year)
                    }
                }
                .padding(.horizontal, 16)
            }
            mapArea
                .padding(.horizontal, 16)
                .padding(.top, 10)
            statsCard
                .padding(.horizontal, 16)
                .padding(.top, 10)
            Spacer(minLength: 24)
        }
        .padding(.top, 12)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await reloadPoints() }
        }
    }

    private var locatedCount: Int {
        points.filter { $0.lat != 0 || $0.lng != 0 }.count
    }

    // MARK: - Data

    private func load() async {
        guard !loaded else { return }
        loaded = true
        geoData = GeoMap.loadGeoData()
        await reloadPoints()
    }

    private func reloadPoints() async {
        let rows = await DiaryRepository.shared.getAllMapPoints()
        let build = MapDataService.buildMapPoints(rows, precision: "exact")
        let filtered = yearFilter == "all" ? build.points : build.points.filter { $0.dayKey.hasPrefix(yearFilter) }
        points = filtered
        unlocated = build.unlocated
        var yearSet = Set<String>()
        for p in build.points {
            if p.dayKey.count >= 4 { yearSet.insert(String(p.dayKey.prefix(4))) }
        }
        years = yearSet.sorted(by: >)
        computeStats()
        let maxTime = rows.map { $0.startTimeUtc }.max() ?? 0
        let isFirst = lastMaxTimeUtc == 0
        if maxTime > lastMaxTimeUtc {
            lastMaxTimeUtc = maxTime
            if !isFirst, let newest = rows.first(where: { $0.startTimeUtc == maxTime }) {
                flyToPoint(lat: newest.latitude, lng: newest.longitude)
            } else {
                frameToFirstDiary(rows)
            }
        } else {
            frameToFirstDiary(rows)
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

    private func frameToFirstDiary(_ rows: [MapPointRow]) {
        let located = rows.filter { $0.latitude != 0 || $0.longitude != 0 }
        guard !located.isEmpty else {
            camera = GeoCamera()
            return
        }
        if let newest = located.max(by: { $0.startTimeUtc < $1.startTimeUtc }) {
            let country = newest.country
            let province = newest.region1
            if country == "中国" || country == "China", !province.isEmpty {
                if let feat = geoData.china.first(where: { $0.name == province }) {
                    focusProvince = province
                    focusFeature = feat
                    level = 2
                    flyTo(lng: feat.cx, lat: feat.cy, zoom: 5.5, isPixel: true)
                    return
                }
            }
            flyTo(lng: newest.longitude, lat: newest.latitude, zoom: 4.5)
        }
    }

    private func flyToPoint(lat: Double, lng: Double) {
        if lat == 0 && lng == 0 { return }
        flyTo(lng: lng, lat: lat, zoom: 4.5)
    }

    // MARK: - UI

    private func yearChip(_ label: String, value: String) -> some View {
        GlassChip(label: label, active: yearFilter == value) {
            yearFilter = value
            Task { await reloadPoints() }
        }
    }

    private var mapArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .glassEffect(tintedGlass(nil),
                             in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            GeoMapCanvas(geoData: geoData,
                         camera: camera,
                         level: level,
                         focusProvince: focusFeature,
                         points: points,
                         isZh: AppLanguage.isZh,
                         isDark: colorScheme == .dark,
                         selectedPoint: selectedPoint)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .gesture(mapGestures)
            VStack {
                HStack {
                    levelSelector
                    Spacer()
                    zoomBar
                }
                Spacer()
                if let point = selectedPoint {
                    infoCard(point)
                }
            }
            .padding(12)
        }
        .frame(height: mainScreenHeight() * 0.55)
    }

    private var mapGestures: some Gesture {
        ExclusiveGesture(
            MagnificationGesture()
                .onChanged { value in
                    handlePinch(value)
                }
                .onEnded { _ in
                    animating = false
                },
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    handlePanChanged(value)
                }
                .onEnded { value in
                    handlePanEnded(value)
                }
        )
        .simultaneously(with: SpatialTapGesture(count: 1).onEnded { value in
            handleMapTap(at: value.location)
        })
    }

    private func handlePinch(_ scale: CGFloat) {
        guard !animating else { return }
        let target = GeoMath.clampZoom(camera.zoom + log2(max(0.25, scale)))
        camera.zoom = target
    }

    private func mainScreenHeight() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? 852
    }

    private func handlePanChanged(_ value: DragGesture.Value) {
        guard !animating else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastPanTime)
        if dt > 0.001 {
            panVelocity = CGPoint(x: value.translation.width / CGFloat(dt) * 0.1,
                                  y: value.translation.height / CGFloat(dt) * 0.1)
            lastPanTime = now
        }
        let s = GeoMath.camScale(camera.zoom)
        camera.centerLng = GeoMath.xToLng(GeoMath.lngToX(camera.centerLng) - Double(value.translation.width) / s)
        camera.centerLat = GeoMath.yToLat(GeoMath.latToY(camera.centerLat) - Double(value.translation.height) / s)
    }

    private func handlePanEnded(_ value: DragGesture.Value) {
        guard !animating else { return }
        let velocity = panVelocity
        let velocityMagnitude = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        guard velocityMagnitude > 50 else { return }
        let s = GeoMath.camScale(camera.zoom)
        let targetLng = GeoMath.xToLng(GeoMath.lngToX(camera.centerLng) - Double(velocity.x) / s)
        let targetLat = GeoMath.yToLat(GeoMath.latToY(camera.centerLat) - Double(velocity.y) / s)
        let clampedLat = max(-85, min(85, targetLat))
        animateCamera(to: GeoCamera(centerLng: targetLng, centerLat: clampedLat, zoom: camera.zoom))
        panVelocity = .zero
    }

    private func handleMapTap(at location: CGPoint) {
        selectedPoint = nil
        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
        let mapRect = CGRect(x: 0, y: 0, width: screen.width - 32, height: screen.height * 0.55)
        let point = CGPoint(x: location.x, y: location.y)
        guard mapRect.contains(point) else { return }
        let world = GeoMath.screenToWorld(Double(point.x), Double(point.y), cam: camera,
                                          vpW: Double(mapRect.width), vpH: Double(mapRect.height))
        let s = GeoMath.camScale(camera.zoom)
        var best: MapPoint?
        var bestDist = 20.0
        for p in points {
            let projected = GeoMath.projectPoint(p.lat, p.lng)
            let dx = (projected.wx - world.wx) * s
            let dy = (projected.wy - world.wy) * s
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                best = p
            }
        }
        if let best {
            selectedPoint = best
        }
    }

    private func flyTo(lng: Double, lat: Double, zoom: Double, isPixel: Bool = false) {
        let target = GeoCamera(centerLng: isPixel ? GeoMath.xToLng(lng) : lng,
                               centerLat: isPixel ? GeoMath.yToLat(lat) : lat,
                               zoom: GeoMath.clampZoom(zoom))
        animateCamera(to: target)
    }

    private func animateCamera(to target: GeoCamera) {
        animating = true
        let from = camera
        let start = Date()
        let duration = 0.6
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            let t = min(1, Date().timeIntervalSince(start) / duration)
            let k = t * t * (3 - 2 * t)
            var lngDelta = target.centerLng - from.centerLng
            while lngDelta > 180 { lngDelta -= 360 }
            while lngDelta < -180 { lngDelta += 360 }
            camera.centerLng = from.centerLng + lngDelta * k
            camera.centerLat = from.centerLat + (target.centerLat - from.centerLat) * k
            camera.zoom = from.zoom + (target.zoom - from.zoom) * k
            if t >= 1 {
                timer.invalidate()
                animating = false
            }
        }
    }

    // MARK: - Level selector

    private var levelSelector: some View {
        VStack(spacing: 4) {
            levelButton(0, label: L10n.str("map_level_global"))
            levelButton(1, label: L10n.str("map_level_national"))
            levelButton(2, label: L10n.str("map_level_province"))
        }
        .padding(6)
        .background {
            GlassCapsule(cornerRadius: 20, blur: 22)
        }
    }

    private func levelButton(_ lvl: Int, label: String) -> some View {
        Button {
            Haptics.tap()
            switchLevel(lvl)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(level == lvl ? .white : Theme.onSurfaceVariant())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 46, height: 26)
                .background {
                    if level == lvl {
                        Capsule().fill(Theme.primary())
                            .glassEffect(tintedGlass(Theme.primary()), in: Capsule())
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func switchLevel(_ lvl: Int) {
        guard lvl != level else { return }
        Haptics.medium()
        level = lvl
        if lvl == 1, geoData.china.isEmpty == false {
            let bounds = MapDataService.fitBounds(points)
            if let b = bounds {
                let dx = max(GeoMath.lngToX(b.maxLng) - GeoMath.lngToX(b.minLng), 1)
                let dy = max(GeoMath.latToY(b.maxLat) - GeoMath.latToY(b.minLat), 1)
                let screen = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
                let vpW = screen.width - 32
                let vpH = screen.height * 0.55
                let zoom = min(log2(vpW * 0.8 / dx), log2(vpH * 0.8 / dy))
                flyTo(lng: (b.minLng + b.maxLng) / 2, lat: (b.minLat + b.maxLat) / 2,
                      zoom: min(zoom, 4.5))
            } else {
                flyTo(lng: 105, lat: 35, zoom: 3.6)
            }
        } else if lvl == 0 {
            flyTo(lng: 105, lat: 30, zoom: 1.5)
        } else if lvl == 2 {
            if let feat = focusFeature {
                flyTo(lng: feat.cx, lat: feat.cy, zoom: 5.5, isPixel: true)
            } else {
                flyTo(lng: 105, lat: 35, zoom: 5.5)
            }
        }
    }

    // MARK: - Zoom bar

    private var zoomBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Theme.onSurfaceVariant().opacity(0.4))
                    .frame(width: 5)
                Circle()
                    .fill(Theme.primary())
                    .frame(width: 24, height: 24)
                    .glassEffect(tintedGlass(Theme.primary()), in: Circle())
                    .overlay {
                        Circle().stroke(Color.white, lineWidth: 2)
                    }
                    .offset(y: zoomBarOffset(geo.size.height) - 12)
            }
            .frame(width: 36, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let range = zoomRange()
                        let pct = min(1, max(0, value.location.y / geo.size.height))
                        camera.zoom = GeoMath.clampZoom(range.min + pct * (range.max - range.min))
                    }
            )
        }
        .frame(width: 36)
    }

    private func zoomRange() -> (min: Double, max: Double) {
        switch level {
        case 0: return (1.0, 6)
        case 2: return (4, 16)
        default: return (2, 9)
        }
    }

    private func zoomBarOffset(_ height: CGFloat) -> CGFloat {
        let range = zoomRange()
        let pct = min(1, max(0, (camera.zoom - range.min) / (range.max - range.min)))
        return height * pct
    }

    // MARK: - Info card

    private func infoCard(_ point: MapPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.formatDayKey(point.dayKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
                Spacer()
                Button {
                    selectedPoint = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                .buttonStyle(.plain)
            }
            if !point.locText.isEmpty {
                Text(point.locText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
                    .lineLimit(1)
            }
            Text(point.summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.onSurface())
                .lineLimit(2)
            Button {
                openDiary(point.dayKey)
            } label: {
                Text(L10n.str("map_open_diary"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(Theme.primary())
                            .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .diaryGlassCard(cornerRadius: 16)
        .frame(maxWidth: 260)
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(L10n.str("map_stat_provinces"), "\(stats.provinces.count)")
            statCell(L10n.str("map_stat_cities"), "\(stats.cities.count)")
            statCell(L10n.str("map_stat_countries"), "\(stats.countries.count)")
            statCell(L10n.str("map_stat_blocks"), "\(stats.blocks)")
            statCell(L10n.str("map_stat_days"), "\(stats.days.count)")
        }
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(tintedGlass(nil), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.onSurface())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.onSurfaceVariant())
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeoMapCanvas: View {
    var geoData: GeoDataSet
    var camera: GeoCamera
    var level: Int
    var focusProvince: GeoFeature?
    var points: [MapPoint]
    var isZh: Bool
    var isDark: Bool
    var selectedPoint: MapPoint?

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
                drawChina(context, dark: dark, s: s, centerX: centerX, centerY: centerY, vpW: vpW, vpH: vpH, isVisible: isVisible, toScreen: toScreen)
            } else {
                drawProvince(context, dark: dark, s: s, centerX: centerX, centerY: centerY, vpW: vpW, vpH: vpH, isVisible: isVisible, toScreen: toScreen)
            }
            drawPoints(context, dark: dark, s: s, centerX: centerX, centerY: centerY, vpW: vpW, vpH: vpH)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Level 0

    private func drawWorld(_ context: GraphicsContext, isZh: Bool, dark: Bool,
                           s: Double, centerX: Double, centerY: Double, vpW: Double, vpH: Double) {
        let land = dark ? UIColor(hex: 0x2A2F38) : UIColor(hex: 0xEFECE3)
        let borderColor = dark ? UIColor(hex: 0x3D4350) : UIColor(hex: 0xC8C4BC)
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
            context.fill(path, with: .color(Color(uiColor: land)))
            context.stroke(path, with: .color(Color(uiColor: borderColor)), lineWidth: 0.5)
        }
        let labelColor = dark ? UIColor(hex: 0x9AA3B2) : UIColor(hex: 0x667085)
        let counted = countriesWithCounts()
        for f in geoData.world where counted[f.name] != nil {
            let p = CGPoint(x: (f.cx - centerX) * s + vpW / 2, y: (f.cy - centerY) * s + vpH / 2)
            guard p.x > -20, p.x < vpW + 20, p.y > -20, p.y < vpH + 20 else { continue }
            let name = GeoMap.countryName(f.name, isZh: isZh)
            let count = counted[f.name] ?? 0
            drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 8), size: 13, color: labelColor, stroke: true)
            drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + 12), size: 17, color: labelColor, stroke: false)
        }
    }

    private func countriesWithCounts() -> [String: Int] {
        var map: [String: Int] = [:]
        for p in points where !p.country.isEmpty {
            map[p.country, default: 0] += 1
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
                    let fontSize = s < 32 ? 12.0 : (s < 64 ? 14.0 : 16.0)
                    let countSize = s < 32 ? 13.0 : (s < 64 ? 17.0 : 21.0)
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
                context.fill(cpath, with: .color(heatColor(count: count, maxCount: maxCount, dark: dark, fallback: land)))
                if count > 0 {
                    let p = toScreen(f.cx, f.cy)
                    let labelColor = dark ? UIColor(hex: 0xF5F6F8) : UIColor(hex: 0x191C20)
                    let name = GeoMap.displayName(f.name, isZh: isZh, level: "city")
                    drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 8), size: 12, color: labelColor, stroke: true)
                    drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + 10), size: 15, color: labelColor, stroke: false)
                }
            }
        } else {
            let p = toScreen(target.cx, target.cy)
            let labelColor = dark ? UIColor(hex: 0xF5F6F8) : UIColor(hex: 0x191C20)
            let name = GeoMap.displayName(target.name, isZh: isZh, level: "province")
            let count = provinceCounts()[target.name] ?? 0
            drawText(context, text: name, at: CGPoint(x: p.x, y: p.y - 10), size: 16, color: labelColor, stroke: true)
            drawText(context, text: "\(count)", at: CGPoint(x: p.x, y: p.y + 18), size: 21, color: labelColor, stroke: false)
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

    // MARK: - Points

    private func drawPoints(_ context: GraphicsContext, dark: Bool, s: Double, centerX: Double, centerY: Double,
                            vpW: Double, vpH: Double) {
        let dotRadius = min(6.0, max(3.0, 4.0 * log2(s + 1) / 4))
        let isSelectedRadius = dotRadius * 2
        for p in points {
            let pt = GeoMath.projectPoint(p.lat, p.lng)
            let screen = CGPoint(x: (pt.wx - centerX) * s + vpW / 2, y: (pt.wy - centerY) * s + vpH / 2)
            guard screen.x > -10, screen.x < vpW + 10, screen.y > -10, screen.y < vpH + 10 else { continue }
            let isSelected = selectedPoint?.id == p.id
            if isSelected {
                context.fill(Path(ellipseIn: CGRect(x: screen.x - isSelectedRadius, y: screen.y - isSelectedRadius,
                                                     width: isSelectedRadius * 2, height: isSelectedRadius * 2)),
                             with: .color(Theme.glowColor()))
            }
            context.fill(Path(ellipseIn: CGRect(x: screen.x - dotRadius, y: screen.y - dotRadius,
                                                 width: dotRadius * 2, height: dotRadius * 2)),
                         with: .color(Theme.primary()))
            context.stroke(Path(ellipseIn: CGRect(x: screen.x - dotRadius, y: screen.y - dotRadius,
                                                   width: dotRadius * 2, height: dotRadius * 2)),
                           with: .color(.white), lineWidth: 1.5)
        }
    }

    private func drawText(_ context: GraphicsContext, text: String, at point: CGPoint, size: Double, color: UIColor, stroke: Bool = false) {
        if stroke {
            let strokeColor = color == UIColor(hex: 0xF5F6F8) || color == UIColor(hex: 0x191C20)
                ? UIColor.white.withAlphaComponent(0.8)
                : UIColor.black.withAlphaComponent(0.3)
            let strokeResolved = context.resolve(Text(text)
                .font(.system(size: size))
                .foregroundStyle(Color(uiColor: strokeColor)))
            context.draw(strokeResolved, at: point, anchor: .center)
        }
        let resolved = context.resolve(Text(text)
            .font(.system(size: size))
            .foregroundStyle(Color(uiColor: color)))
        context.draw(resolved, at: point, anchor: .center)
    }
}
