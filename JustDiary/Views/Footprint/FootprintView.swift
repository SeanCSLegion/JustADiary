import SwiftUI
import Charts

struct FootprintView: View {
    @State private var vm = FootprintViewModel()
    @State private var showTimeFilter = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L10n.str("footprint_title")) {
                Text(L10n.fmt("footprint_summary", vm.locatedCount, vm.unlocated))
                    .font(.system(size: 14))
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
                .padding(.horizontal, 16)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    statsCard
                    if vm.yearly.count > 1 {
                        trendCard
                    }
                    listCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
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
                .presentationBackground(.ultraThinMaterial)
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
        .diaryCard(cornerRadius: 16)
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

    // MARK: - Yearly trend

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.str("footprint_trend_title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.onSurfaceVariant())

            Chart(vm.yearly) { stat in
                BarMark(
                    x: .value(L10n.str("footprint_trend_year"), stat.year),
                    y: .value(L10n.str("footprint_trend_days"), stat.days)
                )
                .foregroundStyle(Theme.primary())
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 132)
            .accessibilityLabel(L10n.str("footprint_trend_title"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diaryCard(cornerRadius: 16)
    }

    // MARK: - Footprint list

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.str("footprint_list_title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.onSurfaceVariant())
                .padding(.bottom, 8)

            if vm.hasPlaces {
                FootprintNodeList(nodes: vm.nodes, depth: 0, expanded: $vm.expanded)
            } else {
                GlassEmptyState(systemImage: "mappin.slash",
                                text: L10n.str("footprint_empty"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diaryCard(cornerRadius: 16)
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(node.isLeaf ? Theme.onSurfaceVariant() : Theme.primary())
                        .frame(width: 16)
                    Text(node.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.onSurface())
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(node.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .monospacedDigit()
                    if !node.isLeaf {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
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
