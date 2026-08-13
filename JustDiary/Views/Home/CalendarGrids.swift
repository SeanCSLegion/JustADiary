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
                    .font(.system(size: size))
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

    private static let lock = NSLock()
    private static var textCache: [TextKey: GraphicsContext.ResolvedText] = [:]

    private struct TextKey: Hashable {
        var text: String
        var size: CGFloat
        var weight: Int
        var color: Int
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
                     dimAdjacent: Bool) {
        let dayKey = DateUtil.dayKeyOf(day)
        let isSelected = dayKey == selectedKey
        let isToday = dayKey == todayKey
        let isFuture = dayKey > todayKey
        let inMonth = anchorMonth.map { DateUtil.calendar.isDate(day, equalTo: $0, toGranularity: .month) } ?? true
        var cellAlpha = alpha
        if isFuture {
            cellAlpha *= 0.35
        } else if !inMonth {
            cellAlpha *= dimAdjacent ? 0.45 : 1
        }
        guard cellAlpha > 0.01 else { return }

        let lineH = lunarLineH(m)
        let contentH = m.dayFont + 4 + lineH
        let top = rowY + (m.cellH - contentH) / 2
        let numY = top + m.dayFont / 2
        let lunarY = top + m.dayFont + 4 + lineH / 2
        let cx = (CGFloat(col) + 0.5) * m.cellW
        let circleC = top + contentH / 2
        let circleD = min(m.cellW - 2, contentH + 10, m.cellH - 2)

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
        let num = resolvedText(context, "\(dayNum)", size: m.dayFont, weight: isSelected ? 1 : 0, color: colorKey, colorStyle: textColor)
        context.drawLayer { layer in
            layer.opacity = cellAlpha
            layer.draw(num, at: CGPoint(x: cx, y: numY), anchor: .center)
            if lineH > 0.5 {
                let lunar = resolvedText(context, Lunar.dayLabel(day), size: m.lunarFont, weight: 0, color: colorKey,
                                         colorStyle: textColor.opacity(isSelected ? 0.95 : 0.75))
                layer.draw(lunar, at: CGPoint(x: cx, y: lunarY), anchor: .center)
            }
        }

        if flags.contains(dayKey) {
            let w = min(20, m.cellW * 0.5)
            let uy = (lineH > 0.5 ? lunarY + lineH / 2 : numY + m.dayFont / 2) + 3
            let underline = Path(roundedRect: CGRect(x: cx - w / 2, y: uy, width: w, height: 2),
                                 cornerRadius: 1)
            let color: Color = isSelected ? Theme.onPrimary() : Theme.primary()
            context.fill(underline, with: .color(color.opacity(cellAlpha)))
        }
    }

    private static func resolvedText(_ context: GraphicsContext, _ text: String, size: CGFloat, weight: Int, color: Int,
                                     colorStyle: Color) -> GraphicsContext.ResolvedText {
        let quantizedSize = (size * 2).rounded() / 2
        let key = TextKey(text: text, size: quantizedSize, weight: weight, color: color)
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
        if textCache.count > 4000 {
            textCache.removeAll()
        }
        textCache[key] = resolved
        lock.unlock()
        return resolved
    }
}

struct MonthCanvas: View {
    var weeks: [WeekDays]
    var anchorMonth: Date
    var metrics: DayMetrics
    var selectedDate: Date
    var flags: Set<String>
    var showAdjacent: Bool = false
    var onTapDay: ((Date) -> Void)? = nil
    var onAdjacentDaySelected: ((Date) -> Void)? = nil

