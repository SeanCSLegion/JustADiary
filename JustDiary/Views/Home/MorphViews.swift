import SwiftUI

// MARK: - Year <-> Month zoom morph

struct YearMonthMorphView: View, Animatable {
    var progress: Double
    var year: Int
    var month: Date
    var size: CGSize
    var weekStart: String
    var selectedDate: Date
    var flags: Set<String>
    var showsLunar: Bool

    var animatableData: Double {
        get { progress }
        set {
            progress = newValue
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-morph-log") {
                MorphProgressLog.shared.append(newValue, tag: "ym")
            }
            #endif
        }
    }

    var body: some View {
        let t = CL.clamp01(1 - progress)
        let monthNum = DateUtil.calendar.component(.month, from: month)
        let miniRect = CalendarLayout.miniGridRect(month: monthNum, in: size)
        let fullRect = CalendarLayout.fullMonthGridRect(in: size)
        let grid = CL.lerp(miniRect, fullRect, t)
        // 迷你月的起点必须与年历页完全一致（否则过渡中字号会跳）
        let mini = CalendarLayout.miniMetrics(in: size)
        let full = CalendarLayout.monthMetrics(width: size.width, areaH: size.height, lunar: showsLunar)
        var metrics = DayMetrics.lerp(mini, full, t)
        metrics.cellW = grid.width / 7
        metrics.cellH = grid.height / 6
        metrics.lunarAlpha = showsLunar ? CL.clamp01((t - 0.5) / 0.5) : 0
        metrics.dividerAlpha = CL.clamp01((t - 0.55) / 0.45)
        let late = CL.clamp01((t - 0.55) / 0.45)
        let card = CalendarLayout.yearCardRect(month: monthNum, in: size)
        let anchor = UnitPoint(x: card.midX / size.width, y: card.midY / size.height)
        let yearOpacity = CL.clamp01((progress - 0.45) / 0.55)
        let yearScale = 1 + (1 - progress) * 0.6
        let labelOpacity = CL.clamp01((progress - 0.7) / 0.3)
        return ZStack(alignment: .topLeading) {
            YearPageView(year: year,
                         selectedDate: selectedDate,
                         flags: flags,
                         weekStart: weekStart,
                         containerSize: size,
                         hiddenMonth: monthNum,
                         onSelectMonth: { _ in })
                .scaleEffect(yearScale, anchor: anchor)
                .opacity(yearOpacity)
            VStack(spacing: 0) {
                // 固定尺寸的槽位：动画中 `MonthBigTitle` 的生长/收缩不会推动
                // 下面的星期栏与日期网格（之前月份数字会「跳一下」）。
                ZStack(alignment: .leading) {
                    MonthBigTitle(month: month)
                        .accessibilityIdentifier("home.monthTitle")
                }
                .frame(height: CalendarLayout.bigTitleH)
                WeekdayHeaderView(weekStart: weekStart, cellW: size.width / 7)
                    .frame(height: CalendarLayout.weekdayHeaderH)
            }
            .opacity(late)
            MonthCanvas(weeks: CalendarLayout.weeks(inMonth: month, ws: weekStart),
                        anchorMonth: month,
                        metrics: metrics,
                        selectedDate: selectedDate,
                        flags: flags,
                        showAdjacent: false,
                        onTapDay: nil)
                .frame(width: grid.width, height: grid.height)
                .offset(x: grid.minX, y: grid.minY)
            // 源头月份的迷你月标题，必须与 `YearPageView.miniMonth` 用**同一个**
            // `miniTitleRect` 和同一种写法（`frame(width:height:alignment: .leading)`
            // + `offset`）。之前这里用 `.position` 把视图中心对到卡片中心，算出来的
            // 原点是 `midX - width/2`，与年历页的取整差 1/3pt；morph 被移除、真实年历
            // 接上的那一帧，月份数字会「啪」地挪一下（x/y 各 1px @3x）。
            let title = CalendarLayout.miniTitleRect(month: monthNum, in: size)
            MiniMonthLabel(year: year, month: monthNum)
                .frame(width: title.width, height: title.height, alignment: .leading)
                .offset(x: title.minX, y: title.minY)
                .opacity(labelOpacity)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Month <-> Week expand morph

struct MonthWeekMorphView<Content: View>: View, Animatable {
    var progress: Double
    var month: Date
    var selectedDate: Date
    var flags: Set<String>
    var weekStart: String
    var size: CGSize
    var showsLunar: Bool
    @ViewBuilder var content: () -> Content

    var animatableData: Double {
        get { progress }
        set {
            progress = newValue
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-morph-log") {
                MorphProgressLog.shared.append(newValue, tag: "mw")
            }
            #endif
        }
    }

    var body: some View {
        let weeks = CalendarLayout.weeks(inMonth: month, ws: weekStart)
        let selRow = CalendarLayout.weekRowIndex(of: selectedDate, in: month, ws: weekStart)
        let titleH = CalendarLayout.bigTitleH
        let headH = CalendarLayout.weekdayHeaderH
        let cellH = CalendarLayout.monthCellH(areaH: size.height)
        let mMetrics = CalendarLayout.monthMetrics(width: size.width, areaH: size.height, lunar: showsLunar)
        let wMetrics = CalendarLayout.weekMetrics(width: size.width, lunar: showsLunar)
        let stripBottom = headH + CalendarLayout.weekStripH
        let contentT = CL.clamp01((progress - 0.25) / 0.75)
        return ZStack(alignment: .top) {
            MonthBigTitle(month: month)
                .accessibilityIdentifier("home.monthTitle")
                .offset(y: -progress * titleH)
                .opacity(1 - CL.clamp01(progress * 2))
            WeekdayHeaderView(weekStart: weekStart, cellW: size.width / 7)
                .frame(width: size.width, height: headH)
                .offset(y: CL.lerp(titleH, 0, progress))
            ForEach(0..<6, id: \.self) { i in
                row(i, weeks: weeks, selRow: selRow, titleH: titleH, headH: headH,
                    cellH: cellH, mMetrics: mMetrics, wMetrics: wMetrics)
            }
            content()
                .offset(y: stripBottom + (CalendarLayout.dayTitleH + 20) * (1 - contentT))
                .opacity(CL.clamp01((progress - 0.3) / 0.5))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
    }

    private func row(_ i: Int, weeks: [WeekDays], selRow: Int,
                     titleH: CGFloat, headH: CGFloat, cellH: CGFloat,
                     mMetrics: DayMetrics, wMetrics: DayMetrics) -> some View {
        let base = titleH + headH + CGFloat(i) * cellH
        var y: CGFloat
        var alpha: Double
        var metrics = mMetrics
        if i == selRow {
            y = CL.lerp(base, headH, progress)
            alpha = 1
            metrics = DayMetrics.lerp(mMetrics, wMetrics, progress)
        } else if i < selRow {
            y = base - CGFloat(progress) * (base + cellH)
            alpha = 1 - CL.clamp01(progress * 1.4)
        } else {
            y = base + CGFloat(progress) * (size.height - base)
            alpha = 1 - CL.clamp01(progress * 1.4)
        }
        return WeekRowCanvas(week: weeks[i],
                             metrics: metrics,
                             selectedDate: selectedDate,
                             flags: flags,
                             alpha: alpha,
                             showDivider: i > 0,
                             anchorMonth: month,
                             adjacentAlpha: progress,
                             onTapDay: nil)
            .frame(width: size.width, height: metrics.cellH)
            .offset(y: y)
    }
}
