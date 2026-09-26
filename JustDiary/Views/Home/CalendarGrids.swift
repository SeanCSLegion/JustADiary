import SwiftUI

struct WeekdayHeaderView: View {
    var weekStart: String
    var cellW: CGFloat
    var fontSize: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            let names = L10n.weekdayNames(weekStart: weekStart)
            let size = fontSize ?? CalendarLayout.weekdayFontSize(cellW: cellW)
            ForEach(0..<7, id: \.self) { i in
                let isWeekend = weekStart == "sunday" ? (i == 0 || i == 6) : (i >= 5)
                Text(names[i])
                    .diaryCalendarFont(size)
                    .foregroundStyle(isWeekend ? Theme.onSurfaceVariant().opacity(0.6) : Theme.onSurfaceVariant())
                    .frame(width: cellW)
            }
        }
    }
}

enum DayDraw {
    static func lunarLineH(_ m: DayMetrics) -> CGFloat {
        m.lunarAlpha > 0.01 ? (m.lunarFont + 5) * CGFloat(m.lunarAlpha) : 0
    }

    /// 行内日期块的**上留白**：日期是垂直居中画的，所以内容顶 = 行顶 + 这个值。
    ///
    /// 月份小标题要「紧贴数字上方」就得知道这个数：带子不再是行与行之间的一条空隙，
    /// 而是坐在本月第一行的上留白里（见 `MonthFlowView.blockView`）。
    static func contentTopPadding(_ m: DayMetrics) -> CGFloat {
        let contentH = m.dayFont + 4 + lunarLineH(m)
        return max(0, (m.cellH - contentH) / 2)
    }

    private static let lock = NSLock()
    private static var textCache: [TextKey: GraphicsContext.ResolvedText] = [:]
    /// High-water mark for the resolved-text cache. The animated font size mints
    /// a key per half point, so a morph can legitimately add a few thousand
    /// entries; the limit only exists to stop unbounded growth over a long
    /// session.
    private static let maxEntries = 24_000

    private struct TextKey: Hashable {
        var text: String
        var size: CGFloat
        var weight: Int
        var color: Int
        var isDark: Bool
    }

