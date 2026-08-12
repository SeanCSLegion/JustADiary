import SwiftUI


private enum MorphLog {
    static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("morph_log.txt")
    static func write(_ name: String, _ v: Double) {
        NSLog("MORPHLOG \(name) \(v)")
        let line = "\(ProcessInfo.processInfo.environment["SLOW_MORPH"] ?? "?" ) \(name) \(v)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}

struct HomeView: View {
    var openEditor: (String) -> Void

    init(openEditor: @escaping (String) -> Void) {
        self.openEditor = openEditor
        NSLog("MORPHLOG HomeView.init")
    }

    @State private var selectedDate = Date()
    @State private var monthPage = DateUtil.monthFirst(Date())
    @State private var yearPage = DateUtil.calendar.component(.year, from: Date())
    @State private var mode: CalendarMode = .month
    @State private var zoom: Double = 0
    @State private var ymMorph: (year: Int, month: Date)?
    @State private var expand: Double = 0
    @State private var mwMorphMonth: Date?
    @State private var flags: Set<String> = []
    @State private var dayBlocks: [EditBlock]?
    @State private var showFutureToast = false

    private var weekStart: String { SettingsStore.load().weekStart }
    private var showsLunar: Bool { AppLanguage.isZh }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                calendarArea(size: size)
            }
        }
        .overlay(alignment: .bottom) {
            if showFutureToast {
                Text(L10n.str("index_future_toast"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.onSurface())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .glassEffect(tintedGlass(nil, interactive: true), in: Capsule())
                    }
                    .shadow(color: Theme.shadowColor(), radius: 12, y: 4)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .task { await loadInitial() }
        .onChange(of: zoom) { _, v in MorphLog.write("zoom", v) }
        .onChange(of: expand) { _, v in MorphLog.write("expand", v) }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await loadInitial() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            resetToToday()
        }
    }

    // MARK: - Data

    private func loadInitial() async {
        MorphLog.write("startup", 0)
        let thisYear = DateUtil.calendar.component(.year, from: Date())
        let pageYear = DateUtil.calendar.component(.year, from: monthPage)
        let from = "\(min(thisYear, pageYear) - 1)-01-01"
        let to = "\(max(thisYear, pageYear) + 1)-12-31"
        flags = Set(await DiaryRepository.shared.getDiaryFlagsRange(fromKey: from, toKey: to))
        await reloadDayBlocks()
    }

    private func reloadDayBlocks() async {
        let key = DateUtil.dayKeyOf(selectedDate)
        if let diary = await DiaryRepository.shared.getDiaryByDay(key) {
            dayBlocks = await DiaryRepository.shared.getBlocks(diaryId: diary.id)
        } else {
            dayBlocks = nil
        }
    }

    // MARK: - Header

