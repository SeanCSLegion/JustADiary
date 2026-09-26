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
    @State private var ymMorph: (year: Int, month: Date, zoomingIn: Bool)?
    @State private var expand: Double = 0
    @State private var mwMorphMonth: Date?
    /// 月↔周 morph 冻结下来的连续月历流几何（开合两个方向共用）。
    @State private var mwSource: MonthFlowMorphSource?
    /// 连续月历流的滚动偏移（内容坐标）。竖屏整屏与横屏左栏两条流各一份；
    /// 归 HomeView 持有是为了让 SwiftUI 能逐帧插值惯性（见 `FlowRenderedOffset`）。
    @State private var flowOffset: CGFloat?
    @State private var paneFlowOffset: CGFloat?
    /// 发给竖屏月视图的「跳到某个月」请求与它的序号。
    @State private var monthJump: MonthFlowJump?
    @State private var jumpToken = 0
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
                if layout.splitsMasterDetail {
                    // 横屏分栏：整块头部隐藏。年份入口已按需求取消，横屏只剩
                    // 「上下滑切月」一种交互；「今天」在右栏标题行。
                    splitCalendarArea(size: size)
                } else {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, Self.headerTopPadding)
                        // 顶栏的透明效果已按用户要求**回退**：这一排恢复页面背景色，
                        // 不再铺磨砂材质（用户：「顶部的透明效果看起来不好，回退吧」）。
                    // 横屏（尚未分栏的窄窗口）点年份胶囊进年历：复用竖屏那套整屏 morph
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
                    // 这颗 toast 挂在整块几何的底边上（几何一直延伸到屏幕底边），
                    // 而浮条悬在内容之上：只让 24pt 的话 toast 整颗都落在浮条
                    // 底下（竖屏浮条顶边在 y 791，toast 在 810–850），等于没显示。
                    .padding(.bottom, layout.tabBarClearance + 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .sensoryFeedback(.warning, trigger: showFutureToast)
            }
        }
        .task { await vm.loadInitial() }
        .onChange(of: layout.splitsMasterDetail) { _, split in
            // 旋转进横屏分栏时，年/周态与 morph 都必须收掉：横屏没有年历入口，
            // 也不该停留在半屏 morph 上。反向旋转时让竖屏那条流按当前月重新静止
            // （横屏左栏可能已经滚到别的月份了）。
            if split { settleToMonth() } else { flowOffset = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await vm.loadInitial() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            vm.refreshSettings()
            resetToToday()
        }
    }

    /// 无动画地退回「月」态（横屏分栏使用）。
    private func settleToMonth() {
        guard mode != .month || ymMorph != nil || mwMorphMonth != nil else { return }
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            ymMorph = nil
            mwMorphMonth = nil
            mwSource = nil
            zoom = 0
            expand = 0
            mode = .month
        }
        // 左栏的滚动位置跟着行高变（横屏 45pt / SE 40.5pt），下一次进横屏重新静止。
        paneFlowOffset = nil
        Task { await vm.reloadDayBlocks() }
    }

    // MARK: - Header

    /// 头部整块占掉的高度：`.padding(.top, 12)` + `.frame(minHeight, 52)`。
    ///
    /// 日历区的高度是从**整块几何**里推出来的（几何因为 `.ignoresSafeArea(edges:
    /// .bottom)` 一直延伸到屏幕底边），所以这两个数字既要在 `header` 上用，也要在
    /// 减高度时用 —— 写两份就会漂移，日期又会钻到浮条底下。
    private static let headerTopPadding: CGFloat = 12
    private static let headerMinHeight: CGFloat = 52
    private static var headerBlockHeight: CGFloat { headerTopPadding + headerMinHeight }

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

            // 这一整个 header 只在未分栏（竖屏 / 窄窗口）时构建，
            // 横屏的「今天」在右栏标题行，不会重复。
            InfoCapsule(text: relativeDayLabel(), action: todayTapped)
        }
        // `height` clipped the capsule once the title grew with the user's
        // text size; `minHeight` is unchanged at the default category.
        .frame(minHeight: Self.headerMinHeight)
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
            // 连续月历流要在 morph 结束时**正好**停在这个月的静止位置，所以这里
            // 立刻把跳转请求发下去（morph 期间月视图是隐藏的，看不见这次跳）。
            jumpFlow(to: monthDate, animated: false)
            ymMorph = (vm.yearPage, monthDate, true)
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

    /// 点某一天 → 月↔周 morph。`source` 是按下那一刻冻结的连续月历流几何：
    /// 反方向（周→月）也用同一份源倒放，所以这一行会**回到它原来的位置**。
    private func openDay(_ day: Date, source: MonthFlowMorphSource) {
        guard mwMorphMonth == nil else { return }
        Haptics.tap()
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            vm.select(day)
            mwMorphMonth = vm.monthPage
            mwSource = source
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
                // 源几何用完就丢：下一次开合会重新冻结。
                mwSource = nil
            }
        case .month:
            showYearPage()
        case .year:
            break
        }
    }

    /// 切到年历（缩放 morph）。竖屏左上角的年月胶囊走这里。
    /// 横屏没有年份入口，此路径不可达。
    private func showYearPage() {
        guard !morphing else { return }
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            vm.yearPage = DateUtil.calendar.component(.year, from: vm.monthPage)
            ymMorph = (vm.yearPage, vm.monthPage, false)
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
            jumpFlow(to: Date(), animated: true)
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
        mwSource = nil
        zoom = 0
        expand = 0
        mode = .month
        vm.resetToToday()
        // 版面可能刚变过（旋转 / 密度），先把两条流都放回当前月的静止位置。
        flowOffset = nil
        paneFlowOffset = nil
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

    /// 横屏（两栏放得下）走「左月历 + 右选中日」的静态分栏。
    ///
    /// 竖屏**不经过这里** —— 年 ↔ 月 ↔ 周三态与 morph 动画保持原样。
    private func splitCalendarArea(size: CGSize) -> some View {
        // `size` 已经是**扣掉左右安全区**的内容尺寸（18 Pro 横屏 874×402 → 宽 750；
        // SE 横屏 667×375 → 宽 667；高度因为 `.ignoresSafeArea(.bottom)` 仍是屏高）：
        // 左侧那 62pt 系统占位已经在几何原点里，这里再减一次就是重复避让 ——
        // 第一版在 HomeView 与左栏月历各避让一次，日历被推到 x ≈ 222，左半屏白白空着。
        let topPad = AdaptiveLayout.splitTopPadding
        // 底部为横屏那枚悬在屏幕底部的系统浮条让位（实测 64pt，且紧贴屏底）：
        // 日历区在浮条之上结束。这里**不能**用 `bottomInset + 44`：SE 横屏没有
        // home indicator（`bottomInset = 0`），那样只让出 44pt，最后一行会被压住。
        let paneH = layout.splitPaneHeight(containerHeight: size.height)

        let headerH = CalendarLayout.compactMonthTitleH + CalendarLayout.compactWeekdayHeaderH

        // 主栏固定为容器宽的一部分，其余全部给右栏；两栏之和 + 页边距 + 分隔线
        // 正好等于容器宽，所以 18 Pro 横屏是 345 / 356.5，SE 横屏是 307 / 311.5，
        // 都不会溢出（见 `AdaptiveLayout.splitColumns`）。
        let columns = layout.splitColumns(containerWidth: size.width)
        let calendarW = columns.master
        let dayW = columns.detail
        let gutter = AdaptiveLayout.splitGutter
        let todayAction = todayTapped

        // 行高按**固定的 6 行**算：连续滚动里行高必须全局一致，不能跟着「当月是 5 行
        // 还是 6 行」变，否则滚过月份边界时格子会忽高忽低。
        let density = CalendarDensity.resolve(availableHeight: paneH - headerH,
                                              rows: 6,
                                              wantsLunar: showsLunar)
        let rowH = density.rowHeight(availableHeight: paneH - headerH, rows: 6)
        let flowMetrics = CalendarLayout.flowMetrics(width: calendarW,
                                                     rowH: rowH,
                                                     lunar: density.showsLunar,
                                                     compact: true)

        return HStack(alignment: .top, spacing: 0) {
            // 月历：与竖屏同一套**连续月历流**（上下滑无级滚动，不引入第二套手势），
            // 只是紧凑形态 + 行高按左栏高度自适应。
            MonthFlowView(offset: paneFlowOffset ?? flowRest(vm.monthPage, rowH: rowH),
                          onScroll: { paneFlowOffset = $0 },
                          weekStart: weekStart,
                          selectedDate: selectedDate,
                          flags: flags,
                          size: CGSize(width: calendarW, height: paneH),
                          metrics: flowMetrics,
                          rowH: rowH,
                          titleHeight: CalendarLayout.compactMonthTitleH,
                          weekdayHeight: CalendarLayout.compactWeekdayHeaderH,
                          titleFont: TypeSize.pageTitle,
                          compact: true,
                          onTapDay: { day, _ in selectDay(day) },
                          // 翻月后把选中日带进新月份，右栏才跟着一起走。
                          onSettle: { month in
                              selectMonthPage(CalendarLayout.monthKey(month))
                          })
                .frame(width: calendarW, height: paneH)
                .clipped()

            Rectangle()
                .fill(Theme.outlineVariant().opacity(0.4))
                .frame(width: 0.5, height: paneH)
                .padding(.horizontal, gutter / 2)

            // 右栏：选中日的日记预览。标题行放「今天」，正文限宽。
            DayPane(blocks: vm.dayBlocks,
                    dayKey: DateUtil.dayKeyOf(selectedDate),
                    isFuture: DateUtil.dayKeyOf(selectedDate) > DateUtil.dayKeyOf(Date()),
                    openEditor: openEditor,
                    bottomInset: layout.bottomInset,
                    maxColumnWidth: 560,
                    headingHeight: 44,
                    onTodayTap: todayAction,
                    // `auto_time` 关闭时不显示开始时间（仅显示层，数据照常记录）。
                    showTime: vm.settings.autoTime)
                .frame(width: dayW, height: paneH)
                .clipped()
        }
        .padding(.leading, AdaptiveLayout.pagePadding)
        .padding(.trailing, AdaptiveLayout.pagePadding)
        .padding(.top, topPad)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 横屏上下滑翻月：把选中日带到新月份的同一天，右栏才跟着一起走。
    private func selectMonthPage(_ key: Int) {
        let month = CalendarLayout.dateForMonthKey(key)
        let cal = DateUtil.calendar
        let day = cal.component(.day, from: selectedDate)
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = min(day, cal.range(of: .day, in: .month, for: month)?.count ?? day)
        let target = cal.date(from: comps) ?? month
        vm.select(target)
        Task { await vm.reloadDayBlocks() }
    }

    private func calendarArea(size: CGSize) -> some View {
        let w = size.width
        // 两把高度尺子（用户要求底部「不要留白色遮罩、要有沉浸感」之后分出来的）：
        //
        // - `hSafe`（= 几何 − 头部 − **浮条自身的高度**）：**不许被浮条压住**的内容用它。
        //   年历的四行卡片、morph 的终点都按它排 —— 几何到屏幕底边，而浮条悬在内容之上
        //   （竖屏 `safeArea.bottom` 只有 34pt 的 home indicator、浮条自身 83pt 不在安全区），
        //   不自己让出来，最后一行就被盖住。
        // - `hFull`（= 几何 − 头部）：**可以穿到浮条底下**的内容用它。月视图的连续流与
        //   周视图的日记都铺到屏幕底边：日期从玻璃浮条下面滚过去，浮条那层玻璃才有东西
        //   可以透，底部不会留出一条空白的「白遮罩」。当月那六行仍然落在 `hSafe` 之内
        //   （行高按 `hSafe` 算），所以「日期被浮条压住」那个 bug 不会回来。
        let hSafe = layout.singleColumnCalendarHeight(containerHeight: size.height,
                                                     headerHeight: Self.headerBlockHeight)
        let hFull = hSafe + layout.tabBarClearance
        // 行高沿用「标题槽 + 星期栏 + 六行」那把尺子（按 `hSafe` 算）：静止时画面与
        // 改造前逐像素一致，年↔月 morph 的终点（`fullMonthGridRect`）也就不用重新推导。
        // 24pt 只是兜底：容器矮到连一行都放不下时（分屏 / 折叠态的极端高度），
        // 行高不能变成负数。
        let rowH = max(24, CalendarLayout.monthCellH(areaH: hSafe))
        let flowMetrics = CalendarLayout.flowMetrics(width: w, rowH: rowH, lunar: showsLunar)

        // While a morph runs the base layers sit at opacity 0 — but an opacity-0 view is
        // still built and still re-evaluated on every animation frame. The year layer
        // wraps a DragPagePager that eagerly builds three pages (3 x 12 = 36 month
        // canvases), so it is only built when it is actually the visible mode; the week
        // layer (day content scroll view) likewise.
        //
        // 月视图（连续月历流）是例外：**始终挂载**，morph 期间只把不透明度压到 0。
        // 它的滚动位置是内部状态，卸载就丢 —— 月↔周 morph 收尾要回到「按下那一行
        // 原来的位置」，卸载再挂载就会跳一下。
        return ZStack(alignment: .top) {
            if !morphing, mode == .year {
                // 页高用 `hFull`（铺满屏幕）：分页器的邻页整页在屏幕之外，不会有
                // 「下一年的头两行从底部漏出来」；卡片本身仍按 `hSafe` 排，最后一
                // 行依旧在浮条之上。
                yearLayer(w: w, containerH: hFull, layoutH: hSafe)
            }
            MonthFlowView(offset: flowOffset ?? flowRest(vm.monthPage, rowH: rowH),
                          onScroll: { flowOffset = $0 },
                          weekStart: weekStart,
                          selectedDate: selectedDate,
                          flags: flags,
                          size: CGSize(width: w, height: hFull),
                          metrics: flowMetrics,
                          rowH: rowH,
                          jump: monthJump,
                          onTapDay: { day, source in openDay(day, source: source) },
                          onSettle: settleFlow)
                .frame(width: w, height: hFull)
                .opacity(mode == .month && !morphing ? 1 : 0)
                .allowsHitTesting(mode == .month && !morphing)
            if !morphing, mode == .week {
                weekLayer(w: w, h: hFull)
            }
            if let m = ymMorph {
                YearMonthMorphView(progress: zoom,
                                   year: m.year,
                                   month: m.month,
                                   size: CGSize(width: w, height: hSafe),
                                   weekStart: weekStart,
                                   selectedDate: selectedDate,
                                   flags: flags,
                                   showsLunar: showsLunar,
                                   frameHeight: hFull,
                                   // 年→月（`zoom` 从 1 走到 0）时下个月那一条要**淡入**；
                                   // 月→年时它一开场就迅速消失。
                                   peekFadesIn: m.zoomingIn)
            }
            if mwMorphMonth != nil, let src = mwSource {
                MonthWeekMorphView(progress: expand,
                                   month: src.topMonth,
                                   source: src,
                                   selectedDate: selectedDate,
                                   flags: flags,
                                   weekStart: weekStart,
                                   // 周视图与日记也铺到屏幕底边（沉浸），所以 morph 的
                                   // 容器同样用 `hFull`：收尾换回真实图层时高度不会变。
                                   size: CGSize(width: w, height: hFull),
                                   showsLunar: showsLunar) {
                    dayContentBlock(w: w, h: hFull)
                }
            }
        }
        // 整块日历区铺到屏幕底边（`hFull`）：月视图的日期从玻璃浮条下面滚过去。
        .frame(width: w, height: hFull, alignment: .top)
        .clipped()
    }

    /// 连续月历流滚动落定：竖屏只把「当前月」记进 VM（顶部大标题由月视图自己实时跟随），
    /// 横屏由左栏的 `onSettle` 单独处理（还要把选中日带过去）。
    private func settleFlow(_ month: Date) {
        guard CalendarLayout.monthKey(month) != CalendarLayout.monthKey(vm.monthPage) else { return }
        vm.selectMonth(month)
    }

    /// 某个月在连续月历流里的**静止偏移**（该月第一行的顶）。
    ///
    /// 月视图的滚动位置由 HomeView 持有（惯性要交给 SwiftUI 逐帧插值），所以
    /// 「跳到某个月」就是把偏移设成这个值；`MonthFlowLayout` 有缓存，这里几乎零成本。
    private func flowRest(_ month: Date, rowH: CGFloat) -> CGFloat {
        MonthFlowLayout.cached(weekStart: weekStart, rowH: rowH)
            .restOffset(forKey: CalendarLayout.monthKey(month)) ?? 0
    }

    /// 让月视图跳到某个月（今天 / 年历点月）。`token` 保证「连续两次跳同一个月」
    /// 也能被 `onChange` 看到；真正的偏移换算与动画在月视图里做（它才知道行高）。
    private func jumpFlow(to month: Date, animated: Bool) {
        jumpToken += 1
        monthJump = MonthFlowJump(key: CalendarLayout.monthKey(month),
                                  animated: animated,
                                  token: jumpToken)
    }

    private func yearLayer(w: CGFloat, containerH: CGFloat, layoutH: CGFloat) -> some View {
        DragPagePager(keys: CalendarLayout.allYears,
                      current: vm.yearPage,
                      axis: .vertical,
                      pageSize: containerH,
                      disabled: morphing,
                      onPageChange: { vm.yearPage = $0 }) { y in
            YearPageView(year: y,
                         selectedDate: selectedDate,
                         flags: flags,
                         weekStart: weekStart,
                         containerSize: CGSize(width: w, height: containerH),
                         layoutHeight: layoutH,
                         onSelectMonth: openMonthFromYear)
        }
        .frame(height: containerH)
    }

    /// 点某个日期：横屏只更新选中日（不进入周视图），竖屏走 morph。
    private func selectDay(_ day: Date) {
        Haptics.tap()
        withAnimation(.snappy(duration: 0.25)) { vm.select(day) }
        Task { await vm.reloadDayBlocks() }
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
                           showFutureToast: showFutureDateToast,
                           // `auto_time` 关闭时不显示开始时间（仅显示层，数据照常记录）。
                           showTime: vm.settings.autoTime)
        }
        .frame(width: w, height: h - stripBottom)
    }
}