    /// 每格日期上方的那一小段分隔线。
    ///
    /// 用户的要求：「分割线应该在日期上面，如果没有日期的位置就没有分割线，
    /// 分割线不是一整行的」—— 所以这里是**按格**画（每格左右各留一点缝，格子之间不连成
    /// 一条通栏的线），并且只画**这一行真的画了日期**的那几列（相邻月的空白格不画）。
    static func drawCellDividers(_ context: GraphicsContext,
                                 columns: [Int],
                                 rowY: CGFloat,
                                 cellW: CGFloat,
                                 alpha: Double) {
        guard alpha > 0.01, cellW > 0, !columns.isEmpty else { return }
        let inset = cellW * 0.16
        let width = max(1, cellW - inset * 2)
        let color = Theme.outlineVariant().opacity(0.35 * alpha)
        for col in columns {
            context.fill(Path(CGRect(x: CGFloat(col) * cellW + inset,
                                     y: rowY - 0.5,
                                     width: width,
                                     height: 1)),
                         with: .color(color))
        }
    }

    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        textCache.removeAll()
    }

    static func draw(_ context: GraphicsContext,
                     day: Date,
                     col: Int,
                     rowY: CGFloat,
                     m: DayMetrics,
                     alpha: Double,
                     selectedKey: String,
                     todayKey: String,
                     flags: Set<String>,
                     anchorMonth: Date?,
                     isDark: Bool,
                     adjacentAlpha: Double = 1) {
        let dayKey = DateUtil.dayKeyOf(day)
        let isSelected = dayKey == selectedKey
        let isToday = dayKey == todayKey
        let isFuture = dayKey > todayKey
        let inMonth = anchorMonth.map { DateUtil.calendar.isDate(day, equalTo: $0, toGranularity: .month) } ?? true
        var cellAlpha = alpha
        if isFuture {
            cellAlpha *= 0.35
        } else if !inMonth {
            cellAlpha *= adjacentAlpha
        }
        guard cellAlpha > 0.01 else { return }

        let lineH = lunarLineH(m)
        let contentH = m.dayFont + 4 + lineH
        let top = rowY + (m.cellH - contentH) / 2
        let numY = top + m.dayFont / 2
        let lunarY = top + m.dayFont + 4 + lineH / 2
        let cx = (CGFloat(col) + 0.5) * m.cellW
        let circleC = top + contentH / 2
        // 选中圆比内容再大一圈，让「选中」比「今天」更醒目；但受格宽/格高夹住，
        // 相邻两格之间不会碰在一起。
        let circleD = min(m.cellW - 3, contentH + 14, m.cellH - 3)

        if isSelected {
            context.fill(Path(ellipseIn: CGRect(x: cx - circleD / 2, y: circleC - circleD / 2,
                                                width: circleD, height: circleD)),
                         with: .color(Theme.primary().opacity(cellAlpha)))
        } else if isToday {
            let lineWidth: CGFloat = 1.5
            let inset = lineWidth / 2
            context.stroke(Path(ellipseIn: CGRect(x: cx - circleD / 2 + inset, y: circleC - circleD / 2 + inset,
                                                  width: circleD - lineWidth, height: circleD - lineWidth)),
                           with: .color(Theme.primary().opacity(cellAlpha)),
                           lineWidth: lineWidth)
        }

        let textColor: Color
        let colorKey: Int
        if isSelected {
            textColor = Theme.onPrimary()
            colorKey = 0
        } else if isToday {
            textColor = Theme.primary()
            colorKey = 1
        } else if inMonth {
            textColor = Theme.onSurface()
            colorKey = 2
        } else {
            textColor = Theme.onSurface().opacity(0.5)
            colorKey = 3
        }

        let dayNum = DateUtil.calendar.component(.day, from: day)
        let num = resolvedText(context, "\(dayNum)", size: m.dayFont, weight: isSelected ? 1 : 0, color: colorKey, colorStyle: textColor, isDark: isDark)
        context.drawLayer { layer in
            layer.opacity = cellAlpha
            layer.draw(num, at: CGPoint(x: cx, y: numY), anchor: .center)
            if lineH > 0.5 {
                let lunar = resolvedText(context, Lunar.dayLabel(day), size: m.lunarFont, weight: 0, color: colorKey,
                                         colorStyle: textColor.opacity(isSelected ? 0.95 : 0.75), isDark: isDark)
                layer.draw(lunar, at: CGPoint(x: cx, y: lunarY), anchor: .center)
            }
        }

        if flags.contains(dayKey) {
            let w = min(20, m.cellW * 0.5)
            let uy = numY + m.dayFont / 2 + 2
            let underline = Path(roundedRect: CGRect(x: cx - w / 2, y: uy, width: w, height: 2),
                                 cornerRadius: Radius.hairline)
            let color: Color = isSelected ? Theme.onPrimary() : Theme.primary()
            context.fill(underline, with: .color(color.opacity(cellAlpha)))
        }
    }

    private static func resolvedText(_ context: GraphicsContext, _ text: String, size: CGFloat, weight: Int, color: Int,
                                     colorStyle: Color, isDark: Bool) -> GraphicsContext.ResolvedText {
        let quantizedSize = (size * 2).rounded() / 2
        let key = TextKey(text: text, size: quantizedSize, weight: weight, color: color, isDark: isDark)
        lock.lock()
        if let cached = textCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let resolved = context.resolve(Text(text)
            .font(.system(size: quantizedSize, weight: weight == 1 ? .semibold : .medium))
            .foregroundStyle(colorStyle))
        lock.lock()
        if textCache.count > Self.maxEntries {
            // Evicting everything here was destroying ~4k entries in the middle
            // of a morph: the animated font size mints a new key per half point,
            // so the cache crossed the limit while the animation was running and
            // every visible string then had to be re-resolved on the next frame,
            // which showed up as a dropped frame.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-morph-log") {
                MorphProgressLog.shared.append("textcache-evict-\(textCache.count)")
            }
            #endif
            textCache.removeAll(keepingCapacity: true)
        }
        textCache[key] = resolved
        lock.unlock()
        return resolved
    }
}

