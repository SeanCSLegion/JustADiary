import SwiftUI

struct HomeView: View {
    var openEditor: (String) -> Void

    @State private var selectedDate = Date()
    @State private var monthPage = DateUtil.monthFirst(Date())
    @State private var yearPage: Int? = DateUtil.calendar.component(.year, from: Date())
    @State private var yearMode = false
    @State private var pageID: Int? = 1
    @State private var flags: Set<String> = []
    @State private var cardInfo: DiaryCardInfo?
    @State private var cardLoading = false
    @State private var showFutureToast = false

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header(geo: geo)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    calendarArea(geo: geo)
                        .padding(.horizontal, 16)
                    if !yearMode {
                        diaryCardArea(geo: geo)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            }
            .animation(.easeOut(duration: 0.36), value: yearMode)
        }
        .overlay(alignment: .bottom) {
            if showFutureToast {
                Text(L10n.str("index_future_toast"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }
        }
        .task { await loadInitial() }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await reloadFlagsAndCard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            yearMode = false
            monthPage = DateUtil.monthFirst(Date())
            selectedDate = Date()
            Task { await reloadFlagsAndCard() }
        }
    }

    // MARK: - Data

    private func loadInitial() async {
        await reloadFlagsAndCard()
    }
    private func reloadFlagsAndCard() async {
        let thisYear = DateUtil.calendar.component(.year, from: Date())
        let pageYear = DateUtil.calendar.component(.year, from: monthPage)
        let from = "\(min(thisYear, pageYear) - 1)-01-01"
        let to = "\(max(thisYear, pageYear) + 1)-12-31"
        let all = await DiaryRepository.shared.getDiaryFlagsRange(fromKey: from, toKey: to)
        flags = Set(all)
        let key = DateUtil.dayKeyOf(selectedDate)
        cardInfo = await DiaryRepository.shared.getDiaryCardInfo(dayKey: key)
        cardLoading = false
    }

    private func dayKey(_ date: Date) -> String {
        DateUtil.dayKeyOf(date)
    }

    private func reloadCard() {
        cardLoading = true
        Task {
            cardInfo = await DiaryRepository.shared.getDiaryCardInfo(dayKey: dayKey(selectedDate))
            cardLoading = false
        }
    }

    // MARK: - Header

    private func header(geo: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.36)) {
                    yearMode.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    ZStack {
                        Text(L10n.monthTitle(monthPage))
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(Theme.onSurface())
                            .opacity(yearMode ? 0 : 1)
                        Text(L10n.yearTitle(yearPage ?? DateUtil.calendar.component(.year, from: monthPage)))
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(Theme.onSurface())
                            .opacity(yearMode ? 1 : 0)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .rotationEffect(.degrees(yearMode ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            InfoCapsule(text: relativeDayLabel(), action: {
                selectDate(Date())
            })

            Spacer()

            HStack(spacing: 6) {
                pageButton(systemName: "chevron.left", action: {
                    if yearMode {
                        shiftYear(-1)
                    } else {
                        shiftMonth(-1)
                    }
                })
                pageButton(systemName: "chevron.right", action: {
                    if yearMode {
                        shiftYear(1)
                    } else {
                        shiftMonth(1)
                    }
                })
            }
        }
        .frame(height: 52)
    }

    private func pageButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.onSurface())
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular, in: Circle())
                }
        }
        .buttonStyle(.plain)
    }

    private func relativeDayLabel() -> String {
        let diff = DateUtil.relativeDays(from: selectedDate, to: Date())
        if diff == 0 { return L10n.str("index_today") }
        if diff < 0 { return L10n.fmt("index_days_ago", -diff) }
        return L10n.fmt("index_days_later", diff)
    }

    private func shiftMonth(_ delta: Int) {
        monthPage = DateUtil.monthFirst(DateUtil.addMonths(monthPage, delta))
        selectedDate = clampToMonth(selectedDate, month: monthPage)
        reloadCard()
    }

    private func shiftYear(_ delta: Int) {
        let current = yearPage ?? DateUtil.calendar.component(.year, from: Date())
        yearPage = current + delta
        selectedDate = clampToMonth(selectedDate, month: monthPage)
        reloadCard()
    }

    private func selectDate(_ date: Date) {
        Haptics.tap()
        selectedDate = date
        monthPage = DateUtil.monthFirst(date)
        reloadCard()
    }

    private func clampToMonth(_ date: Date, month: Date) -> Date {
        let day = DateUtil.calendar.component(.day, from: date)
        let days = DateUtil.daysInMonth(month)
        var comps = DateUtil.calendar.dateComponents([.year, .month], from: month)
        comps.day = min(day, days)
        return DateUtil.calendar.date(from: comps) ?? month
    }

    // MARK: - Calendar area

    private func calendarArea(geo: GeometryProxy) -> some View {
        ZStack {
            monthLayer(geo: geo)
                .opacity(yearMode ? 0 : 1)
                .scaleEffect(yearMode ? 0.94 : 1)
                .offset(y: yearMode ? -12 : 0)

            yearLayer(geo: geo)
                .scaleEffect(yearMode ? 1 : yearZoom(geo: geo), anchor: .topLeading)
                .offset(x: yearMode ? 0 : yearOffsetX(geo: geo),
                        y: yearMode ? 0 : yearOffsetY(geo: geo))
                .opacity(yearMode ? 1 : 0)
                .allowsHitTesting(yearMode)
        }
        .frame(height: yearMode ? 520 : 330)
    }

    private func yearZoom(geo: GeometryProxy) -> CGFloat {
        let calWidth = geo.size.width - 32
        let cardW = (calWidth - 4 - 16) / 3
        return max(1, calWidth / cardW)
    }

    private func yearOffsetX(geo: GeometryProxy) -> CGFloat {
        let calWidth = geo.size.width - 32
        let month = DateUtil.calendar.component(.month, from: selectedDate) - 1
        let col = CGFloat(month % 3)
        let centerX = col * ((calWidth - 4 - 16) / 3 + 8) + (calWidth - 4 - 16) / 3 / 2
        return (calWidth / 2) - yearZoom(geo: geo) * centerX
    }

    private func yearOffsetY(geo: GeometryProxy) -> CGFloat {
        let cardH = (520.0 - 3 * 8 - 4) / 4
        let month = DateUtil.calendar.component(.month, from: selectedDate) - 1
        let row = CGFloat(month / 3)
        let centerY = row * (cardH + 8) + cardH / 2
        return (330.0 / 2) - yearZoom(geo: geo) * centerY
    }

    private func monthLayer(geo: GeometryProxy) -> some View {
        let ids = [monthPageKey(monthPage, -1), monthPageKey(monthPage, 0), monthPageKey(monthPage, 1)]
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(ids, id: \.self) { id in
                    let monthDate = dateForMonthKey(id)
                    MonthGridCanvas(month: monthDate,
                                    selectedDate: selectedDate,
                                    flags: flags,
                                    isZh: AppLanguage.isZh,
                                    onSelect: { day in
                        var comps = DateUtil.calendar.dateComponents([.year, .month], from: monthDate)
                        comps.day = day
                        if let date = DateUtil.calendar.date(from: comps) {
                            selectDate(date)
                        }
                    })
                    .frame(width: geo.size.width - 32)
                    .id(id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pageID, anchor: .center)
        .scrollDisabled(yearMode)
        .onChange(of: pageID) { _, newID in
            guard let newID, newID != 1 else { return }
            let delta = newID == 0 ? -1 : 1
            monthPage = DateUtil.monthFirst(DateUtil.addMonths(monthPage, delta))
            selectedDate = clampToMonth(selectedDate, month: monthPage)
            pageID = 1
            reloadCard()
        }
        .frame(height: 330)
        .background {
            GlassCapsule(cornerRadius: 26, blur: 26)
        }
    }

    private func monthPageKey(_ month: Date, _ delta: Int) -> Int {
        let target = DateUtil.addMonths(month, delta)
        let m = DateUtil.calendar.component(.month, from: target)
        let y = DateUtil.calendar.component(.year, from: target)
        return y * 100 + m
    }

    private func dateForMonthKey(_ key: Int) -> Date {
        let y = key / 100
        let m = key % 100
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = 1
        return DateUtil.calendar.date(from: comps) ?? monthPage
    }

    private func yearLayer(geo: GeometryProxy) -> some View {
        let year = yearPage ?? DateUtil.calendar.component(.year, from: Date())
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach([year - 1, year, year + 1], id: \.self) { y in
                    YearGrid(year: y,
                             selectedDate: selectedDate,
                             flags: flags,
                             weekStart: SettingsStore.load().weekStart,
                             onSelectMonth: { month in
                        var comps = DateComponents()
                        comps.year = y
                        comps.month = month
                        comps.day = 1
                        guard let date = DateUtil.calendar.date(from: comps) else { return }
                        selectDate(date)
                        withAnimation(.easeOut(duration: 0.36)) {
                            yearMode = false
                        }
                    })
                    .frame(width: geo.size.width - 32)
                    .id(y)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $yearPage, anchor: .center)
        .onChange(of: yearPage) { _, newID in
            guard let newID else { return }
            let year = yearPage ?? DateUtil.calendar.component(.year, from: Date())
            if newID != year {
                yearPage = newID
                reloadCard()
            }
        }
        .frame(height: 520)
        .background {
            GlassCapsule(cornerRadius: 26, blur: 26)
        }
    }

    // MARK: - Diary card

    private func diaryCardArea(geo: GeometryProxy) -> some View {
        Group {
            if let card = cardInfo {
                if card.hasDiary {
                    DiaryCardView(card: card, todayKey: dayKey(Date()), action: {
                        openEditor(dayKey(selectedDate))
                    })
                } else {
                    EmptyDiaryCardView(isFuture: selectedDate > DateUtil.startOfDay(Date()),
                                       action: {
                        openEditor(dayKey(selectedDate))
                    })
                }
            } else if cardLoading {
                ProgressView()
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            } else {
                EmptyDiaryCardView(isFuture: false, action: {
                    openEditor(dayKey(selectedDate))
                })
            }
        }
        .frame(height: 100)
    }
}

