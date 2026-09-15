import SwiftUI

struct HomeView: View {
    var openEditor: (String) -> Void

    init(openEditor: @escaping (String) -> Void) {
        self.openEditor = openEditor
    }

    @State private var vm = HomeViewModel()
    @State private var mode: CalendarMode = .month
    @State private var zoom: Double = 0
    @State private var ymMorph: (year: Int, month: Date)?
    @State private var expand: Double = 0
    @State private var mwMorphMonth: Date?
    @State private var showFutureToast = false
    @State private var futureToastTask: Task<Void, Never>?

    private var weekStart: String { vm.weekStart }
    private var showsLunar: Bool { AppLanguage.isZh }
    private var selectedDate: Date { vm.selectedDate }
    private var flags: Set<String> { vm.flags }

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
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            if showFutureToast {
                Text(L10n.str("index_future_toast"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.onSurface())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule().fill(Color(.secondarySystemGroupedBackground))
                    }
                    .shadow(color: Theme.shadowColor(), radius: 12, y: 4)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .sensoryFeedback(.warning, trigger: showFutureToast)
            }
        }
        .task { await vm.loadInitial() }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await vm.loadInitial() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            vm.refreshSettings()
            resetToToday()
        }
    }

    // MARK: - Header

    private var titleText: String {
        switch mode {
        case .year:
            return L10n.fmt("date_year", vm.yearPage)
        case .month:
            return L10n.fmt("date_year", DateUtil.calendar.component(.year, from: vm.monthPage))
        case .week:
            return L10n.monthFull(vm.monthPage)
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
                    Capsule().fill(Color(.secondarySystemGroupedBackground))
                }
            }
            .buttonStyle(.plain)
            .opacity(mode == .year ? 0 : 1)
            .allowsHitTesting(mode != .year)
            .animation(.diaryStandard, value: mode)

            Spacer()

            InfoCapsule(text: relativeDayLabel(), action: todayTapped)
        }
        .frame(height: 52)
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
        comps.year = vm.yearPage
        comps.month = month
        comps.day = 1
        let monthDate = DateUtil.calendar.date(from: comps) ?? vm.monthPage
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            vm.selectMonth(monthDate)
            ymMorph = (vm.yearPage, monthDate)
            mode = .month
            zoom = 1
        }
        withAnimation(CalendarLayout.morphAnimation) {
            zoom = 0
        } completion: {
            ymMorph = nil
        }
    }

    private func openDay(_ day: Date) {
        guard mwMorphMonth == nil else { return }
        Haptics.tap()
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            vm.select(day)
            mwMorphMonth = vm.monthPage
            mode = .week
            expand = 0
        }
        withAnimation(CalendarLayout.morphSlideAnimation) {
            expand = 1
        } completion: {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-morph-log") {
                MorphProgressLog.shared.append("completion-open")
            }
            #endif
            mwMorphMonth = nil
        }
        Task { await vm.reloadDayBlocks() }
    }

    private func goBack() {
        guard !morphing else { return }
        switch mode {
        case .week:
            var tr = Transaction()
            tr.disablesAnimations = true
            withTransaction(tr) {
                vm.selectMonth(DateUtil.monthFirst(selectedDate))
                mwMorphMonth = vm.monthPage
                mode = .month
                expand = 1
            }
            withAnimation(CalendarLayout.morphSlideAnimation) {
                expand = 0
            } completion: {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-morph-log") {
                    MorphProgressLog.shared.append("completion-back")
                }
                #endif
                mwMorphMonth = nil
            }
        case .month:
            var tr = Transaction()
            tr.disablesAnimations = true
            withTransaction(tr) {
                vm.yearPage = DateUtil.calendar.component(.year, from: vm.monthPage)
                ymMorph = (vm.yearPage, vm.monthPage)
                mode = .year
                zoom = 0
            }
            withAnimation(CalendarLayout.morphAnimation) {
                zoom = 1
            } completion: {
                ymMorph = nil
            }
        case .year:
            break
        }
    }

    private func todayTapped() {
        guard !morphing else { return }
        let now = Date()
        switch mode {
        case .year:
            vm.resetToToday()
            openMonthFromYear(DateUtil.calendar.component(.month, from: now))
        case .month:
            Haptics.tap()
            withAnimation(.snappy(duration: 0.3)) {
                vm.resetToToday()
            }
            Task { await vm.reloadDayBlocks() }
        case .week:
            Haptics.tap()
            withAnimation(.snappy(duration: 0.3)) {
                vm.select(now)
            }
            Task { await vm.reloadDayBlocks() }
        }
    }

    private func resetToToday() {
        ymMorph = nil
        mwMorphMonth = nil
        zoom = 0
        expand = 0
        mode = .month
        vm.resetToToday()
        Task { await vm.loadInitial() }
    }

    private func showFutureDateToast() {
        futureToastTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) {
            showFutureToast = true
        }
        futureToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) {
                showFutureToast = false
            }
        }
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
                      current: vm.yearPage,
                      axis: .vertical,
                      pageSize: h,
                      disabled: morphing,
                      onPageChange: { vm.yearPage = $0 }) { y in
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
                      current: CalendarLayout.monthKey(vm.monthPage),
                      axis: .vertical,
                      pageSize: h,
                      disabled: morphing,
                      onPageChange: { key in
            vm.selectMonth(CalendarLayout.dateForMonthKey(key))
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
                            onTapDay: openDay,
                            onAdjacentDaySelected: openDay)
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
                vm.select(DateUtil.addDays(selectedDate, delta))
                Task { await vm.reloadDayBlocks() }
            }) { key in
                let start = CalendarLayout.dateForWeekKey(key)
                WeekRowCanvas(week: CalendarLayout.weekOf(start, ws: weekStart),
                              metrics: CalendarLayout.weekMetrics(width: w, lunar: showsLunar),
                              selectedDate: selectedDate,
                              flags: flags,
                              onTapDay: { day in
                    Haptics.tap()
                    vm.select(day)
                    Task { await vm.reloadDayBlocks() }
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
            HStack(spacing: 12) {
                Text(L10n.weekHeaderTitle(selectedDate))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onSurface())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if showsLunar {
                    Text(Lunar.fullLabel(selectedDate))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.onSurfaceVariant().opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: CalendarLayout.dayTitleH)
            Divider()
            DayContentView(blocks: vm.dayBlocks,
                           dayKey: dayKey,
                           isFuture: dayKey > DateUtil.dayKeyOf(Date()),
                           openEditor: openEditor,
                           openDiary: openEditor,
                           showFutureToast: showFutureDateToast)
        }
        .frame(width: w, height: h - stripBottom)
    }
}
