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

    @State private var vm = MapViewModel()
    @State private var showTimeFilter = false
    @State private var panVelocity: CGPoint = .zero
    @State private var lastPanTime: Date = .now
    @State private var lastPanTranslation: CGSize = .zero
    @State private var suppressTapUntil: Date = .distantPast
    @State private var viewportSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L10n.str("map_title")) {
                Text(L10n.fmt("map_summary", vm.locatedCount, vm.unlocated))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onSurfaceVariant())
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    yearChip(L10n.str("map_time_all"), value: "all")
                    ForEach(vm.years, id: \.self) { year in
                        yearChip(year, value: year)
                    }
                    GlassActionChip(label: vm.timeRangeLabel, systemImage: "calendar",
                                    active: vm.timeKind == .custom) {
                        Haptics.tap()
                        showTimeFilter = true
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
        .task { await vm.load() }
        .onDisappear { vm.stopCameraAnimation() }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await vm.reloadPoints() }
        }
        .sheet(isPresented: $showTimeFilter) {
            timeFilterSheet
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Filter chips

    private func yearChip(_ label: String, value: String) -> some View {
        GlassChip(label: label, active: vm.timeKind == .all && vm.yearFilter == value) {
            vm.yearFilter = value
            vm.applyTimeKind(.all)
            Task { await vm.reloadPoints() }
        }
    }

    // MARK: - Map area

    private var mapArea: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                GlassCapsule(cornerRadius: 26)
                mapCanvas(size: size)
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
            .onAppear {
                viewportSize = size
            }
            .onChange(of: size) { _, newSize in
                viewportSize = newSize
            }
        }
        .frame(height: Screen.height * 0.55)
    }

    @ViewBuilder
    private func mapCanvas(size: CGSize) -> some View {
        if vm.cameraAnimation != nil {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let animatedCamera = vm.interpolatedCamera(at: context.date)
                GeoMapCanvas(geoData: vm.geoData,
                             camera: animatedCamera,
                             level: vm.level,
                             focusProvince: vm.focusFeature,
                             focusCountry: vm.focusCountry,
                             points: vm.points,
                             isZh: AppLanguage.isZh,
                             isDark: colorScheme == .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .highPriorityGesture(mapGestures)
                    .accessibilityLabel(L10n.str("map_title"))
                    .accessibilityValue(L10n.fmt("map_summary", vm.locatedCount, vm.unlocated))
            }
        } else {
            GeoMapCanvas(geoData: vm.geoData,
                         camera: vm.camera,
                         level: vm.level,
                         focusProvince: vm.focusFeature,
                         focusCountry: vm.focusCountry,
                         points: vm.points,
                         isZh: AppLanguage.isZh,
                         isDark: colorScheme == .dark)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .highPriorityGesture(mapGestures)
                .accessibilityLabel(L10n.str("map_title"))
                .accessibilityValue(L10n.fmt("map_summary", vm.locatedCount, vm.unlocated))
        }
    }

    private var mapGestures: some Gesture {
        let pinch = MagnificationGesture()
            .onChanged { value in
                vm.pinch(by: value)
            }
            .onEnded { _ in }
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

    private func handlePanChanged(_ value: DragGesture.Value) {
        guard !vm.isAnimating else { return }
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
        vm.pan(by: dx, dy: dy)
    }

    private func handlePanEnded(_ value: DragGesture.Value) {
        guard !vm.isAnimating else {
            panVelocity = .zero
            lastPanTranslation = .zero
            return
        }
        let velocity = panVelocity
        panVelocity = .zero
        lastPanTranslation = .zero
        if abs(value.translation.width) > 6 || abs(value.translation.height) > 6 {
            suppressTapUntil = Date().addingTimeInterval(0.25)
        }
        vm.panDecelerate(velocity: velocity)
    }

    private func handleMapTap(at location: CGPoint) {
        guard Date() >= suppressTapUntil else { return }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let mapRect = CGRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height)
        guard mapRect.contains(location) else { return }
        vm.tap(at: location, viewport: viewportSize)
    }

    // MARK: - Level selector

    private var levelSelector: some View {
        Group {
            if vm.levelExpanded {
                expandedLevelSelector
                    .transition(.scale(scale: 0.55, anchor: .bottomLeading).combined(with: .opacity))
            } else {
                collapsedLevelSelector
                    .transition(.scale(scale: 0.55, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .task(id: vm.levelExpanded) {
            guard vm.levelExpanded else { return }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.diarySpring) {
                vm.levelExpanded = false
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
            withAnimation(.diarySpring) {
                vm.levelExpanded = true
            }
        } label: {
            Image(systemName: levelIcon(vm.level))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Capsule()
                        .fill(Theme.primary())
                        .glassEffect(tintedGlass(Theme.primary(), interactive: true), in: Capsule())
                        .shadow(color: Theme.glowColor(), radius: 8, y: 2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.str("a11y_map_level"))
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
            vm.switchLevel(lvl)
            withAnimation(.diarySpring) {
                vm.levelExpanded = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(vm.level == lvl ? .white : Theme.onSurfaceVariant())
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if vm.level == lvl {
                    Capsule().fill(Theme.primary())
                        .glassEffect(tintedGlass(Theme.primary(), interactive: true), in: Capsule())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(vm.level == lvl ? .isSelected : [])
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
                    .glassEffect(tintedGlass(Theme.primary(), interactive: true), in: Circle())
                    .overlay {
                        Circle().stroke(Color.white, lineWidth: 2)
                    }
                    .offset(y: vm.zoomBarOffset(geo.size.height) - 14)
            }
            .frame(width: 40, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pct = min(1, max(0, value.location.y / geo.size.height))
                        vm.zoomBarSet(pct: pct)
                    }
            )
        }
        .frame(width: 40, height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.str("a11y_map_zoom"))
        .accessibilityAdjustableAction { direction in
            let range = vm.zoomRange()
            let step = (range.max - range.min) / 8
            let target = direction == .increment ? vm.camera.zoom + step : vm.camera.zoom - step
            vm.flyTo(lng: vm.camera.centerLng, lat: vm.camera.centerLat,
                     zoom: min(max(target, range.min), range.max))
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(L10n.str("map_stat_provinces"), "\(vm.stats.provinces.count)")
            statCell(L10n.str("map_stat_cities"), "\(vm.stats.cities.count)")
            statCell(L10n.str("map_stat_countries"), "\(vm.stats.countries.count)")
            statCell(L10n.str("map_stat_blocks"), "\(vm.stats.blocks)")
            statCell(L10n.str("map_stat_days"), "\(vm.stats.days.count)")
        }
        .padding(.vertical, 14)
        .diaryGlassCard(cornerRadius: 16)
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
            GlassSheetHeader(title: L10n.str("search_time_title")) {
                showTimeFilter = false
            }
            HStack(spacing: 8) {
                quickChip(L10n.str("search_time_week"), kind: .thisWeek)
                quickChip(L10n.str("search_time_month"), kind: .thisMonth)
                quickChip(L10n.str("search_time_year"), kind: .thisYear)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.str("search_time_start"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
                DatePicker("", selection: Binding(
                    get: { vm.customFrom ?? DateUtil.monthFirst(Date()) },
                    set: { vm.customFrom = DateUtil.startOfDay($0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.primary())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.str("search_time_end"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
                DatePicker("", selection: Binding(
                    get: { vm.customTo ?? Date() },
                    set: { vm.customTo = DateUtil.startOfDay($0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.primary())
            }
            HStack(spacing: 12) {
                GlassSecondaryButton(title: L10n.str("search_time_clear"), fullWidth: true) {
                    vm.clearTimeFilter()
                    showTimeFilter = false
                    Task { await vm.reloadPoints() }
                }
                GlassPrimaryButton(title: L10n.str("search_time_apply"), fullWidth: true) {
                    vm.applyCustomTime()
                    showTimeFilter = false
                    Task { await vm.reloadPoints() }
                }
            }
            .padding(.top, 12)
        }
        .padding(20)
        .padding(.bottom, 8)
    }

    private func quickChip(_ label: String, kind: TimeRangeKind) -> some View {
        GlassChip(label: label, active: vm.timeKind == kind) {
            vm.applyTimeKind(kind)
            showTimeFilter = false
            Task { await vm.reloadPoints() }
        }
    }
}