struct MonthGridCanvas: View {
    var month: Date
    var selectedDate: Date
    var flags: Set<String>
    var isZh: Bool
    var onSelect: (Int) -> Void

    private let headerH = 26.0
    private let cellH = (330.0 - 26.0 - 22.0) / 6
    private let topPad = 12.0

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let cellW = size.width / 7
                let weekdayNames = L10n.weekdayNames(weekStart: SettingsStore.load().weekStart)
                let weekStart = SettingsStore.load().weekStart
                for (i, name) in weekdayNames.enumerated() {
                    let isWeekend = (weekStart == "sunday" ? i : i + 1) % 7 >= 5
                    let color = isWeekend ? Theme.primary() : Theme.onSurfaceVariant()
                    let x = Double(i) * cellW + cellW / 2
                    let y = topPad + 13
                    drawCenteredText(context, text: name, at: CGPoint(x: x, y: y), fontSize: 11, color: color)
                }
                let first = DateUtil.calendar.dateComponents([.year, .month, .day], from: month)
                guard let firstDay = DateUtil.calendar.date(from: DateComponents(year: first.year, month: first.month, day: 1)) else { return }
                let lead = DateUtil.weekdayIndex(firstDay, weekStart: weekStart)
                let days = DateUtil.daysInMonth(month)
                let todayKey = DateUtil.dayKeyOf(Date())
                let selectedKey = DateUtil.dayKeyOf(selectedDate)
                let selectedMonth = DateUtil.calendar.component(.month, from: selectedDate)
                for day in 1...days {
                    let index = lead + day - 1
                    let row = index / 7
                    let col = index % 7
                    guard row < 6 else { continue }
                    let cx = Double(col) * cellW + cellW / 2
                    let cy = topPad + headerH + Double(row) * cellH + cellH / 2
                    let dayKey = String(format: "%04d-%02d-%02d", first.year ?? 0, first.month ?? 0, day)
                    let isSelected = dayKey == selectedKey
                    let isToday = dayKey == todayKey
                    let isFuture = dayKey > todayKey
                    let hasDiary = flags.contains(dayKey)
                    if isSelected {
                        let rect = CGRect(x: cx - cellW / 2 + 3, y: cy - cellH / 2 + 3, width: cellW - 6, height: cellH - 6)
                        context.fill(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 16),
                                     with: .color(Theme.glowColor()))
                        context.fill(Path(roundedRect: rect, cornerRadius: 16),
                                     with: .color(Theme.primary()))
                    } else if isToday {
                        let rect = CGRect(x: cx - cellW / 2 + 3, y: cy - cellH / 2 + 3, width: cellW - 6, height: cellH - 6)
                        let path = Path(roundedRect: rect, cornerRadius: 16)
                        context.stroke(path, with: .color(Theme.primary()), lineWidth: 1)
                    }
                    let textColor: Color
                    if isSelected {
                        textColor = Theme.onPrimary()
                    } else if isToday {
                        textColor = Theme.primary()
                    } else if selectedMonth == first.month {
                        textColor = Theme.onSurface()
                    } else {
                        textColor = Theme.onSurface().opacity(0.4)
                    }
                    var alpha = 1.0
                    if isFuture { alpha = AppLanguage.isZh ? 0.32 : 0.42 }
                    drawCenteredText(context, text: "\(day)", at: CGPoint(x: cx, y: cy - 4),
                                     fontSize: 15, color: textColor.opacity(alpha))
                    if hasDiary {
                        context.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy + 8, width: 4, height: 4)),
                                     with: .color(isSelected ? Theme.onPrimary() : Theme.primary().opacity(alpha)))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 1)
                    .onEnded { value in
                        if let day = dayAt(point: value.location, width: geo.size.width) {
                            onSelect(day)
                        }
                    }
            )
        }
    }

    private func dayAt(point: CGPoint, width: Double) -> Int? {
        let cellW = width / 7
        guard point.x >= 0, point.x < width else { return nil }
        let col = Int(point.x / cellW)
        let row = Int((point.y - topPad - headerH) / cellH)
        guard col >= 0, col < 7, row >= 0, row < 6 else { return nil }
        let index = row * 7 + col
        let lead = DateUtil.weekdayIndex(DateUtil.monthFirst(month), weekStart: SettingsStore.load().weekStart)
        let day = index - lead + 1
        guard day >= 1, day <= DateUtil.daysInMonth(month) else { return nil }
        return day
    }

    private func drawCenteredText(_ context: GraphicsContext, text: String, at point: CGPoint,
                                  fontSize: CGFloat, color: Color) {
        let resolved = context.resolve(Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(color))
        context.draw(resolved, at: point, anchor: .center)
    }
}

