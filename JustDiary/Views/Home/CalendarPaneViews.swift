import SwiftUI

// MARK: - 月历面板
//
// 竖屏的「月」态与横屏的左栏共用这一段绘制：`MonthBigTitle` + 星期栏 + `MonthCanvas`。
// 密度不同（横屏可能降级为周条），但结构与画笔完全一致，避免两套月历各自漂移。

struct MonthPane: View {
    var month: Date
    var weekStart: String
    var selectedDate: Date
    var flags: Set<String>
    /// 面板宽度。**已经**在安全区内（横屏时左栏位于系统占位右侧），
    /// 这里不要再扣一遍 `safeArea.leading`，否则横屏会白白浪费一条 62pt 空白。
    var width: CGFloat
    /// 日历区总高（含标题与星期栏）。
    var areaH: CGFloat
    /// 单行高度，由调用方按可用高度算好。
    var cellH: CGFloat
    var density: CalendarDensity
    /// 标题槽与星期栏高度。竖屏用 72 / 30，横屏用紧凑的 34 / 26。
    ///
    /// 这组数字是**年↔月、月↔周 morph 的终点**：morph 里的 `MonthBigTitle` 槽位
    /// 必须和这里一模一样，否则 morph 结束、真实月历接上时会整体上跳。
    /// 之前横屏引入紧凑标题行时把这里的默认值也改成了 32，竖屏于是也用了紧凑行，
    /// 而 morph 仍按 72 计算 —— 这就是「年历切回月历时月历突然上跳」的根因。
    /// 所以默认值只能引用 `portraitTitleHeight` / `portraitWeekdayHeight`，
    /// 它们就是 `CalendarLayout` 里 morph 用的那组常量。
    var titleHeight: CGFloat = MonthPane.portraitTitleHeight
    var weekdayHeight: CGFloat = MonthPane.portraitWeekdayHeight
    var titleFont: CGFloat = TypeSize.display
    var onTapDay: (Date) -> Void

    /// 竖屏（也就是 morph 终点）的标题槽 / 星期栏 / 网格起点。
    static let portraitTitleHeight = CalendarLayout.bigTitleH
    static let portraitWeekdayHeight = CalendarLayout.weekdayHeaderH
    static var portraitGridOriginY: CGFloat { portraitTitleHeight + portraitWeekdayHeight }

