import SwiftUI

struct HomeView: View {
    var openEditor: (String) -> Void

    init(openEditor: @escaping (String) -> Void) {
        self.openEditor = openEditor
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.adaptiveLayout) private var layout

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
                // 横屏分栏时头部整块隐藏：年份入口与「今天」都在左栏标题行里，
                // 留着就会出现两个年份胶囊。
                if !(layout.splitsMasterDetail && mode == .month) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                if layout.splitsMasterDetail, mode == .month {
                    splitCalendarArea(size: size)
                } else {
                    // 横屏点年份胶囊进年历：复用竖屏那套整屏 morph（此时不显示分栏）
                    calendarArea(size: size)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            if showFutureToast {
                Text(L10n.str("index_future_toast"))
                    .diaryFont(TypeSize.meta)
                    .foregroundStyle(Theme.onSurface())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        // A transient surface floating above the calendar: the
                        // control layer, so it is glass rather than an opaque
                        // capsule.
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule())
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
                        .diaryFont(16, weight: .semibold)
                    Text(titleText)
                        .diaryFont(TypeSize.headerTitle, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(Theme.onSurface())
                .padding(.horizontal, 14)
                .frame(minHeight: Spacing.hitTarget)
                .background {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(true), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.header.back")
            .opacity(mode == .year ? 0 : 1)
            .allowsHitTesting(mode != .year)
            .animation(.diaryStandard, value: mode)

            Spacer()

            // 横屏分栏时右栏标题行已有「今天」，这里不再重复一个相对日期胶囊。
            if !layout.splitsMasterDetail {
                InfoCapsule(text: relativeDayLabel(), action: todayTapped)
            }
        }
        // `height` clipped the capsule once the title grew with the user's
        // text size; `minHeight` is unchanged at the default category.
        .frame(minHeight: 52)
    }

    private func relativeDayLabel() -> String {
        L10n.relativeDayLabel(from: selectedDate, to: Date())
    }

    // MARK: - Transitions

    private var morphing: Bool { ymMorph != nil || mwMorphMonth != nil }

    /// With 减弱动态效果 enabled the calendar still switches, but the geometry
    /// travels only briefly instead of sweeping across the screen.
    private var zoomAnimation: Animation {
        reduceMotion ? CalendarLayout.reducedMorphAnimation : CalendarLayout.morphAnimation
    }

    private var slideAnimation: Animation {
        reduceMotion ? CalendarLayout.reducedMorphAnimation : CalendarLayout.morphSlideAnimation
    }

    /// DEBUG-only marker for the `-morph-log` frame-timing harness.
    private func morphLog(_ marker: String) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-morph-log") {
            MorphProgressLog.shared.append(marker)
        }
        #endif
    }

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
        morphLog("ym-open-start")
        withAnimation(zoomAnimation) {
            zoom = 0
        } completion: {
            morphLog("ym-open-end")
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
        morphLog("mw-open-start")
        withAnimation(slideAnimation) {
            expand = 1
        } completion: {
            morphLog("mw-open-end")
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
            morphLog("mw-back-start")
            withAnimation(slideAnimation) {
                expand = 0
            } completion: {
                morphLog("mw-back-end")
                mwMorphMonth = nil
            }
        case .month:
            showYearPage()
        case .year:
            break
        }
    }

    /// 切到年历（缩放 morph）。竖屏的左上角胶囊与横屏左栏的年份胶囊都走这里。
    private func showYearPage() {
        guard !morphing else { return }
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            vm.yearPage = DateUtil.calendar.component(.year, from: vm.monthPage)
            ymMorph = (vm.yearPage, vm.monthPage)
            mode = .year
            zoom = 0
        }
        morphLog("ym-back-start")
        withAnimation(zoomAnimation) {
            zoom = 1
        } completion: {
            morphLog("ym-back-end")
            ymMorph = nil
        }
    }

    /// 从年历点某个月回来（缩放 morph）。
    private func showMonthPage() {
        guard !morphing else { return }
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            vm.selectMonth(DateUtil.monthFirst(selectedDate))
            ymMorph = (vm.yearPage, vm.monthPage)
            mode = .month
            zoom = 1
        }
        morphLog("ym-open-start")
        withAnimation(zoomAnimation) {
            zoom = 0
        } completion: {
            morphLog("ym-open-end")
            ymMorph = nil
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

    /// 横屏（宽度足够）走「左月历 + 右选中日」的静态分栏。
    ///
    /// 竖屏**不经过这里** —— 年 ↔ 月 ↔ 周三态与 morph 动画保持原样。
    private func splitCalendarArea(size: CGSize) -> some View {
        // 系统占位由 safeArea 提供（横屏 leading = 62，浮条与灵动岛都在左侧）；
        // 页面自己的边距统一 16pt，四屏一致。
        let inset = layout.contentInset
        let pagePad: CGFloat = 16
        let top: CGFloat = 50
        let bottom = layout.bottomInset + 8
        // 内容可用宽 = 屏宽 − 左侧系统占位；再扣掉两侧 16pt 页面边距。
        let paneW = size.width - inset
        let shapeW = max(320, paneW - pagePad * 2)
        // 月历 7 列每格 ≈56pt（好点、不挤），其余给右栏（本机约 330pt）。
        let calendarW = min(shapeW - 280, min(420, max(360, (shapeW * 0.52).rounded())))
        let dayW = shapeW - calendarW - pagePad * 2
        let paneH = size.height - top
        let areaH = max(220, paneH - bottom)

        let weeks = CalendarLayout.displayedWeeks(inMonth: vm.monthPage, ws: weekStart).count
        // 横屏标题区是紧凑的「年份+今天」一行 + 月标题一行
        let titleAndHeader = MonthPane.titleBlockHeight(compact: true)
            + CalendarLayout.weekdayHeaderH
        let density = CalendarDensity.resolve(availableHeight: areaH - titleAndHeader,
                                               rows: weeks,
                                               wantsLunar: showsLunar)
        let rows = density.rows(monthWeeks: weeks)
        let cellH = max(CalendarDensity.minimumRowHeight,
                        (areaH - titleAndHeader) / CGFloat(rows).rounded())
        return HStack(alignment: .top, spacing: pagePad * 2) {
            // 月历：**上下滑**翻月（与竖屏一致，横屏不引入第二套手势方向）；
            // 每页只画当前月，不显示相邻月的日期。
            DragPagePager(keys: CalendarLayout.allMonthKeys,
                          current: CalendarLayout.monthKey(vm.monthPage),
                          axis: .vertical,
                          pageSize: areaH,
                          disabled: false,
                          onPageChange: { key in
                withAnimation(.snappy(duration: 0.3)) {
                    vm.selectMonth(CalendarLayout.dateForMonthKey(key))
                }
                Task { await vm.reloadDayBlocks() }
            }) { key in
                MonthPane(month: CalendarLayout.dateForMonthKey(key),
                          weekStart: weekStart,
                          selectedDate: selectedDate,
                          flags: flags,
                          width: calendarW,
                          areaH: areaH,
                          cellH: cellH,
                          density: density,
                          // 「今天」与年份入口都放在左栏标题行 —— 横屏的唯一入口。
                          showsTodayChip: true,
                          onTodayTap: todayTapped,
                          onTapDay: selectDay)
                    .frame(width: calendarW, height: areaH)
            }
            .frame(width: calendarW, height: areaH)
            .clipped()

            Rectangle()
                .fill(Theme.outlineVariant().opacity(0.4))
                .frame(width: 0.5)

            // 右栏：固定宽度，内容限宽并居中（正文一行不超过 ~40 汉字）
            DayPane(blocks: vm.dayBlocks,
                    dayKey: DateUtil.dayKeyOf(selectedDate),
                    isFuture: DateUtil.dayKeyOf(selectedDate) > DateUtil.dayKeyOf(Date()),
                    openEditor: openEditor,
                    bottomInset: layout.bottomInset,
                    maxColumnWidth: 560,
                    year: DateUtil.calendar.component(.year, from: vm.monthPage),
                    onYearTap: showYearPage)
                .frame(width: dayW)
        }
        .padding(.leading, inset + pagePad)
        .padding(.trailing, pagePad)
        .frame(width: paneW, height: paneH, alignment: .topLeading)
        .clipped()
    }

    private func calendarArea(size: CGSize) -> some View {
        let w = size.width
        let h = max(320, size.height - 64)
        // While a morph runs, all three base layers sit at opacity 0 — but an
        // opacity-0 view is still built and still re-evaluated on every
        // animation frame. Each layer wraps a DragPagePager that eagerly builds
        // three pages, so the hidden year layer alone costs 3 x 12 = 36 month
        // canvases per frame. Skip them entirely while morphing; the morph view
        // is the only thing that needs to be on screen.
        return ZStack(alignment: .top) {
            if !morphing {
                yearLayer(w: w, h: h)
                    .opacity(mode == .year ? 1 : 0)
                    .allowsHitTesting(mode == .year)
                monthLayer(w: w, h: h)
                    .opacity(mode == .month ? 1 : 0)
                    .allowsHitTesting(mode == .month)
                weekLayer(w: w, h: h)
                    .opacity(mode == .week ? 1 : 0)
                    .allowsHitTesting(mode == .week)
            }
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
            MonthPane(month: CalendarLayout.dateForMonthKey(key),
                      weekStart: weekStart,
                      selectedDate: selectedDate,
                      flags: flags,
                      width: w,
                      areaH: h,
                      cellH: CalendarLayout.monthCellH(areaH: h),
                      density: showsLunar ? .month(lunar: true) : .month(lunar: false),
                      // 竖屏顶部已经有 InfoCapsule(今天 + 相对日期)，这里不再重复。
                      showsTodayChip: false,
                      onTapDay: openDay)
        }
        .frame(height: h)
    }

    /// 点某个日期：横屏只更新选中日（不进入周视图），竖屏走原来的 morph。
    private func selectDay(_ day: Date) {
        if layout.splitsMasterDetail {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { vm.select(day) }
            Task { await vm.reloadDayBlocks() }
        } else {
            openDay(day)
        }
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
                    .diaryFont(TypeSize.rowTitle, weight: .semibold)
                    .foregroundStyle(Theme.onSurface())
                    .lineLimit(1)
                    // The full date is the point of this row; shrinking it
                    // keeps it readable where truncation would not.
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                Spacer()
                if showsLunar {
                    Text(Lunar.fullLabel(selectedDate))
                        .diaryFont(TypeSize.caption)
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