struct MonthCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.diaryDynamicTypeSize) private var typeSize

    var weeks: [WeekDays]
    var anchorMonth: Date
    var metrics: DayMetrics
    var selectedDate: Date
    var flags: Set<String>
    var showAdjacent: Bool = false
    var onTapDay: ((Date) -> Void)? = nil
    var onAdjacentDaySelected: ((Date) -> Void)? = nil

    /// Canvas text cannot follow Dynamic Type automatically, so the design font
    /// sizes are scaled here.
    private var drawnMetrics: DayMetrics {
        var m = metrics
        let f = DynamicTypeMetrics.calendarMultiplier(for: typeSize)
        m.dayFont *= f
        m.lunarFont *= f
        return m
    }

    var body: some View {
        let metrics = drawnMetrics
        return Canvas { context, _ in
            let todayKey = DateUtil.dayKeyOf(Date())
            let selectedKey = DateUtil.dayKeyOf(selectedDate)
            for (i, week) in weeks.enumerated() {
                let rowY = CGFloat(i) * metrics.cellH
                // 末尾「整周都不属于本月」的填充行不画分隔线：morph 用的是固定 6 行，
                // 真实月历只用 `displayedWeeks`（5 行月份少一行），不跳过的话动画收尾
                // 会在最后一行下面多出一条线、然后就消失。
                let rowInMonth = showAdjacent || week.days.contains {
                    DateUtil.calendar.isDate($0, equalTo: anchorMonth, toGranularity: .month)
                }
                // 这一行真正画出来的列（相邻月的空白格不算）—— 分隔线只画在这些格子上。
                let drawn = week.days.enumerated().compactMap { col, day -> Int? in
                    (showAdjacent || DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month))
                        ? col : nil
                }
                if i > 0, rowInMonth {
                    DayDraw.drawCellDividers(context, columns: drawn, rowY: rowY,
                                             cellW: metrics.cellW, alpha: metrics.dividerAlpha)
                }
                for (col, day) in week.days.enumerated() {
                    if !showAdjacent,
                       !DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
                        continue
                    }
                    DayDraw.draw(context, day: day, col: col, rowY: rowY, m: metrics, alpha: 1,
                                 selectedKey: selectedKey, todayKey: todayKey, flags: flags,
                                 anchorMonth: anchorMonth, isDark: colorScheme == .dark, adjacentAlpha: 1)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1).onEnded { value in
                guard let onTapDay, let day = dayAt(point: value.location) else { return }
                onTapDay(day)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.fmt("date_month_title",
                                     DateUtil.calendar.component(.year, from: anchorMonth),
                                     L10n.monthName(DateUtil.calendar.component(.month, from: anchorMonth))))
        .accessibilityValue(L10n.formatDayKey(DateUtil.dayKeyOf(selectedDate)))
        .accessibilityAdjustableAction { direction in
            guard let onAdjacentDaySelected else { return }
            let delta = direction == .increment ? 1 : -1
            onAdjacentDaySelected(DateUtil.addDays(selectedDate, delta))
        }
        .accessibilityAction {
            onTapDay?(selectedDate)
        }
    }

    private func dayAt(point: CGPoint) -> Date? {
        let col = Int(point.x / metrics.cellW)
        let row = Int(point.y / metrics.cellH)
        guard col >= 0, col < 7, row >= 0, row < weeks.count else { return nil }
        guard weeks[row].days.indices.contains(col) else { return nil }
        let day = weeks[row].days[col]
        if !showAdjacent, !DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
            return nil
        }
        return day
    }
}

struct WeekRowCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.diaryDynamicTypeSize) private var typeSize

    var week: WeekDays
    var metrics: DayMetrics
    var selectedDate: Date
    var flags: Set<String>
    var alpha: Double = 1
    var showDivider: Bool = false
    var anchorMonth: Date? = nil
    var adjacentAlpha: Double = 1
    /// 是否画相邻月的日期。连续月历流里**不画**（与参考一致：月份边界那一周由两个月
    /// 各画自己那一半，另一边留白），周条与 morph 里要画（那里的 `anchorMonth` 为 nil）。
    var showAdjacent: Bool = true
    var onTapDay: ((Date) -> Void)? = nil

    private var drawnMetrics: DayMetrics {
        var m = metrics
        let f = DynamicTypeMetrics.calendarMultiplier(for: typeSize)
        m.dayFont *= f
        m.lunarFont *= f
        return m
    }

    var body: some View {
        let metrics = drawnMetrics
        return Canvas { context, size in
            let todayKey = DateUtil.dayKeyOf(Date())
            let selectedKey = DateUtil.dayKeyOf(selectedDate)
            // 只画有日期的那几格：相邻月的空白格上没有线（连续月历流的月份边界那两行
            // 因此是「半行线」）。分隔线本身也按格断开，不是通栏一条。
            let drawn = week.days.enumerated().compactMap { col, day -> Int? in
                if !showAdjacent, let anchorMonth,
                   !DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
                    return nil
                }
                return col
            }
            if showDivider {
                DayDraw.drawCellDividers(context, columns: drawn, rowY: 0,
                                         cellW: metrics.cellW, alpha: metrics.dividerAlpha * alpha)
            }
            for (col, day) in week.days.enumerated() {
                if !showAdjacent, let anchorMonth,
                   !DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
                    continue
                }
                DayDraw.draw(context, day: day, col: col, rowY: 0, m: metrics, alpha: alpha,
                             selectedKey: selectedKey, todayKey: todayKey, flags: flags,
                             anchorMonth: anchorMonth, isDark: colorScheme == .dark, adjacentAlpha: adjacentAlpha)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1).onEnded { value in
                guard let onTapDay else { return }
                let col = Int(value.location.x / metrics.cellW)
                guard week.days.indices.contains(col) else { return }
                let day = week.days[col]
                // 只画本月的日期时，空白格不能点：否则会选中一个屏幕上看不见的日子
                // （相邻月的日期不在本块里）。
                if !showAdjacent, let anchorMonth,
                   !DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
                    return
                }
                onTapDay(day)
            }
        )
    }
}

