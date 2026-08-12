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
    @State private var focusCountry: GeoFeature?
    @State private var levelExpanded = false
    @State private var points: [MapPoint] = []
    @State private var unlocated = 0
    @State private var yearFilter = "all"
    @State private var months: [String] = []
    @State private var monthFilter = "all"
    @State private var years: [String] = []
    @State private var stats = TravelStats()
    @State private var loaded = false
    @State private var showLabels = false
    @State private var labelHideTask: Task<Void, Never>?
    @State private var lastMaxTimeUtc: Int64 = 0
    @State private var animating = false
    @State private var panVelocity: CGPoint = .zero
    @State private var lastPanTime: Date = .now
    @State private var lastPanTranslation: CGSize = .zero
    @State private var showTimeFilter = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L10n.str("map_title")) {
                Text(L10n.fmt("map_summary", locatedCount, unlocated))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onSurfaceVariant())
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    yearChip(L10n.str("map_time_all"), value: "all")
                    ForEach(years, id: \.self) { year in
                        yearChip(year, value: year)
                    }
                    Button {
                        showTimeFilter = true
                    } label: {
                        Text(L10n.str("map_time_custom"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.primary())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
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
        .sheet(isPresented: $showTimeFilter) {
            timeFilterSheet
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
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
        var filtered = yearFilter == "all" ? build.points : build.points.filter { $0.dayKey.hasPrefix(yearFilter) }
        if monthFilter != "all", let monthInt = Int(monthFilter) {
            filtered = filtered.filter {
                guard $0.dayKey.count >= 6 else { return false }
                let month = String($0.dayKey.dropFirst(4).prefix(2))
                return Int(month) == monthInt
            }
        }
        points = filtered
        unlocated = build.unlocated
        var yearSet = Set<String>()
        var monthSet = Set<String>()
        for p in build.points {
            if p.dayKey.count >= 4 {
                let y = String(p.dayKey.prefix(4))
                yearSet.insert(y)
            }
            if p.dayKey.count >= 6 {
                let start = p.dayKey.index(p.dayKey.startIndex, offsetBy: 4, limitedBy: p.dayKey.endIndex) ?? p.dayKey.endIndex
                let end = p.dayKey.index(p.dayKey.startIndex, offsetBy: 6, limitedBy: p.dayKey.endIndex) ?? p.dayKey.endIndex
                if start < end && end <= p.dayKey.endIndex {
                    monthSet.insert(String(p.dayKey[start..<end]))
                }
            }
        }
        years = yearSet.sorted(by: >)
        months = monthSet.sorted()
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
            flyTo(lng: 104, lat: 35, zoom: zoomRange().min + 0.3)
            return
        }
        if let newest = located.max(by: { $0.startTimeUtc < $1.startTimeUtc }) {
            let country = newest.country
            let province = newest.region1
            if country == "中国" || country == "China", !province.isEmpty {
                if let feat = geoData.china.first(where: { $0.name == province }) {
                    focusCountry = nil
                    focusProvince = province
                    focusFeature = feat
                    level = 2
                    loadCityDataIfNeeded(feat)
                    flyToFeatureBounds(feat)
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
            monthFilter = "all"
            Task { await reloadPoints() }
        }
    }

    private var mapArea: some View {
        ZStack {
            GlassCapsule(cornerRadius: 26)
            GeoMapCanvas(geoData: geoData,
                         camera: camera,
                         level: level,
                         focusProvince: focusFeature,
                         focusCountry: focusCountry,
                         points: points,
                         isZh: AppLanguage.isZh,
                         isDark: colorScheme == .dark)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .highPriorityGesture(mapGestures)
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    levelSelector
                    Spacer()
                    zoomBar
                }
            }
            .padding(12)
        }
        .frame(height: Screen.height * 0.55)
    }

    private var mapGestures: some Gesture {
        let pinch = MagnificationGesture()
            .onChanged { value in
                handlePinch(value)
            }
            .onEnded { _ in
                animating = false
            }
        let drag = DragGesture(minimumDistance: 5)
            .onChanged { value in
                handlePanChanged(value)
            }
            .onEnded { value in
                handlePanEnded(value)
            }
        let tap = SpatialTapGesture(count: 1)
            .onEnded { value in
                handleMapTap(at: value.location)
            }
        return drag.simultaneously(with: pinch).simultaneously(with: tap)
    }

    private func handlePinch(_ scale: CGFloat) {
        guard !animating else { return }
        let range = zoomRange()
        let target = camera.zoom + log2(max(0.25, scale))
        camera.zoom = min(max(target, range.min), range.max)
    }

    private static let panSensitivity: CGFloat = 0.7

    private func handlePanChanged(_ value: DragGesture.Value) {
        guard !animating else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastPanTime)
        let dx = value.translation.width - lastPanTranslation.width
        let dy = value.translation.height - lastPanTranslation.height
        lastPanTranslation = value.translation
        if dt > 0.001 {
            let instant = CGPoint(x: dx / CGFloat(dt), y: dy / CGFloat(dt))
            let alpha = 0.35
            panVelocity = CGPoint(x: panVelocity.x * (1 - alpha) + instant.x * alpha,
                                  y: panVelocity.y * (1 - alpha) + instant.y * alpha)
            lastPanTime = now
        }
        let s = GeoMath.camScale(camera.zoom)
        camera.centerLng = GeoMath.xToLng(GeoMath.lngToX(camera.centerLng) - Double(dx) * Double(Self.panSensitivity) / s)
        camera.centerLat = GeoMath.yToLat(GeoMath.latToY(camera.centerLat) - Double(dy) * Double(Self.panSensitivity) / s)
    }

    private func handlePanEnded(_ value: DragGesture.Value) {
        guard !animating else { return }
        let velocity = panVelocity
        panVelocity = .zero
        lastPanTranslation = .zero
        let velocityMagnitude = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        guard velocityMagnitude > 250 else { return }
        let s = GeoMath.camScale(camera.zoom)
        let decay: CGFloat = 0.3 * Self.panSensitivity
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
        let clampedLat = max(-85, min(85, targetLat))
        animateCamera(to: GeoCamera(centerLng: targetLng, centerLat: clampedLat, zoom: camera.zoom))
    }

    private func handleMapTap(at location: CGPoint) {
        let mapRect = CGRect(x: 0, y: 0, width: Screen.width - 32, height: Screen.height * 0.55)
        let point = CGPoint(x: location.x, y: location.y)
        guard mapRect.contains(point) else { return }
        let world = GeoMath.screenToWorld(Double(point.x), Double(point.y), cam: camera,
                                          vpW: Double(mapRect.width), vpH: Double(mapRect.height))
        let s = GeoMath.camScale(camera.zoom)
        guard !animating else { return }
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

    private func flyToFeatureBounds(_ f: GeoFeature) {
        flyTo(lng: GeoMath.xToLng((f.minX + f.maxX) / 2),
              lat: GeoMath.yToLat((f.minY + f.maxY) / 2),
              zoom: fitZoom(of: f))
    }

    private func fitZoom(of f: GeoFeature) -> Double {
        let vpW = Screen.width - 32
        let vpH = Screen.height * 0.55
        return min(log2(vpW * 0.75 / max(f.maxX - f.minX, 1)),
                   log2(vpH * 0.75 / max(f.maxY - f.minY, 1)))
    }

    private func chinaFallback() -> GeoFeature? {
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

    private func loadCityDataIfNeeded(_ feature: GeoFeature?) {
        guard let feature, !feature.adcode.isEmpty else { return }
        if geoData.cities[feature.adcode] == nil {
            _ = GeoMap.loadCityData(&geoData, provinceAdcode: feature.adcode)
        }
    }

    private func flyTo(lng: Double, lat: Double, zoom: Double, isPixel: Bool = false) {
        let range = zoomRange()
        let z = min(max(zoom, range.min), range.max)
        let target = GeoCamera(centerLng: isPixel ? GeoMath.xToLng(lng) : lng,
                               centerLat: isPixel ? GeoMath.yToLat(lat) : lat,
                               zoom: z)
        animateCamera(to: target)
    }

    private func animateCamera(to target: GeoCamera) {
        animating = true
        let from = camera
        let start = Date()
        let s = GeoMath.camScale(camera.zoom)
        let distPts = hypot(GeoMath.lngToX(target.centerLng) - GeoMath.lngToX(from.centerLng),
                            GeoMath.latToY(target.centerLat) - GeoMath.latToY(from.centerLat)) * s
        let duration = min(0.7, max(0.2, distPts / Screen.width * 0.6))
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
        Group {
            if levelExpanded {
                expandedLevelSelector
                    .transition(.scale(scale: 0.55, anchor: .bottomLeading).combined(with: .opacity))
            } else {
                collapsedLevelSelector
                    .transition(.scale(scale: 0.55, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .task(id: levelExpanded) {
            guard levelExpanded else { return }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                levelExpanded = false
            }
        }
    }

    private func levelIcon(_ lvl: Int) -> String {
        switch lvl {
        case 0: return "globe"
        case 2: return "mappin.circle.fill"
        default: return "map"
        }
    }

    private var collapsedLevelSelector: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                levelExpanded = true
            }
        } label: {
            Image(systemName: levelIcon(level))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Capsule()
                        .fill(Theme.primary())
                        .glassEffect(tintedGlass(Theme.primary()), in: Capsule())
                        .shadow(color: Theme.glowColor(), radius: 8, y: 2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var expandedLevelSelector: some View {
        VStack(spacing: 6) {
            levelButton(0, icon: "globe", label: L10n.str("map_level_global"))
            levelButton(1, icon: "map", label: L10n.str("map_level_national"))
            levelButton(2, icon: "mappin.circle.fill", label: L10n.str("map_level_province"))
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .glassEffect(tintedGlass(nil, interactive: true),
                             in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .shadow(color: Theme.shadowColor(), radius: 12, y: 4)
    }

    private func levelButton(_ lvl: Int, icon: String, label: String) -> some View {
        Button {
            Haptics.tap()
            switchLevel(lvl)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                levelExpanded = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(level == lvl ? .white : Theme.onSurfaceVariant())
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if level == lvl {
                    Capsule().fill(Theme.primary())
                        .glassEffect(tintedGlass(Theme.primary()), in: Capsule())
                }
            }
            .contentShape(Capsule())
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
                let vpW = Screen.width - 32
                let vpH = Screen.height * 0.55
                let zoom = min(log2(vpW * 0.75 / dx), log2(vpH * 0.75 / dy))
                flyTo(lng: (b.minLng + b.maxLng) / 2, lat: (b.minLat + b.maxLat) / 2, zoom: zoom)
            } else {
                flyTo(lng: 105, lat: 35, zoom: 3.6)
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

    // MARK: - Zoom bar

    private var zoomBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Theme.onSurfaceVariant().opacity(0.4))
                    .frame(width: 5)
                Circle()
                    .fill(Theme.primary())
                    .frame(width: 28, height: 28)
                    .glassEffect(tintedGlass(Theme.primary()), in: Circle())
                    .overlay {
                        Circle().stroke(Color.white, lineWidth: 2)
                    }
                    .offset(y: zoomBarOffset(geo.size.height) - 14)
            }
            .frame(width: 40, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let range = zoomRange()
                        let pct = min(1, max(0, value.location.y / geo.size.height))
                        camera.zoom = GeoMath.clampZoom(range.max - pct * (range.max - range.min))
                    }
            )
        }
        .frame(width: 40, height: 170)
    }

    private func zoomRange() -> (min: Double, max: Double) {
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

    private func zoomBarOffset(_ height: CGFloat) -> CGFloat {
        let range = zoomRange()
        let pct = min(1, max(0, (camera.zoom - range.min) / (range.max - range.min)))
        return height * (1 - pct)
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
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(tintedGlass(nil), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.onSurface())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.onSurfaceVariant())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Time filter sheet

    private var timeFilterSheet: some View {
        VStack(spacing: 16) {
            GlassSheetHeader(title: L10n.str("map_time_filter")) {
                showTimeFilter = false
            }
            if !months.isEmpty {
                Text(L10n.str("map_time_month"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onSurfaceVariant())
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    monthChip(L10n.str("map_time_all"), value: "all")
                    ForEach(months, id: \.self) { m in
                        monthChip("\(m)", value: m)
                    }
                }
            }
            HStack(spacing: 12) {
                GlassSecondaryButton(title: L10n.str("map_time_clear"), fullWidth: true) {
                    monthFilter = "all"
                    showTimeFilter = false
                    Task { await reloadPoints() }
                }
                GlassPrimaryButton(title: L10n.str("map_time_apply"), fullWidth: true) {
                    showTimeFilter = false
                    Task { await reloadPoints() }
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .padding(.bottom, 8)
    }

    private func monthChip(_ label: String, value: String) -> some View {
        Button {
            monthFilter = value
        } label: {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(monthFilter == value ? .white : Theme.onSurface())
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if monthFilter == value {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.primary())
                            .glassEffect(tintedGlass(Theme.primary()), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.glassDim())
                            .glassEffect(tintedGlass(nil), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

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
