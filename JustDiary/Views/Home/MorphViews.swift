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
    /// 外框高度（竖屏传 `hFull`）。几何仍按 `size` 排（`size` 是让开浮条的那把尺子，
    /// 卡片与本月网格都读它），只是允许把「下个月的第一行」画到浮条底下那一段里去。
    var frameHeight: CGFloat? = nil
    /// 「下个月那一条」是**淡入**（年→月）还是**迅速消失**（月→年）。
    var peekFadesIn: Bool = false

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

    /// 「下个月那一条」：小标题 + 第一行日期，位置与 `MonthFlowView` 完全同一把尺子。
    @ViewBuilder
    private func peek(fullRect: CGRect, opacity: Double) -> some View {
        let rowH = fullRect.height / 6
        let rows = CalendarLayout.displayedWeekCount(inMonth: month, ws: weekStart)
        let next = CalendarLayout.nextMonth(month)
        // 下个月第一行 / 小标题的位置：与连续月历流同一把尺子（`flowMonthGap` 属于下一块，
        // 小标题贴在它上面 `flowLabelTightGap` 处）。**别把空隙减第二次** —— 实测那样小标题
        // 会高 16pt，收尾换回真图层时「小月份」标题往上跳一下。
        let peek = CalendarLayout.peekGeometry(fullRect: fullRect, rows: rows)
        let nextTop = peek.nextRowTop
        let labelBottom = peek.labelBottom
        let labelH = CalendarLayout.flowLabelBandHeight(compact: false)
        MonthFlowLabel(month: next,
                       cellW: size.width / 7,
                       column: CalendarLayout.monthLabelColumn(inMonth: next, ws: weekStart),
                       bandH: labelH,
                       weekStart: weekStart)
            .frame(width: size.width, height: labelH, alignment: .bottomLeading)
            .offset(y: labelBottom - labelH)
            .opacity(opacity)
        // 下个月**在容器里能看见的每一行**都要画：只画第一行的话，被系统浮条遮住的那
        // 部分（`hFull` 里 `hSafe` 之外那一段）要等 morph 结束、真图层接上才出现，
        // 而没被遮住的部分早就出现了 —— 用户看到的就是「同一批日期分两次冒出来」。
        let frameBottom = frameHeight ?? size.height
        // 先算出「容器里看得见的那几行」（ViewBuilder 里不能写 break/continue）。
        let visibleWeeks = CalendarLayout.displayedWeeks(inMonth: next, ws: weekStart)
            .enumerated()
            .filter { nextTop + CGFloat($0.offset) * rowH < frameBottom - 0.5 }
        ForEach(visibleWeeks, id: \.offset) { i, week in
            let top = nextTop + CGFloat(i) * rowH
            WeekRowCanvas(week: week,
                          metrics: CalendarLayout.flowMetrics(width: size.width, rowH: rowH,
                                                              lunar: showsLunar),
                          selectedDate: selectedDate,
                          flags: flags,
                          showDivider: true,
                          anchorMonth: next,
                          showAdjacent: false,
                          onTapDay: nil)
                .frame(width: size.width, height: rowH)
                .offset(y: top)
                .opacity(opacity)
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
                    // 同样不带 `home.monthTitle`：那个标识唯一属于连续月历流的钉住标题，
                    // 它常驻挂载且在这两个 morph 里显示的就是同一个月份。
                    MonthBigTitle(month: month)
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
            // 视口底部接着**下个月的小标题与第一行日期**（本月 5 行或 6 行都可能有）。
            // 方向不同，处理也不同（`peekFadesIn` 由调用方给）：
            // - 年 → 月：它是**要出现**的内容，跟着这一段动画淡入（不能等 morph 结束才冒出来）；
            // - 月 → 年：它是**要离开**的内容，一开场就迅速消失（不能飘进年视图里）。
            peek(fullRect: fullRect, opacity: peekFadesIn
                 ? CL.clamp01((t - 0.55) / 0.45)
                 : CL.clamp01((t - 0.9) / 0.1))
        }
        .frame(width: size.width, height: frameHeight ?? size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Month <-> Week expand morph

/// 月↔周 morph：把**冻结下来的连续月历流**（`MonthFlowMorphSource`）里选中那一行
/// 抬到星期栏下方、其余行淡出，同时日报内容从下面顶上来。
///
/// 行的位置不再由「第几行 × 行高」推出来，而是直接用冻结时的绝对 y —— 月视图改成
/// 连续滚动之后，按下那一刻屏幕上的行可能停在任意位置（半行、跨月），只有照抄这些
/// 数字，切换那一帧才不会跳。反方向（周→月）用同一份源、同一条进度曲线倒放。
struct MonthWeekMorphView<Content: View>: View, Animatable {
    var progress: Double
    /// 月视图正在看的那个月（只用来画大标题）。
    var month: Date
    var source: MonthFlowMorphSource
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
        let titleH = source.viewportTop - CalendarLayout.weekdayHeaderH
        let headH = CalendarLayout.weekdayHeaderH
        let rowH = source.rowH
        let mMetrics = CalendarLayout.flowMetrics(width: size.width, rowH: rowH,
                                                  lunar: showsLunar, compact: source.compact)
        let wMetrics = CalendarLayout.weekMetrics(width: size.width, lunar: showsLunar)
        // 选中行在冻结坐标里的顶：其余行的「往上/往下让开」都以它为界。
        let selectedTop = source.selectedRow?.top ?? source.viewportTop
        // 内容被顶栏遮住的那条边界：跟星期栏的底边完全重合（两端都对得上真实排版）。
        let clipTop = CL.lerp(source.viewportTop, headH, progress)
        // 选中行当前画在哪儿（morph 的两个方向都从它推）。
        let selectedY = CL.lerp(selectedTop, headH, progress)
        // 日记内容**始终挂在选中行下面**（行底 + 周条高度），不是按固定曲线滑。
        // 之前反方向（周→月）时内容是「往下滑 60pt」、而选中行要往下走 400+pt 回到
        // 它那个月的行里 —— 行会从内容中间穿过去，日期标题行就压在周行上（实测截帧里
        // 「2026年9月17日 周四」正好印在 14–20 那一行上面）。挂在行下面，两个方向都
        // 不会穿：正方向内容是「从下面升上来」，反方向是「跟着行一起沉下去」。
        let contentOffset = selectedY + CalendarLayout.weekStripH
        return ZStack(alignment: .top) {
            // 大标题**不带** `home.monthTitle` 标识：那个标识唯一属于连续月历流的
            // 钉住标题（它常驻挂载），morph 期间再挂一个会让 UI 测试查到两个同名元素，
            // 其中一个在 morph 收尾时消失 —— 查询就会报「元素已不在快照里」。
            MonthBigTitle(month: month)
                .offset(y: -progress * titleH)
                .opacity(1 - CL.clamp01(progress * 2))
            WeekdayHeaderView(weekStart: weekStart, cellW: size.width / 7)
                .frame(width: size.width, height: headH)
                // 月视图那一侧的落点是 `titleH`（标题槽高度 = 72），**不是**
                // `source.viewportTop`（= 标题槽 + 星期栏 = 102）：写成 102 时收尾那一帧
                // 星期栏比真实月视图低整整 30pt，动画结束换回真图层时就会「闪现」到
                // 月视图的位置（用户报的正是这一条）。
                .offset(y: CL.lerp(titleH, 0, progress))
            // 行与小标题**裁在顶栏底边以下**，而且这条边界跟着顶栏一起上/下移：
            // 月视图那一侧的顶栏是固定不动的，被它挡住的那半行在真实月视图里是看不见的；
            // morph 里若把它画出来，收尾换回真图层的一瞬间就会「直接被吞掉」（用户报的
            // 「顶部日期在最后直接消失」）。边界取 `lerp(viewportTop, headH, progress)`，
            // 正好等于星期栏的底边，两端都与真实排版对齐。
            //
            // 裁剪用「占位 + frame + clipped」，**不要**写成 `frame(...).offset(...).clipped()`：
            // 后者实测根本不裁（`.offset` 是渲染期平移，`.clipped()` 跟着它一起移，
            // 结果等于没裁 —— 加一条红色标记线量过：本该被裁掉的上半行照样画在顶栏上）。
            VStack(spacing: 0) {
                Color.clear.frame(height: clipTop)
                ZStack(alignment: .top) {
                    ForEach(Array(source.labels.enumerated()), id: \.offset) { _, label in
                        MonthFlowLabel(month: label.month,
                                       cellW: size.width / 7,
                                       column: CalendarLayout.monthLabelColumn(inMonth: label.month,
                                                                               ws: weekStart),
                                       bandH: source.labelBandH,
                                       compact: source.compact,
                                       weekStart: weekStart)
                            .frame(width: size.width, height: source.labelBandH, alignment: .bottomLeading)
                            .offset(y: label.bottom - source.labelBandH - clipTop)
                            .opacity(1 - CL.clamp01(progress * 2.2))
                    }
                    ForEach(Array(source.rows.enumerated()), id: \.offset) { i, row in
                        // 月份边界那一周在相邻月里也有一行，它的日期由选中行那一套负责
                        // —— 见 `isCarriedBySelectedRow`，不再画第二遍。
                        if !isCarriedBySelectedRow(row, at: i) {
                            rowView(i, row: row, selectedTop: selectedTop, rowH: rowH,
                                    headH: headH, mMetrics: mMetrics, wMetrics: wMetrics)
                                .offset(y: -clipTop)
                        }
                    }
                }
                .frame(width: size.width, height: max(0, size.height - clipTop), alignment: .top)
                .clipped()
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            content()
                .offset(y: contentOffset)
                .opacity(CL.clamp01((progress - 0.3) / 0.5))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
    }

    /// 这一行是不是**被选中行带走了**的那一行。
    ///
    /// 月份边界那一周在连续流里属于**两个块**：上个月的最后一行（画上个月那几天）
    /// 与下个月的第一行（画下个月那几天）。选中行会把「相邻月的那几格」带走
    /// （`previousShift` / `nextShift`），那几格与相邻月那一行画的是**同一批日期** ——
    /// 两边都画就会出现两套动画：一套跟着选中行进出周条，另一套跟着它自己那个月
    /// 滑走 / 滑进来（用户报的正是这个：上面一套往下走、下面一套跟着月份往上走）。
    ///
    /// 判据 = **周起始日相同 + 不属于选中行所在的那个月**。命中时这一行整行不画：
    /// 它在自己块里画的就是那几天，而它的分隔线由选中行那一组在同一个位置画出来
    /// （见 `WeekRowCanvas` 里三组分隔线），两端因此与真实图层逐像素一致。
    private func isCarriedBySelectedRow(_ row: MonthFlowMorphSource.Row, at index: Int) -> Bool {
        guard index != source.selectedIndex, let selected = source.selectedRow else { return false }
        let cal = DateUtil.calendar
        guard cal.isDate(row.week.start, inSameDayAs: selected.week.start) else { return false }
        return !cal.isDate(row.anchorMonth, equalTo: selected.anchorMonth, toGranularity: .month)
    }

    /// 相邻月那两组日期各自的位移：从周条里的位置，走到它们在**自己那一块**里的真实位置。
    /// `away` 是 0…1 的进度（0 = 周视图那一侧，1 = 月视图那一侧）。
    ///
    /// **方向由真实坐标决定，不是「上个月就一定向上」**：目标行的屏幕位置是用
    /// `MonthFlowLayout` 的内容坐标 + 冻结时的滚动偏移算出来的
    /// （`block.top + row × rowH − flowOffset + viewportTop`），再减去这一行当前的屏幕位置，
    /// 就是它该走的位移 —— 该向上就向上、该向下就向下。
    ///
    /// 例：本月的第 4 行（含 9/28–10/4）被点开时，上个月那一行的最后一行其实在它**下面**
    /// 一行，所以那几格在动画里要**向下**走回 9 月最后一行；而月初那一行被点开时，
    /// 上个月那一行在它上面，就**向上**走。两种情况都由同一段减法自然得出。
    ///
    /// 横向按「周几」逐格算（两边的列天然对齐，实测恒为 0，留着以防排版规则变化）。
    /// `away = 0` 时位移全为 0，所以周视图那一侧逐像素重合、两个方向都不跳。
    private func adjacentShifts(row: MonthFlowMorphSource.Row, rowH: CGFloat, away: Double)
        -> (previous: WeekRowShift, next: WeekRowShift) {
        let cal = DateUtil.calendar
        let anchor = row.anchorMonth
        let week = row.week
        let layout = MonthFlowLayout.cached(weekStart: weekStart, rowH: rowH)
        let screenOrigin = source.viewportTop - source.flowOffset   // 内容坐标 → 屏幕坐标
        // `row.top` 就是这一行冻结时的**屏幕顶**（`MonthFlowView.morphSource` 里已经换算过）。
        let selectedScreenTop = row.top
        let inMonth: (Date) -> Bool = { cal.isDate($0, equalTo: anchor, toGranularity: .month) }

        /// 某一周在它自己那个月里的**屏幕顶**（真实排版，不靠行号推）。
        func rowScreenTop(ofMonth month: Date, weekStartOf targetWeek: Date) -> CGFloat? {
            guard let bi = layout.blockIndex(forKey: CalendarLayout.monthKey(month)) else { return nil }
            let block = layout.blocks[bi]
            let weeks = layout.weeks(of: block)
            guard let ri = weeks.firstIndex(where: { cal.isDate($0.start, inSameDayAs: targetWeek) }) else { return nil }
            return block.top + CGFloat(ri) * rowH + screenOrigin
        }

        var previous = WeekRowShift(dy: 0)
        if let firstInMonth = week.days.firstIndex(where: inMonth), firstInMonth > 0 {
            // 上个月那一块的**最后一行**（就是这一周在它自己那个月里的位置）。
            let prevMonth = DateUtil.addDays(DateUtil.monthFirst(anchor), -1)
            if let target = rowScreenTop(ofMonth: prevMonth, weekStartOf: week.start) {
                previous.dy = (target - selectedScreenTop) * CGFloat(away)
            }
            for col in 0..<firstInMonth {
                let target = DateUtil.weekdayIndex(week.days[col], weekStart: weekStart)
                previous.columnShifts[col] = CGFloat(target - col) * CGFloat(away)
            }
        }
        var next = WeekRowShift(dy: 0)
        if let lastInMonth = week.days.lastIndex(where: inMonth), lastInMonth < week.days.count - 1 {
            // 下个月那一块的**第一行**。
            let nextMonth = CalendarLayout.nextMonth(anchor)
            if let target = rowScreenTop(ofMonth: nextMonth, weekStartOf: week.start) {
                next.dy = (target - selectedScreenTop) * CGFloat(away)
            }
            for col in (lastInMonth + 1)..<week.days.count {
                let target = DateUtil.weekdayIndex(week.days[col], weekStart: weekStart)
                next.columnShifts[col] = CGFloat(target - col) * CGFloat(away)
            }
        }
        return (previous, next)
    }

    private func rowView(_ i: Int, row: MonthFlowMorphSource.Row, selectedTop: CGFloat,
                         rowH: CGFloat, headH: CGFloat,
                         mMetrics: DayMetrics, wMetrics: DayMetrics) -> some View {
        let isSelected = i == source.selectedIndex
        var y: CGFloat
        var alpha: Double
        var metrics = mMetrics
        // 选中行里「相邻月的日期」**各走各的路线**（月视图里它们根本不属于这一行：上个月的
        // 那几天在上面那一块的最后一行、下个月的那几天在下面那一块的第一行）。
        // 起点 = 周条里它现在的位置，终点 = 它在自己那一块里的真实位置，两条路径按同一条
        // S 形曲线从「周视图」走到「月视图」；`progress = 1`（周视图）时位移为 0，
        // 所以端点上两边完全重合。
        var previousShift = WeekRowShift(dy: 0)
        var nextShift = WeekRowShift(dy: 0)
        var previousSolid: Double = 0
        var nextSolid: Double = 0
        if isSelected {
            y = CL.lerp(row.top, headH, progress)
            alpha = 1
            metrics = DayMetrics.lerp(mMetrics, wMetrics, progress)
            let away = CL.smoothstep(Double(CL.clamp01(1 - progress)))
            let shifts = adjacentShifts(row: row, rowH: rowH, away: away)
            previousShift = shifts.previous
            nextShift = shifts.next
            // 相邻月的日期**从头到尾都是实色**：灰（0.5）表达的是「这不是本月的日期」，
            // 而 morph 一开始它们就在往自己那个月的那一行走 —— 再挂着这层灰，整段动画
            // 看起来都是「虚的」，直到收尾换回真图层才突然变实（用户报的「还不是从头到尾
            // 都实」）。这里直接给 1：整段保持实色，收尾与真实月视图一致，不再有突变。
            previousSolid = 1
            nextSolid = 1
        } else if row.top < selectedTop {
            // 选中行**上方**的行：往上滑出屏幕。
            y = row.top - CGFloat(progress) * (row.top + rowH)
            alpha = 1 - CL.clamp01(progress * 1.4)
        } else {
            // 下方：往下滑出去，把位置让给日报内容。
            y = row.top + CGFloat(progress) * (size.height - row.top)
            alpha = 1 - CL.clamp01(progress * 1.4)
        }
        // 相邻月那几格会被搬到**本行格子之外**（上个月的最后一行在上方一整行 + 月份空隙
        // 处、下个月的第一行在下方同样远，竖屏约 110pt），而 `Canvas` 只画在自己的 frame
        // 里 —— 不按位移把画布撑开，那几格一离开本行就被裁掉：屏幕上就是「日期凭空出现」，
        // 而不是从周条一路走到自己那个月的那一行（用户报的）。选中行因此按位移撑高画布，
        // 其余行的位移恒为 0，frame 与改造前逐像素一致。
        let rise = max(0, -min(previousShift.dy, nextShift.dy, 0))
        let drop = max(0, max(previousShift.dy, nextShift.dy, 0))
        return WeekRowCanvas(week: row.week,
                             metrics: metrics,
                             selectedDate: selectedDate,
                             flags: flags,
                             alpha: alpha,
                             showDivider: row.showDivider,
                             anchorMonth: row.anchorMonth,
                             // 只有**选中的那一行**（它就是正在变成周条的那一行）要带相邻月的
                             // 日期；其余行和月视图一样只画本月的。边界那一周在相邻月里的
                             // 那一行整行不画（见 `isCarriedBySelectedRow`），所以这批日期
                             // 在动画里只有这一套。
                             // 相邻月日期**不淡入淡出**，只做移动（用户要求「就按照原本的样式」）。
                             adjacentAlpha: 1,
                             previousShift: previousShift,
                             nextShift: nextShift,
                             previousSolid: previousSolid,
                             nextSolid: nextSolid,
                             showAdjacent: isSelected,
                             rowOrigin: rise,
                             onTapDay: nil)
            .frame(width: size.width, height: metrics.cellH + rise + drop)
            .offset(y: y - rise)
    }
}