/// 一整块（一个月的所有周行）画在**一张** `Canvas` 里。
///
/// 连续月历流滚动时每一帧都要重画可见的行：一屏 8–9 行如果各是一张 `Canvas`，
/// 每帧就是 8–9 次绘制（每次 7 个日期 + 农历 + 按格分隔线），快速滑动时跟不上手指
/// （用户反馈「快速滑动不跟手、不流畅」）。合成一张后每帧只有 2–3 张。
struct MonthBlockCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.diaryDynamicTypeSize) private var typeSize

    var weeks: [WeekDays]
    var anchorMonth: Date
    var metrics: DayMetrics
    var selectedDate: Date
    var flags: Set<String>
    /// 本块第一行是否画分隔线（整条流的第一行不画 —— 上面就是星期栏）。
    var showsFirstDivider: Bool
    /// 点某一天：回传 (日期, 行号)，行号给 morph 源用。
    var onTapDay: ((Date, Int) -> Void)?

    private var drawnMetrics: DayMetrics {
        var m = metrics
        let f = DynamicTypeMetrics.calendarMultiplier(for: typeSize)
        m.dayFont *= f
        m.lunarFont *= f
        return m
    }

    var body: some View {
        let m = drawnMetrics
        return Canvas { context, _ in
            let todayKey = DateUtil.dayKeyOf(Date())
            let selectedKey = DateUtil.dayKeyOf(selectedDate)
            for (i, week) in weeks.enumerated() {
                let rowY = CGFloat(i) * m.cellH
                var inMonth = [Bool](repeating: false, count: week.days.count)
                var columns: [Int] = []
                for (col, day) in week.days.enumerated()
                where DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
                    inMonth[col] = true
                    columns.append(col)
                }
                // 分隔线按格画、只画本月有日期的那几格（空白格没有线）。
                if i > 0 || showsFirstDivider {
                    DayDraw.drawCellDividers(context, columns: columns, rowY: rowY,
                                             cellW: m.cellW, alpha: m.dividerAlpha)
                }
                for (col, day) in week.days.enumerated() where inMonth[col] {
                    DayDraw.draw(context, day: day, col: col, rowY: rowY, m: m, alpha: 1,
                                 selectedKey: selectedKey, todayKey: todayKey, flags: flags,
                                 anchorMonth: anchorMonth, isDark: colorScheme == .dark)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1).onEnded { value in
                guard let onTapDay else { return }
                let row = Int(value.location.y / m.cellH)
                let col = Int(value.location.x / m.cellW)
                guard weeks.indices.contains(row), weeks[row].days.indices.contains(col) else { return }
                let day = weeks[row].days[col]
                // 只画本月的日期，空白格不能点（否则会选中屏幕上看不见的日子）。
                guard DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) else { return }
                onTapDay(day, row)
            }
        )
    }
}

struct MonthBigTitle: View {
    var month: Date
    /// 标题槽高度。竖屏是 `CalendarLayout.bigTitleH`（72），横屏分栏用紧凑值。
    /// **必须**和连续月历流（`MonthFlowView`）的标题槽、morph 的终点用同一个数，
    /// 否则切换时网格会跳。
    var height: CGFloat = CalendarLayout.bigTitleH
    var fontSize: CGFloat = TypeSize.display

    var body: some View {
        Text(L10n.monthFull(month))
            .diaryFont(fontSize, weight: .bold)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Theme.onSurface())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .frame(height: height)
    }
}

struct MiniMonthLabel: View {
    var year: Int
    var month: Int

