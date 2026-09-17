import SwiftUI
import Charts

struct FootprintView: View {
    @Environment(\.adaptiveLayout) private var layout
    @State private var vm = FootprintViewModel()
    @State private var showTimeFilter = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L10n.str("footprint_title")) {
                Text(L10n.fmt("footprint_summary", vm.locatedCount, vm.unlocated))
                    .diaryFont(TypeSize.chip)
                    .foregroundStyle(Theme.onSurfaceVariant())
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    yearChip(L10n.str("footprint_time_all"), value: "all")
                    ForEach(vm.years, id: \.self) { year in
                        yearChip(year, value: year)
                    }
                    GlassActionChip(label: vm.timeRangeLabel,
                                    active: vm.timeKind == .custom) {
                        Haptics.tap()
                        showTimeFilter = true
                    }
                }
                .adaptivePagePadding()
            }

            ScrollView(showsIndicators: false) {
                Group {
                    if layout.splitsDashboard {
                        // 宽屏：三栏骨架里的「中栏 = 统计 + 趋势图」那一栏
                        VStack(spacing: 12) {
                            statsCard
                            if vm.yearly.count > 1 { trendCard() }
                        }
                    } else if layout.isPortrait {
                        // 竖屏：统计 → 趋势 → 清单，单栏纵向（保持现状）
                        VStack(spacing: 12) {
                            statsCard
                            if vm.yearly.count > 1 { trendCard() }
                            listCard(scrollable: false)
                        }
                    } else {
                        // 手机横屏：只有 402pt 高，清单排在趋势图下面会被浮条压掉，
                        // 改成「趋势图 flex + 地点清单固定宽」并排（docs/adaptive-layout-plan.md
                        // §3.2）。标题 + 筛选 + 统计约占 200pt、底部浮条占 64pt，
                        // 剩下的高度才是这两块，否则首屏就会把横轴压到浮条底下。
                        let blockH = max(140, min(190, layout.size.height - 262))
                        VStack(spacing: 12) {
                            statsCard
                            HStack(alignment: .top, spacing: 12) {
                                if vm.yearly.count > 1 {
                                    trendCard(chartHeight: max(72, blockH - 58))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                                               alignment: .topLeading)
                                }
                                listCard(scrollable: true)
                                    .frame(width: listPaneWidth)
                            }
                            .frame(height: blockH)
                        }
                    }
                }
                .adaptivePagePadding()
                .padding(.top, 10)
                // 底部要给横屏那枚悬在屏幕底部的系统浮条留位置（实测 y 338–402）
                .padding(.bottom, max(24, layout.bottomInset + 44))
            }
        }
        .padding(.top, 12)
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await vm.reload() }
        }
        .sheet(isPresented: $showTimeFilter) {
            timeFilterSheet
                .presentationDetents([.medium])
        }
    }

    // MARK: - Filter chips

    private func yearChip(_ label: String, value: String) -> some View {
        GlassChip(label: label, active: vm.timeKind == .all && vm.yearFilter == value) {
            vm.yearFilter = value
            vm.applyTimeKind(.all)
            Task { await vm.reload() }
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(L10n.str("footprint_stat_provinces"), "\(vm.stats.provinces.count)")
            statCell(L10n.str("footprint_stat_cities"), "\(vm.stats.cities.count)")
            statCell(L10n.str("footprint_stat_countries"), "\(vm.stats.countries.count)")
            statCell(L10n.str("footprint_stat_blocks"), "\(vm.stats.blocks)")
            statCell(L10n.str("footprint_stat_days"), "\(vm.stats.days.count)")
        }
        .padding(.vertical, 14)
        .diaryCard(cornerRadius: Radius.card)
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .diaryFont(TypeSize.statValue, weight: .semibold)
                .foregroundStyle(Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // Five cells share the row width, so both lines shrink rather than
            // clip once the user raises the system text size.
            Text(label)
                .diaryFont(TypeSize.caption)
                .foregroundStyle(Theme.onSurfaceVariant())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Yearly trend

    private func trendCard(chartHeight: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.str("footprint_trend_title"))
                .diaryFont(TypeSize.sectionTitle, weight: .medium)
                .foregroundStyle(Theme.onSurfaceVariant())

            Chart(vm.yearly) { stat in
                BarMark(
                    x: .value(L10n.str("footprint_trend_year"), stat.year),
                    y: .value(L10n.str("footprint_trend_days"), stat.days)
                )
                .foregroundStyle(Theme.primary())
                .cornerRadius(Radius.bar)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: chartHeight ?? (layout.splitsDashboard ? 200 : 132))
            // Axis labels are drawn by Charts from the environment font; without
            // this they stayed at the system default while the rest of the card
            // followed the user's text size.
            .diaryFont(TypeSize.caption)
            .accessibilityLabel(L10n.str("footprint_trend_title"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diaryCard(cornerRadius: Radius.card)
    }

    // MARK: - Footprint list

    /// 横屏并排时地点清单那一栏的宽度（趋势图拿走剩下的）。
    private var listPaneWidth: CGFloat {
        min(320, max(240, layout.contentWidth * 0.4))
    }

    /// - Parameter scrollable: 横屏并排时清单被限制在固定高度里，需要在卡片内部滚动，
    ///   否则长清单会把卡片顶出可视区。
    private func listCard(scrollable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.str("footprint_list_title"))
                .diaryFont(TypeSize.sectionTitle, weight: .medium)
                .foregroundStyle(Theme.onSurfaceVariant())
                .padding(.bottom, 8)

            if vm.hasPlaces {
                if scrollable {
                    ScrollView(showsIndicators: false) {
                        FootprintNodeList(nodes: vm.nodes, depth: 0, expanded: $vm.expanded)
                    }
                } else {
                    FootprintNodeList(nodes: vm.nodes, depth: 0, expanded: $vm.expanded)
                }
            } else {
                GlassEmptyState(systemImage: "mappin.slash",
                                text: L10n.str("footprint_empty"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: scrollable ? .infinity : nil, alignment: .topLeading)
        .diaryCard(cornerRadius: Radius.card)
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
                    .diaryFont(TypeSize.caption)
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
                    .diaryFont(TypeSize.caption)
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
                    Task { await vm.reload() }
                }
                GlassPrimaryButton(title: L10n.str("search_time_apply"), fullWidth: true) {
                    vm.applyCustomTime()
                    showTimeFilter = false
                    Task { await vm.reload() }
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
            Task { await vm.reload() }
        }
    }
}

// MARK: - Recursive tree rows

/// Recursion goes through nominal types because a `@ViewBuilder` function that
/// returns `some View` cannot refer to itself.
private struct FootprintNodeList: View {
    let nodes: [FootprintNode]
    let depth: Int
    @Binding var expanded: Set<String>

    var body: some View {
        ForEach(nodes) { node in
            FootprintNodeRow(node: node, depth: depth, expanded: $expanded)
        }
    }
}

private struct FootprintNodeRow: View {
    /// Stable identifier so UI tests can address tree rows without depending on
    /// the user's actual location data.
    static let nodeIdentifier = "footprint.node"

    let node: FootprintNode
    let depth: Int
    @Binding var expanded: Set<String>

    private var isExpanded: Bool { expanded.contains(node.id) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                guard !node.isLeaf else { return }
                Haptics.tap()
                withAnimation(.diaryQuick) {
                    if isExpanded { expanded.remove(node.id) } else { expanded.insert(node.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .diaryFont(12, weight: .medium)
                        .foregroundStyle(node.isLeaf ? Theme.onSurfaceVariant() : Theme.primary())
                        .frame(width: 16)
                    Text(node.name)
                        .diaryFont(TypeSize.rowTitle)
                        .foregroundStyle(Theme.onSurface())
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(node.count)")
                        .diaryFont(TypeSize.badge, weight: .medium)
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .monospacedDigit()
                    if !node.isLeaf {
                        Image(systemName: "chevron.right")
                            .diaryFont(TypeSize.caption, weight: .semibold)
                            .foregroundStyle(Theme.onSurfaceVariant())
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.leading, CGFloat(depth) * 16)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(FootprintNodeRow.nodeIdentifier)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                FootprintNodeList(nodes: node.children, depth: depth + 1, expanded: $expanded)
            }
        }
    }

    private var iconName: String {
        switch depth {
        case 0: return "globe.asia.australia"
        case 1: return "map"
        default: return "mappin"
        }
    }
}