    var body: some View {
        Canvas { context, _ in
            let todayKey = DateUtil.dayKeyOf(Date())
            let selectedKey = DateUtil.dayKeyOf(selectedDate)
            for (i, week) in weeks.enumerated() {
                let rowY = CGFloat(i) * metrics.cellH
                if metrics.dividerAlpha > 0.01, i > 0 {
                    context.fill(Path(CGRect(x: 0, y: rowY - 0.5, width: metrics.cellW * 7, height: 1)),
                                 with: .color(Theme.outlineVariant().opacity(0.35 * metrics.dividerAlpha)))
                }
                for (col, day) in week.days.enumerated() {
                    if !showAdjacent,
                       !DateUtil.calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month) {
                        continue
                    }
                    DayDraw.draw(context, day: day, col: col, rowY: rowY, m: metrics, alpha: 1,
                                 selectedKey: selectedKey, todayKey: todayKey, flags: flags,
                                 anchorMonth: anchorMonth, dimAdjacent: true)
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
    var week: WeekDays
    var metrics: DayMetrics
    var selectedDate: Date
    var flags: Set<String>
    var alpha: Double = 1
    var showDivider: Bool = false
    var onTapDay: ((Date) -> Void)? = nil

    var body: some View {
        Canvas { context, size in
            let todayKey = DateUtil.dayKeyOf(Date())
            let selectedKey = DateUtil.dayKeyOf(selectedDate)
            if showDivider, metrics.dividerAlpha > 0.01 {
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 1)),
                             with: .color(Theme.outlineVariant().opacity(0.35 * metrics.dividerAlpha * alpha)))
            }
            for (col, day) in week.days.enumerated() {
                DayDraw.draw(context, day: day, col: col, rowY: 0, m: metrics, alpha: alpha,
                             selectedKey: selectedKey, todayKey: todayKey, flags: flags,
                             anchorMonth: nil, dimAdjacent: false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1).onEnded { value in
                guard let onTapDay else { return }
                let col = Int(value.location.x / metrics.cellW)
                guard week.days.indices.contains(col) else { return }
                onTapDay(week.days[col])
            }
        )
    }
}

struct MonthBigTitle: View {
    var month: Date

    var body: some View {
        Text(L10n.monthFull(month))
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(Theme.onSurface())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .frame(height: CalendarLayout.bigTitleH)
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
            .font(.system(size: 15, weight: isCurrent ? .bold : .semibold))
            .foregroundStyle(isCurrent ? Theme.primary() : Theme.onSurface())
    }
}

struct YearPageView: View {
    var year: Int
    var selectedDate: Date
    var flags: Set<String>
    var weekStart: String
    var containerSize: CGSize
    var hiddenMonth: Int? = nil
    var onSelectMonth: (Int) -> Void

    var body: some View {
        let card = CalendarLayout.yearCardSize(in: containerSize)
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.fmt("date_year", year))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.primary())
                Spacer()
                if AppLanguage.isZh {
                    let ref = DateUtil.calendar.date(from: DateComponents(year: year, month: 6, day: 1)) ?? Date()
                    Text(Lunar.yearZodiacLabel(ref))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.onSurfaceVariant().opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .frame(height: CalendarLayout.yearTitleH - 8)
            Divider().padding(.horizontal, 20)
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
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private func miniMonth(month: Int) -> some View {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let monthDate = DateUtil.calendar.date(from: comps) ?? Date()
        let grid = CalendarLayout.miniGridRect(month: month, in: containerSize)
        let weeks = CalendarLayout.weeks(inMonth: monthDate, ws: weekStart)
        return VStack(alignment: .leading, spacing: 0) {
            MiniMonthLabel(year: year, month: month)
                .frame(height: CalendarLayout.miniTitleH, alignment: .leading)
                .padding(.horizontal, CalendarLayout.miniPad)
            MonthCanvas(weeks: weeks,
                        anchorMonth: monthDate,
                        metrics: DayMetrics(cellW: grid.width / 7,
                                            cellH: grid.height / 6,
                                            dayFont: 11,
                                            lunarFont: 6,
                                            lunarAlpha: 0,
                                            dividerAlpha: 0),
                        selectedDate: selectedDate,
                        flags: flags,
                        showAdjacent: false,
                        onTapDay: nil)
                .frame(width: grid.width, height: grid.height)
                .padding(.horizontal, CalendarLayout.miniPad)
                .allowsHitTesting(false)
        }
        .frame(width: grid.width + CalendarLayout.miniPad * 2,
               height: grid.height + CalendarLayout.miniPad * 2 + CalendarLayout.miniTitleH)
    }
}