    var body: some View {
        let thisYear = DateUtil.calendar.component(.year, from: Date())
        let thisMonth = DateUtil.calendar.component(.month, from: Date())
        let isCurrent = year == thisYear && month == thisMonth
        Text(L10n.monthName(month))
            .diaryFont(15, weight: isCurrent ? .bold : .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isCurrent ? Theme.primary() : Theme.onSurface())
    }
}

struct YearPageView: View {
    var year: Int
    var selectedDate: Date
    var flags: Set<String>
    var weekStart: String
    /// 整页的尺寸（含底部可以铺到屏幕底边、被浮条压住的那一段）。
    var containerSize: CGSize
    /// 卡片实际排版用的高度。竖屏它比 `containerSize.height` 小一个浮条高度：
    /// 页铺满屏幕（翻页时邻页不会从底部漏出来），而卡片仍然在浮条之上结束。
    var layoutHeight: CGFloat? = nil
    var hiddenMonth: Int? = nil
    var onSelectMonth: (Int) -> Void

    private var layoutSize: CGSize {
        CGSize(width: containerSize.width, height: layoutHeight ?? containerSize.height)
    }

    var body: some View {
        let card = CalendarLayout.yearCardSize(in: layoutSize)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(L10n.fmt("date_year", year))
                        .diaryFont(TypeSize.display, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.primary())
                    Spacer()
                    if AppLanguage.isZh {
                        let ref = DateUtil.calendar.date(from: DateComponents(year: year, month: 6, day: 1)) ?? Date()
                        Text(Lunar.yearZodiacLabel(ref))
                            .diaryFont(TypeSize.caption)
                            .foregroundStyle(Theme.onSurfaceVariant().opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: CalendarLayout.yearTitleH - 8)
                Divider().padding(.horizontal, 20)
            }
            .frame(height: CalendarLayout.yearTitleH, alignment: .bottom)
            VStack(spacing: CalendarLayout.yearSpacing) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: CalendarLayout.yearSpacing) {
                        ForEach(0..<3, id: \.self) { col in
                            let month = row * 3 + col + 1
                            if hiddenMonth == month {
                                Color.clear
                                    .frame(width: card.width, height: card.height)
                            } else {
                                miniMonth(month: month)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelectMonth(month) }
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, CalendarLayout.yearPad)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .top)
    }

    private func miniMonth(month: Int) -> some View {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let monthDate = DateUtil.calendar.date(from: comps) ?? Date()
        let grid = CalendarLayout.miniGridRect(month: month, in: layoutSize)
        let title = CalendarLayout.miniTitleRect(month: month, in: layoutSize)
        let card = CalendarLayout.yearCardRect(month: month, in: layoutSize)
        let weeks = CalendarLayout.weeks(inMonth: monthDate, ws: weekStart)
        // 标题与网格都用**显式矩形 + offset**（而不是让 VStack 去居中分配）：
        // 「月→年」morph 里的同一张迷你月必须用同样的写法，否则两侧的取整差
        // 1/3pt，morph 收尾换回真实年历时月份数字会挪一下。
        // 这里的 ZStack 是**卡片**，所以用卡片内偏移，不能套容器绝对坐标。
        return ZStack(alignment: .topLeading) {
            MiniMonthLabel(year: year, month: month)
                .frame(width: title.width, height: title.height, alignment: .leading)
                .offset(x: CalendarLayout.miniTitleInCard.x,
                        y: CalendarLayout.miniTitleInCard.y)
            MonthCanvas(weeks: weeks,
                        anchorMonth: monthDate,
                        // 用与「月→年」morph 起点**同一份**参数：此前这里写死
                        // `dayFont: 11`，morph 用的是按格宽推导的 12–14pt，
                        // 于是动画收尾时日期字号会突然缩一下（跳变）。
                        metrics: CalendarLayout.miniMetrics(in: layoutSize),
                        selectedDate: selectedDate,
                        flags: flags,
                        showAdjacent: false,
                        onTapDay: nil)
                .frame(width: grid.width, height: grid.height)
                .offset(x: CalendarLayout.miniGridInCard.x,
                        y: CalendarLayout.miniGridInCard.y)
                .allowsHitTesting(false)
        }
        // 外层 frame 必须显式 `alignment: .topLeading`：ZStack 的自然尺寸比卡片小，
        // 默认居中会把它整体推下去（实测纵向偏 7.5pt），miniPad 偏移就白算了。
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        // The mini months are only a tap gesture, so without this they are
        // invisible to VoiceOver; exposing them also lets UI tests address a
        // specific month deterministically instead of tapping coordinates.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L10n.monthFull(monthDate))
        .accessibilityIdentifier("year.month.\(month)")
    }
}
