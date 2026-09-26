import SwiftUI

import SwiftUI

// MARK: - 横屏右栏：选中日
//
// 左栏月历已经改成连续月历流（`MonthFlowView`，见 `MonthFlow.swift`），
// 这里只剩右栏的「选中日」面板。

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

#Preview("连续月历流 · 横屏左栏 345×330") {
    MonthFlowView(offset: 0,
                  onScroll: { _ in },
                  weekStart: "monday",
                  selectedDate: Date(),
                  flags: [],
                  size: CGSize(width: 345, height: 330),
                  metrics: CalendarLayout.flowMetrics(width: 345, rowH: 45, lunar: false, compact: true),
                  rowH: 45,
                  titleHeight: CalendarLayout.compactMonthTitleH,
                  weekdayHeight: CalendarLayout.compactWeekdayHeaderH,
                  titleFont: TypeSize.pageTitle,
                  compact: true,
                  onTapDay: { _, _ in })
        .frame(width: 345, height: 330)
        .background(BlobBackground())
}

#Preview("连续月历流 · 竖屏 402×665") {
    MonthFlowView(offset: 0,
                  onScroll: { _ in },
                  weekStart: "monday",
                  selectedDate: Date(),
                  flags: [],
                  size: CGSize(width: 402, height: 665),
                  metrics: CalendarLayout.flowMetrics(width: 402, rowH: 94, lunar: true),
                  rowH: 94,
                  onTapDay: { _, _ in })
        .frame(width: 402, height: 665)
        .background(BlobBackground())
}