struct YearGrid: View {
    var year: Int
    var selectedDate: Date
    var flags: Set<String>
    var weekStart: String
    var onSelectMonth: (Int) -> Void

    var body: some View {
        let selectedYear = DateUtil.calendar.component(.year, from: selectedDate)
        let selectedMonth = DateUtil.calendar.component(.month, from: selectedDate)
        let thisYear = DateUtil.calendar.component(.year, from: Date())
        let thisMonth = DateUtil.calendar.component(.month, from: Date())
        return VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { col in
                        let month = row * 3 + col + 1
                        Button {
                            Haptics.tap()
                            onSelectMonth(month)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(L10n.monthName(month))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.onSurface())
                                    if year == thisYear, month == thisMonth {
                                        Circle()
                                            .fill(Theme.primary())
                                            .frame(width: 6, height: 6)
                                    }
                                    Spacer()
                                }
                                YearMiniCanvas(month: month, year: year,
                                               selectedDate: selectedDate,
                                               flags: flags)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selectedYear == year && selectedMonth == month
                                          ? Theme.primaryContainer() : Theme.surface1())
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(selectedYear == year && selectedMonth == month
                                                    ? Theme.primary() : Theme.outlineVariant(), lineWidth: selectedYear == year && selectedMonth == month ? 1.5 : 1)
                                    }
                                    .shadow(color: selectedYear == year && selectedMonth == month ? Theme.glowColor() : .clear,
                                            radius: 14, y: 4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(2)
        .frame(height: 520)
        .allowsHitTesting(true)
    }
}