    var body: some View {
        let weeks = CalendarLayout.displayedWeeks(inMonth: month, ws: weekStart)
        // 周条只画一行：调用方给的 cellH 是按「铺满整块」算的，周条要夹回一行的高度，
        // 否则降级时会出现一行 200pt 高的巨大日期。
        let rowH = density.isWeekStrip ? min(cellH, CalendarLayout.weekStripH) : cellH
        VStack(spacing: 0) {
            titleRow
            WeekdayHeaderView(weekStart: weekStart, cellW: width / 7)
                .frame(width: width, height: weekdayHeight)
            Group {
                if density.isWeekStrip {
                    MonthCanvas(weeks: [selectedRow(weeks: weeks)],
                                anchorMonth: month,
                                metrics: weekStripMetrics(cellH: rowH),
                                selectedDate: selectedDate,
                                flags: flags,
                                showAdjacent: true,
                                onTapDay: onTapDay)
                        .frame(width: width, height: rowH)
                } else {
                    MonthCanvas(weeks: weeks,
                                anchorMonth: month,
                                metrics: monthMetrics(cellH: rowH),
                                selectedDate: selectedDate,
                                flags: flags,
                                showAdjacent: false,
                                onTapDay: onTapDay)
                        .frame(width: width, height: rowH * CGFloat(weeks.count))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: areaH, alignment: .top)
        .clipped()
    }

    private func monthMetrics(cellH: CGFloat) -> DayMetrics {
        DayMetrics(cellW: width / 7,
                   cellH: cellH,
                   dayFont: Self.dayFont(for: cellH),
                   lunarFont: Self.lunarFont(for: cellH),
                   lunarAlpha: density.showsLunar ? 1 : 0,
                   dividerAlpha: 1)
    }

    private func weekStripMetrics(cellH: CGFloat) -> DayMetrics {
        DayMetrics(cellW: width / 7,
                   cellH: cellH,
                   dayFont: Self.dayFont(for: cellH),
                   lunarFont: Self.lunarFont(for: cellH),
                   lunarAlpha: density.showsLunar ? 1 : 0,
                   dividerAlpha: 0)
    }

    private var titleRow: some View {
        MonthBigTitle(month: month, height: titleHeight, fontSize: titleFont)
            // UI 测试用它读当前月份（横屏翻月、竖屏 morph 都靠这个断言）
            .accessibilityIdentifier("home.monthTitle")
            .frame(height: titleHeight)
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
    /// 标题行高度。横屏把它抬到 44，好放得下「今天」胶囊。
    var headingHeight: CGFloat = CalendarLayout.dayTitleH
    /// 「回到今日」。横屏分栏时放在右栏标题行（左栏整条留给了日期格子）。
    var onTodayTap: (() -> Void)? = nil
    /// 是否显示「开始时间」，由调用方从 `AppSettings.autoTime` 透传给 `DayContentView`。
    var showTime: Bool = true

    @State private var previewImage: PreviewItem?

    var body: some View {
        VStack(spacing: 0) {
            heading
            DayContentView(blocks: blocks,
                           dayKey: dayKey,
                           isFuture: isFuture,
                           openEditor: openEditor,
                           openDiary: openEditor,
                           showFutureToast: {},
                           bottomPadding: 24,
                           showTime: showTime)
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
                .accessibilityIdentifier("home.dayHeading")
            if AppLanguage.isZh {
                Text(Lunar.fullLabel(date))
                    .diaryFont(TypeSize.caption)
                    .foregroundStyle(Theme.onSurfaceVariant().opacity(0.8))
                    .lineLimit(1)
                    // 窄栏（iPhone SE 横屏右栏 311pt）里「丙午年八月初四」放不下，
                    // 直接截断会变成「丙午年八月…」。这里的日期是完整的公历日期，
                    // 农历年份本来就是冗余信息，缩一点比截断好读。
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
            }
            Spacer(minLength: 8)
            if let onTodayTap {
                InfoCapsule(text: L10n.str("index_today"), action: onTodayTap)
                    .accessibilityIdentifier("home.todayChip")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: maxColumnWidth)
        .frame(maxWidth: .infinity)
        .frame(height: headingHeight)
    }
}

// MARK: - Previews
//
// 用来在 Xcode 里直接看横屏分栏的效果；也方便调到某个尺寸反复核对。
// 竖屏那条路径不经过这里（它用的是现有 `HomeView.calendarArea`）。

#Preview("月历面板 · 横屏 345×330") {
    MonthPane(month: Date(),
              weekStart: "monday",
              selectedDate: Date(),
              flags: [],
              width: 345,
              areaH: 330,
              cellH: 60,
              density: .month(lunar: true),
              titleHeight: CalendarLayout.compactMonthTitleH,
              weekdayHeight: CalendarLayout.compactWeekdayHeaderH,
              titleFont: TypeSize.pageTitle,
              onTapDay: { _ in })
        .frame(width: 345, height: 330)
        .background(BlobBackground())
}

#Preview("月历面板 · 高度不足 → 周条") {
    MonthPane(month: Date(),
              weekStart: "monday",
              selectedDate: Date(),
              flags: [],
              width: 345,
              areaH: 260,
              cellH: 52,
              density: .weekStrip,
              titleHeight: CalendarLayout.compactMonthTitleH,
              weekdayHeight: CalendarLayout.compactWeekdayHeaderH,
              titleFont: TypeSize.pageTitle,
              onTapDay: { _ in })
        .frame(width: 345, height: 260)
        .background(BlobBackground())
}
