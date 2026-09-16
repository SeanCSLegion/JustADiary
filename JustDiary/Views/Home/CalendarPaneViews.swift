import SwiftUI

// MARK: - 月历面板
//
// 竖屏的「月」态与横屏的左栏共用这一段绘制：`MonthBigTitle` + 星期栏 + `MonthCanvas`。
// 密度不同（横屏可能降级为周条），但结构与画笔完全一致，避免两套月历各自漂移。

struct MonthPane: View {
    @Environment(\.adaptiveLayout) private var layout
    @Environment(\.diaryDynamicTypeSize) private var typeSize

    var month: Date
    var weekStart: String
    var selectedDate: Date
    var flags: Set<String>
    var width: CGFloat
    /// 日历区总高（含标题与星期栏）。
    var areaH: CGFloat
    /// 单行高度，由调用方按可用高度算好。
    var cellH: CGFloat
    var density: CalendarDensity
    /// 是否在标题行右侧显示「今天」胶囊（横屏用它顶替整屏头部的那个）。
    var showsTodayChip: Bool
    var onTodayTap: (() -> Void)? = nil
    /// 显示年份胶囊（横屏左栏的年份入口；点它进年历）。
    var showsYearChip: Bool = false
    var onYearTap: (() -> Void)? = nil
    var onTapDay: (Date) -> Void

    /// 左侧要避让的系统占位宽度。
    ///
    /// 横屏时系统浮条在**左边缘**（实测 `safeArea.leading = 62`），灵动岛也在左侧，
    /// 所以日历内容整体右移这么多；竖屏 `leading = 0`，等于没有偏移。
    private var leadingInset: CGFloat { layout.contentInset }

    /// 实际画格子的宽度（扣掉系统占位）。
    private var gridWidth: CGFloat { max(120, width - leadingInset) }

    var body: some View {
        let weeks = CalendarLayout.displayedWeeks(inMonth: month, ws: weekStart)
        VStack(spacing: 0) {
            titleRow
            WeekdayHeaderView(weekStart: weekStart, cellW: gridWidth / 7)
                .frame(width: gridWidth, height: CalendarLayout.weekdayHeaderH)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Group {
                if density.isWeekStrip {
                    MonthCanvas(weeks: [selectedRow(weeks: weeks)],
                                anchorMonth: month,
                                metrics: weekStripMetrics,
                                selectedDate: selectedDate,
                                flags: flags,
                                showAdjacent: true,
                                onTapDay: onTapDay)
                        .frame(width: gridWidth, height: cellH)
                } else {
                    MonthCanvas(weeks: weeks,
                                anchorMonth: month,
                                metrics: monthMetrics,
                                selectedDate: selectedDate,
                                flags: flags,
                                showAdjacent: false,
                                onTapDay: onTapDay)
                        .frame(width: gridWidth, height: cellH * CGFloat(weeks.count))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Spacer(minLength: 0)
        }
        // 整块右移，把左边让给系统导航与灵动岛。
        // 用 `.top` 对齐：分页器会按 areaH 裁剪，居中的内容会把第一行裁掉。
        .padding(.leading, leadingInset)
        .frame(width: width, height: areaH, alignment: .top)
        .clipped()
    }

    private var monthMetrics: DayMetrics {
        DayMetrics(cellW: gridWidth / 7,
                   cellH: cellH,
                   dayFont: Self.dayFont(for: cellH),
                   lunarFont: Self.lunarFont(for: cellH),
                   lunarAlpha: density.showsLunar ? 1 : 0,
                   dividerAlpha: 1)
    }

    private var weekStripMetrics: DayMetrics {
        DayMetrics(cellW: gridWidth / 7,
                   cellH: cellH,
                   dayFont: Self.dayFont(for: cellH),
                   lunarFont: Self.lunarFont(for: cellH),
                   lunarAlpha: density.showsLunar ? 1 : 0,
                   dividerAlpha: 0)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 8) {
            MonthBigTitle(month: month)
                .frame(width: nil)
                // UI 测试用它读当前月份（横屏翻月、竖屏 morph 都靠这个断言）
                .accessibilityIdentifier("home.monthTitle")
            Spacer(minLength: 8)
            if showsTodayChip {
                InfoCapsule(text: L10n.str("index_today"), action: onTodayTap)
            }
        }
        .frame(height: MonthPane.monthTitleHeight)
    }

    /// 横屏标题区高度。
    ///
    /// 横屏只有 402pt 高：标题区每多占一点，日期格子就少一点，一旦低于
    /// `CalendarDensity.minimumRowHeight` 就会整块降级成周条。所以横屏只用
    /// **一行**「月标题 + 今天」，年份入口放进右栏标题行，不再单独占一行。
    static let monthTitleHeight: CGFloat = 32
    static let yearRowHeight: CGFloat = 34

    /// 标题区总高：横屏 32pt，竖屏沿用原来的 `bigTitleH(72)`。
    static func titleBlockHeight(compact: Bool) -> CGFloat {
        compact ? monthTitleHeight : CalendarLayout.bigTitleH
    }

    /// 日号字号跟着格子高度走：原来写死 20pt，横屏格子只剩 40pt 时就会和农历重叠。
    static func dayFont(for cellH: CGFloat) -> CGFloat {
        min(20, max(13, cellH * 0.34))
    }

    static func lunarFont(for cellH: CGFloat) -> CGFloat {
        min(11, max(9, cellH * 0.18))
    }

    /// 周条模式显示选中日所在的那一周。
    private func selectedRow(weeks: [WeekDays]) -> WeekDays {
        let idx = CalendarLayout.weekRowIndex(of: selectedDate, in: month, ws: weekStart)
        return weeks.indices.contains(idx) ? weeks[idx] : weeks[0]
    }
}

// MARK: - 选中日面板

struct DayPane: View {
    var blocks: [EditBlock]?
    var dayKey: String
    var isFuture: Bool
    var openEditor: (String) -> Void
    /// 底部为系统浮条 / 指示条预留。
    var bottomInset: CGFloat
    /// 正文列宽上限：宽栏必须限宽，否则一行 100+ 字。
    var maxColumnWidth: CGFloat = 660
    /// 年份入口（横屏放在右栏标题行，左栏让给日期格子）。
    var year: Int = 0
    var onYearTap: (() -> Void)? = nil