struct YearMiniCanvas: View {
    var month: Int
    var year: Int
    var selectedDate: Date
    var flags: Set<String>

    var body: some View {
        Canvas { context, size in
            let cellW = size.width / 7
            let cellH = size.height / 6
            guard let firstDay = DateUtil.calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }
            let lead = DateUtil.weekdayIndex(firstDay, weekStart: SettingsStore.load().weekStart)
            let days = DateUtil.daysInMonth(firstDay)
            let selectedKey = DateUtil.dayKeyOf(selectedDate)
            let todayKey = DateUtil.dayKeyOf(Date())
            for day in 1...days {
                let index = lead + day - 1
                let row = index / 7
                let col = index % 7
                guard row < 6 else { continue }
                let cx = Double(col) * cellW + cellW / 2
                let cy = Double(row) * cellH + cellH / 2
                let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
                let isSelected = dayKey == selectedKey
                let isToday = dayKey == todayKey
                if isSelected {
                    context.fill(Path(roundedRect: CGRect(x: cx - 9, y: cy - 7, width: 18, height: 14), cornerRadius: 7),
                                 with: .color(Theme.primary()))
                } else if isToday {
                    context.stroke(Path(roundedRect: CGRect(x: cx - 9, y: cy - 7, width: 18, height: 14), cornerRadius: 7),
                                   with: .color(Theme.primary()), lineWidth: 1)
                }
                let color: Color = isSelected ? Theme.onPrimary() : (isToday ? Theme.primary() : Theme.onSurface())
                let resolved = context.resolve(Text("\(day)").font(.system(size: 9)).foregroundStyle(color))
                context.draw(resolved, at: CGPoint(x: cx, y: cy - 4), anchor: .center)
                if flags.contains(dayKey) {
                    context.fill(Path(ellipseIn: CGRect(x: cx - 1.4, y: cy + 8, width: 2.8, height: 2.8)),
                                 with: .color(isSelected ? Theme.onPrimary() : Theme.primary()))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct DiaryCardView: View {
    var card: DiaryCardInfo
    var todayKey: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack(alignment: .topLeading) {
                FlowLightOverlay()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(card.dayKey == todayKey ? L10n.str("index_card_today") : L10n.formatDayKey(card.dayKey))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.onSurface())
                        Spacer()
                        Text(L10n.str("index_written"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.primary()))
                            .shadow(color: Theme.glowColor(), radius: 6, y: 1)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(L10n.timeOf(card.startTimeUtc))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.onSurfaceVariant())
                    if !card.locText.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11))
                            Text(card.locText)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.onSurfaceVariant())
                    }
                    Text(card.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.onSurface())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .scaleEffect(0.98)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyDiaryCardView: View {
    var isFuture: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            if !isFuture {
                action()
            }
        } label: {
            VStack(spacing: 6) {
                Text(L10n.str("index_write"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.primary())
                Text(isFuture ? L10n.str("index_future_empty") : L10n.str("index_day_empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }
}
