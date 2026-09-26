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
    private func peek(fullRect: CGRect, t: Double, opacity: Double) -> some View {
        let rowH = fullRect.height / 6
        let rows = CalendarLayout.displayedWeekCount(inMonth: month, ws: weekStart)
        let next = CalendarLayout.nextMonth(month)
        let nextTop = fullRect.minY + CGFloat(rows) * rowH
        let labelH = CalendarLayout.flowLabelBandHeight(compact: false)
        MonthFlowLabel(month: next,
                       cellW: size.width / 7,
                       column: CalendarLayout.monthLabelColumn(inMonth: next, ws: weekStart),
                       bandH: labelH,
                       weekStart: weekStart)
            .frame(width: size.width, height: labelH, alignment: .bottomLeading)
            .offset(y: nextTop - 3 - labelH)
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
            peek(fullRect: fullRect, t: t, opacity: peekFadesIn
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
                        rowView(i, row: row, selectedTop: selectedTop, rowH: rowH,
                                headH: headH, mMetrics: mMetrics, wMetrics: wMetrics)
                            .offset(y: -clipTop)
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

    private func rowView(_ i: Int, row: MonthFlowMorphSource.Row, selectedTop: CGFloat,
                         rowH: CGFloat, headH: CGFloat,
                         mMetrics: DayMetrics, wMetrics: DayMetrics) -> some View {
        let isSelected = i == source.selectedIndex
        var y: CGFloat
        var alpha: Double
        var metrics = mMetrics
        if isSelected {
            y = CL.lerp(row.top, headH, progress)
            alpha = 1
            metrics = DayMetrics.lerp(mMetrics, wMetrics, progress)
        } else if row.top < selectedTop {
            // 选中行**上方**的行：往上滑出屏幕。
            y = row.top - CGFloat(progress) * (row.top + rowH)
            alpha = 1 - CL.clamp01(progress * 1.4)
        } else {
            // 下方：往下滑出去，把位置让给日报内容。
            y = row.top + CGFloat(progress) * (size.height - row.top)
            alpha = 1 - CL.clamp01(progress * 1.4)
        }
        return WeekRowCanvas(week: row.week,
                             metrics: metrics,
                             selectedDate: selectedDate,
                             flags: flags,
                             alpha: alpha,
                             showDivider: row.showDivider,
                             anchorMonth: row.anchorMonth,
                             // 只有**选中的那一行**（它就是正在变成周条的那一行）要带相邻月的
                             // 日期；其余行和月视图一样只画本月的。否则月份边界那一周会在
                             // 两行里各画一遍（9 月最后一行与 10 月第一行本来就是同一周），
                             // 动画中間会看到同一批日期出现两次。
                             adjacentAlpha: progress,
                             showAdjacent: isSelected,
                             onTapDay: nil)
            .frame(width: size.width, height: metrics.cellH)
            .offset(y: y)
    }
}