    @State private var previewImage: PreviewItem?

    var body: some View {
        VStack(spacing: 0) {
            heading
            DayContentView(blocks: blocks,
                           dayKey: dayKey,
                           isFuture: isFuture,
                           openEditor: openEditor,
                           openDiary: openEditor,
                           showFutureToast: {})
                .frame(maxWidth: maxColumnWidth)
                .frame(maxWidth: .infinity)
                // 系统浮条悬在内容之上；横屏时它高 64pt，用 safeArea.bottom 就够。
                .padding(.bottom, max(bottomInset, 24))
        }
        .fullScreenCover(item: $previewImage) { item in
            ImagePreviewView(item: item)
        }
    }

    private var heading: some View {
        let date = DateUtil.parseDayKey(dayKey) ?? Date()
        return HStack(spacing: 10) {
            Text(L10n.formatDayKey(dayKey))
                .diaryFont(TypeSize.rowTitle, weight: .semibold)
                .foregroundStyle(Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
            if AppLanguage.isZh, onYearTap == nil {
                Text(Lunar.fullLabel(date))
                    .diaryFont(TypeSize.caption)
                    .foregroundStyle(Theme.onSurfaceVariant().opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let onYearTap, year > 0 {
                Button {
                    Haptics.tap()
                    onYearTap()
                } label: {
                    Text(L10n.fmt("date_year", year))
                        .diaryFont(TypeSize.chip, weight: .medium)
                        .foregroundStyle(Theme.onSurface())
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(true), in: Capsule())
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.yearChip")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: maxColumnWidth)
        .frame(maxWidth: .infinity)
        .frame(height: CalendarLayout.dayTitleH)
    }
}

// MARK: - Previews
//
// 用来在 Xcode 里直接看横屏分栏的效果；也方便调到某个尺寸反复核对。
// 竖屏那条路径不经过这里（它用的是现有 `HomeView.calendarArea`）。

#Preview("月历面板 · 横屏 440×402") {
    MonthPane(month: Date(),
              weekStart: "monday",
              selectedDate: Date(),
              flags: [],
              width: 440,
              areaH: 402,
              cellH: 56,
              density: .month(lunar: true),
              showsTodayChip: true,
              onTapDay: { _ in })
        .frame(width: 440, height: 402)
        .background(BlobBackground())
}

#Preview("月历面板 · 高度不足 → 周条") {
    MonthPane(month: Date(),
              weekStart: "monday",
              selectedDate: Date(),
              flags: [],
              width: 440,
              areaH: 260,
              cellH: 52,
              density: .weekStrip,
              showsTodayChip: true,
              onTapDay: { _ in })
        .frame(width: 440, height: 260)
        .background(BlobBackground())
}