    private var titleText: String {
        switch mode {
        case .year:
            return L10n.fmt("date_year", yearPage)
        case .month:
            return L10n.fmt("date_year", DateUtil.calendar.component(.year, from: monthPage))
        case .week:
            return L10n.monthFull(monthPage)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                goBack()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(titleText)
                        .font(.system(size: 18, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(Theme.onSurface())
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background {
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .glassEffect(tintedGlass(nil, interactive: true), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .opacity(mode == .year ? 0 : 1)
            .allowsHitTesting(mode != .year)

            Spacer()

            InfoCapsule(text: relativeDayLabel(), action: todayTapped)
        }
        .frame(height: 52)
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    private func relativeDayLabel() -> String {
        let diff = DateUtil.relativeDays(from: selectedDate, to: Date())
        if diff == 0 { return L10n.str("index_today") }
        if diff < 0 { return L10n.fmt("index_days_ago", -diff) }
        return L10n.fmt("index_days_later", diff)
    }

    // MARK: - Transitions

    private var morphing: Bool { ymMorph != nil || mwMorphMonth != nil }

    private func openMonthFromYear(_ month: Int) {
        guard ymMorph == nil else { return }
        Haptics.tap()
        var comps = DateComponents()
        comps.year = yearPage
        comps.month = month
        comps.day = 1
        let monthDate = DateUtil.calendar.date(from: comps) ?? monthPage
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            monthPage = monthDate
            ymMorph = (yearPage, monthDate)
            mode = .month
            zoom = 1
        }
        MorphLog.write("ym-tx", zoom)
        withAnimation(CalendarLayout.morphAnimation) {
            zoom = 0
        }
        MorphLog.write("ym-anim", zoom)
        DispatchQueue.main.asyncAfter(deadline: .now() + CalendarLayout.morphDuration + 0.05) {
            ymMorph = nil
        }
    }

    private func openDay(_ day: Date) {
        guard mwMorphMonth == nil else { return }
        Haptics.tap()
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            selectedDate = day
            monthPage = DateUtil.monthFirst(day)
            mwMorphMonth = monthPage
            mode = .week
            expand = 0
        }
        withAnimation(CalendarLayout.morphAnimation) {
            expand = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CalendarLayout.morphDuration + 0.05) {
            mwMorphMonth = nil
        }
        Task { await reloadDayBlocks() }
    }

    private func goBack() {
        guard !morphing else { return }
        switch mode {
        case .week:
            var tr = Transaction()
            tr.disablesAnimations = true
            withTransaction(tr) {
                monthPage = DateUtil.monthFirst(selectedDate)
                mwMorphMonth = monthPage
                mode = .month
                expand = 1
            }
            withAnimation(CalendarLayout.morphAnimation) {
                expand = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + CalendarLayout.morphDuration + 0.05) {
                mwMorphMonth = nil
            }
        case .month:
            var tr = Transaction()
            tr.disablesAnimations = true
withTransaction(tr) {
            yearPage = DateUtil.calendar.component(.year, from: monthPage)
            ymMorph = (yearPage, monthPage)
            mode = .year
            zoom = 0
        }
        MorphLog.write("my-tx", zoom)
        withAnimation(CalendarLayout.morphAnimation) {
            zoom = 1
        }
        MorphLog.write("my-anim", zoom)
            DispatchQueue.main.asyncAfter(deadline: .now() + CalendarLayout.morphDuration + 0.05) {
                ymMorph = nil
            }
        case .year:
            break
        }
    }

    private func todayTapped() {
        guard !morphing else { return }
        Haptics.tap()
        let now = Date()
        switch mode {
        case .year:
            withAnimation(.snappy(duration: 0.3)) {
                yearPage = DateUtil.calendar.component(.year, from: now)
            }
        case .month:
            withAnimation(.snappy(duration: 0.3)) {
                selectedDate = now
                monthPage = DateUtil.monthFirst(now)
                yearPage = DateUtil.calendar.component(.year, from: now)
            }
            Task { await reloadDayBlocks() }
        case .week:
            withAnimation(.snappy(duration: 0.3)) {
                selectedDate = now
                monthPage = DateUtil.monthFirst(now)
            }
            Task { await reloadDayBlocks() }
        }
    }

    private func resetToToday() {
        ymMorph = nil
        mwMorphMonth = nil
        zoom = 0
        expand = 0
        mode = .month
        selectedDate = Date()
        monthPage = DateUtil.monthFirst(selectedDate)
        yearPage = DateUtil.calendar.component(.year, from: selectedDate)
        Task { await loadInitial() }
    }

    // MARK: - Calendar area

    private func calendarArea(size: CGSize) -> some View {
        let w = size.width
        let h = max(320, size.height - 64)
        return ZStack(alignment: .top) {
            yearLayer(w: w, h: h)
                .opacity(mode == .year && ymMorph == nil ? 1 : 0)
                .allowsHitTesting(mode == .year && ymMorph == nil)
            monthLayer(w: w, h: h)
                .opacity(mode == .month && !morphing ? 1 : 0)
                .allowsHitTesting(mode == .month && !morphing)
            weekLayer(w: w, h: h)
                .opacity(mode == .week && mwMorphMonth == nil ? 1 : 0)
                .allowsHitTesting(mode == .week && mwMorphMonth == nil)
            if let m = ymMorph {
                YearMonthMorphView(progress: zoom,
                                   year: m.year,
                                   month: m.month,
                                   size: CGSize(width: w, height: h),
                                   weekStart: weekStart,
                                   selectedDate: selectedDate,
                                   flags: flags,
                                   showsLunar: showsLunar)
            }
            if let mm = mwMorphMonth {
                MonthWeekMorphView(progress: expand,
                                   month: mm,
                                   selectedDate: selectedDate,
                                   flags: flags,
                                   weekStart: weekStart,
                                   size: CGSize(width: w, height: h),
                                   showsLunar: showsLunar) {
                    dayContentBlock(w: w, h: h)
                }
            }
        }
        .frame(width: w, height: h)
        .clipped()
    }

    private func yearLayer(w: CGFloat, h: CGFloat) -> some View {
        DragPagePager(keys: CalendarLayout.allYears,
                      current: yearPage,
                      axis: .vertical,
                      pageSize: h,
                      disabled: morphing,
                      onPageChange: { yearPage = $0 }) { y in
            YearPageView(year: y,
                         selectedDate: selectedDate,
                         flags: flags,
                         weekStart: weekStart,
                         containerSize: CGSize(width: w, height: h),
                         onSelectMonth: openMonthFromYear)
        }
        .frame(height: h)
    }

    private func monthLayer(w: CGFloat, h: CGFloat) -> some View {
        DragPagePager(keys: CalendarLayout.allMonthKeys,
                      current: CalendarLayout.monthKey(monthPage),
                      axis: .vertical,
                      pageSize: h,
                      disabled: morphing,
                      onPageChange: { key in
            monthPage = CalendarLayout.dateForMonthKey(key)
        }) { key in
            let d = CalendarLayout.dateForMonthKey(key)
            VStack(spacing: 0) {
                MonthBigTitle(month: d)
                WeekdayHeaderView(weekStart: weekStart, cellW: w / 7)
                    .frame(width: w, height: CalendarLayout.weekdayHeaderH)
                MonthCanvas(weeks: CalendarLayout.weeks(inMonth: d, ws: weekStart),
                            anchorMonth: d,
                            metrics: CalendarLayout.monthMetrics(width: w, areaH: h, lunar: showsLunar),
                            selectedDate: selectedDate,
                            flags: flags,
                            showAdjacent: false,
                            onTapDay: openDay)
            }
            .frame(width: w, height: h)
        }
        .frame(height: h)
    }

    private func weekLayer(w: CGFloat, h: CGFloat) -> some View {
        return VStack(spacing: 0) {
            WeekdayHeaderView(weekStart: weekStart, cellW: w / 7)
                .frame(width: w, height: CalendarLayout.weekdayHeaderH)
            DragPagePager(keys: CalendarLayout.allWeekKeys(weekStart: weekStart),
                          current: CalendarLayout.weekKey(selectedDate, ws: weekStart),
                          axis: .horizontal,
                          pageSize: w,
                          disabled: morphing,
                          onPageChange: { key in
                let newStart = CalendarLayout.dateForWeekKey(key)
                let curStart = CalendarLayout.weekStart(of: selectedDate, ws: weekStart)
                let delta = DateUtil.calendar.dateComponents([.day], from: curStart, to: newStart).day ?? 0
                guard delta != 0 else { return }
                selectedDate = DateUtil.addDays(selectedDate, delta)
                monthPage = DateUtil.monthFirst(selectedDate)
                Task { await reloadDayBlocks() }
            }) { key in
                let start = CalendarLayout.dateForWeekKey(key)
                WeekRowCanvas(week: CalendarLayout.weekOf(start, ws: weekStart),
                              metrics: CalendarLayout.weekMetrics(width: w, lunar: showsLunar),
                              selectedDate: selectedDate,
                              flags: flags,
                              onTapDay: { day in
                    Haptics.tap()
                    selectedDate = day
                    monthPage = DateUtil.monthFirst(day)
                    Task { await reloadDayBlocks() }
                })
                .frame(width: w, height: CalendarLayout.weekStripH)
            }
            .frame(width: w, height: CalendarLayout.weekStripH)
            dayContentBlock(w: w, h: h)
        }
        .frame(width: w, height: h)
    }

    private func dayContentBlock(w: CGFloat, h: CGFloat) -> some View {
        let stripBottom = CalendarLayout.weekdayHeaderH + CalendarLayout.weekStripH
        let dayKey = DateUtil.dayKeyOf(selectedDate)
        return VStack(spacing: 0) {
            Divider()
            VStack(spacing: 4) {
                Text(L10n.weekHeaderTitle(selectedDate))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.onSurface())
                if showsLunar {
                    Text(Lunar.fullLabel(selectedDate))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.onSurfaceVariant().opacity(0.8))
                }
            }
            .frame(height: CalendarLayout.dayTitleH)
            Divider()
            DayContentView(blocks: dayBlocks,
                           dayKey: dayKey,
                           isFuture: dayKey > DateUtil.dayKeyOf(Date()),
                           openEditor: openEditor,
                           showFutureToast: { showFutureToast = true })
        }
        .frame(width: w, height: h - stripBottom)
    }
}

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
        set { progress = newValue }
    }

    var body: some View {
        let t = CL.clamp01(1 - progress)
        let monthNum = DateUtil.calendar.component(.month, from: month)
        let miniRect = CalendarLayout.miniGridRect(month: monthNum, in: size)
        let fullRect = CalendarLayout.fullMonthGridRect(in: size)
        let grid = CL.lerp(miniRect, fullRect, t)
        let mini = DayMetrics(cellW: miniRect.width / 7,
                              cellH: miniRect.height / 6,
                              dayFont: 11,
                              lunarFont: 11,
                              lunarAlpha: 0,
                              dividerAlpha: 0)
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
                MonthBigTitle(month: month)
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
        }
        .frame(width: size.width, height: size.height)
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
        set { progress = newValue }
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
        let contentT = CL.clamp01((progress - 0.1) / 0.9)
        return ZStack(alignment: .top) {
            MonthBigTitle(month: month)
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
                .offset(y: CL.lerp(size.height, stripBottom, contentT))
                .opacity(CL.clamp01((progress - 0.25) / 0.75))
        }
        .frame(width: size.width, height: size.height)
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
                             onTapDay: nil)
            .frame(width: size.width, height: metrics.cellH)
            .offset(y: y)
    }
}
