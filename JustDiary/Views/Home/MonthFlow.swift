import SwiftUI

// MARK: - 连续月历流（月视图：竖屏整屏 / 横屏左栏）
//
// 改造前：一个月一页，上下滑**整页翻月**（`DragPagePager` + `MonthPane`）。
// 改造后：顶部「大月份标题 + 星期栏」钉住不动，下面是**一条连续滚动的月份流**：
//
//     ┌ 九月 ◀── 大标题：钉住，跟着滚动实时切成「占住顶部的那一个月」
//     │ 一 二 三 四 五 六 日 ◀── 星期栏：钉住
//     ├──────────────────────────────────────────────
//     │ 28 29 30                       ← 上个月的最后一行
//     │              10月              ← 小标题：在**分割线上方**、紧贴它
//     │  ──  ──  ──  ──                ← 按格画的分割线（只画有日期的那几格）
//     │                 1  2  3  4      ← 本月第一行（分割线在日期上面）
//     │                    1  2  3  4    ← 下个月第一行（列对齐不变）
//     │  5  6  7  8  9 10 11
//     └──────────────────────────────────────────────
//
// 三条几何约定，全部由 `MonthFlowLayout` 精确算出来（不依赖 SwiftUI 的懒加载测量，
// 因为 morph 的起点必须和屏幕上画的东西逐像素一致）：
//
// 1. **行高全局一致**：每个月 = 一行小标题带 + 若干周行，都是 `rowH`。
// 2. **月份之间不留空隙**：两个月的行紧挨着；小标题画在**分割线上方**（贴着一个
//    `labelTightGap`），分割线画在本月第一行的顶、日期在分割线下面。所以从上到下的
//    次序是「上个月的日期 → 小标题 → 分割线 → 本月日期」。带高
//    （`flowLabelBandHeight`）只是这一行字的高度，用来把标题摆到那个位置。
// 3. **静止位置 = 该月第一行的顶**：进入某个月（初始 / 今天 / 年历点月）时，
//    把该月第一行顶到视口顶部，小标题刚好落在视口上沿之外。于是静止画面与改造前
//    「标题槽 + 星期栏 + 六行日期」**逐像素一致**，年↔月 morph 的终点
//    （`CalendarLayout.fullMonthGridRect`）与月↔周 morph 的起点都不用重新推导。

// MARK: - 几何

/// 一条连续月历流的几何。
struct MonthFlowLayout {
    struct Block: Identifiable {
        /// 在 `blocks` 里的序号（分隔线要不要画、是不是整条流的第一行都看它）。
        var index: Int
        /// `yyyyMM`。
        var key: Int
        var month: Date
        /// 小标题带的顶（= 本块在内容坐标里的起点）。
        /// 本月第一行的顶 —— 也是**本块的起点**、「静止」时滚动偏移该取的值。
        /// 两个月的行是紧挨着的，小标题画在这一行的上留白里。
        var top: CGFloat
        /// 本块要画的周行数（`CalendarLayout.displayedWeekCount`，5 或 6）。
        var rowCount: Int
        /// 本块的底（= 下个月第一行的顶）。
        var bottom: CGFloat

        var id: Int { key }
    }

    var weekStart: String
    var rowH: CGFloat
    var blocks: [Block]
    var contentH: CGFloat

    // MARK: 缓存
    //
    // 行数只随 (weekStart, rowH) 变：旋转 / 密度变化时重建一次，滚动过程中直接复用
    // （每个月一次 O(1) 的行数计算 × 2400 个月，每帧重算也能跑，但没必要）。

    private static let lock = NSLock()
    private static var cache: [String: MonthFlowLayout] = [:]

    static func cached(weekStart: String, rowH: CGFloat) -> MonthFlowLayout {
        let key = "\(weekStart)#\(Int((rowH * 100).rounded()))"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let built = MonthFlowLayout(weekStart: weekStart, rowH: rowH)
        lock.lock()
        cache[key] = built
        // 只留最近几档：旋转会换 rowH，长时间使用不至于无限增长。
        if cache.count > 12 { cache.removeAll(keepingCapacity: true); cache[key] = built }
        lock.unlock()
        return built
    }

    init(weekStart: String, rowH: CGFloat) {
        self.weekStart = weekStart
        self.rowH = max(1, rowH)
        var built: [Block] = []
        built.reserveCapacity(CalendarLayout.allMonthKeys.count)
        var cursor: CGFloat = 0
        for (i, key) in CalendarLayout.allMonthKeys.enumerated() {
            let month = CalendarLayout.dateForMonthKey(key)
            let rows = CalendarLayout.displayedWeekCount(inMonth: month, ws: weekStart)
            let bottom = cursor + CGFloat(rows) * self.rowH
            built.append(Block(index: i, key: key, month: month,
                               top: cursor, rowCount: rows, bottom: bottom))
            cursor = bottom
        }
        self.blocks = built
        self.contentH = cursor
    }

    // MARK: 查询

    /// 内容坐标 `y` 落在哪一块（小标题带也算本块）。二分，越界时夹到两端。
    func blockIndex(atOffset y: CGFloat) -> Int {
        guard !blocks.isEmpty else { return 0 }
        var lo = 0, hi = blocks.count - 1, ans = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if blocks[mid].top <= y {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    /// 视口里**占得最多**的那一块：把每块与本视口相交的高度比一比，取最大的。
    ///
    /// 顶部月份用它而不是「视口顶部落在哪一块」—— 后者下一月刚露一行就换标题，
    /// 快速滑动时标题会乱跳；「占多数」在整屏里只会在过半时切一次。
    func dominantBlockIndex(offset: CGFloat, viewportH: CGFloat) -> Int {
        let top = offset
        let bottom = offset + viewportH
        var best = blockIndex(atOffset: offset)
        var bestShare: CGFloat = -1
        for block in visibleBlocks(offset: offset, viewportH: viewportH, margin: 0) {
            let share = min(block.bottom, bottom) - max(block.top, top)
            if share > bestShare {
                bestShare = share
                best = block.index
            }
        }
        return best
    }

    func blockIndex(forKey key: Int) -> Int? {
        blocks.firstIndex { $0.key == key }
    }

    /// 某个月的「静止」偏移：该月第一行顶到视口顶部。
    func restOffset(forKey key: Int) -> CGFloat? {
        blockIndex(forKey: key).map { blocks[$0].top }
    }

    func maxOffset(viewportH: CGFloat) -> CGFloat {
        max(0, contentH - viewportH)
    }

    /// 与 `[offset, offset + viewportH]` 相交的块（上下各多带 `margin`）。
    func visibleBlocks(offset: CGFloat, viewportH: CGFloat, margin: CGFloat) -> [Block] {
        guard !blocks.isEmpty else { return [] }
        let first = blockIndex(atOffset: max(0, offset - margin))
        let limit = offset + viewportH + margin
        var last = first
        while last + 1 < blocks.count, blocks[last + 1].top < limit { last += 1 }
        return Array(blocks[first...last])
    }

    /// 本块要画的周（`CalendarLayout` 里有缓存）。
    func weeks(of block: Block) -> [WeekDays] {
        CalendarLayout.displayedWeeks(inMonth: block.month, ws: weekStart)
    }

    /// 某一行在内容坐标里的顶。
    func rowTop(of block: Block, row: Int) -> CGFloat {
        block.top + CGFloat(row) * rowH
    }
}

// MARK: - 小标题

/// 月份小标题：站在**当月 1 号那一列的正上方**（不是整行居中），
/// 并且紧贴 1 号那一行（贴着小标题带的底边）。
///
/// 带高就是这一行字的高度（`CalendarLayout.flowLabelBandHeight`），上下不再留白：
/// 用户看过两版（整行高 → 35pt）都嫌高，明确要求「紧贴月份高度」。
struct MonthFlowLabel: View {
    var month: Date
    /// 单格宽度（= 面板宽 / 7）。
    var cellW: CGFloat
    /// 小标题所在的列（0…6）= `CalendarLayout.monthLabelColumn`。
    var column: Int
    /// 小标题带的高度（= 这一行字的高度）。
    var bandH: CGFloat
    /// 横屏左栏的紧凑字号。
    var compact: Bool = false
    var weekStart: String

    var body: some View {
        let cal = DateUtil.calendar
        let isCurrent = cal.isDate(month, equalTo: Date(), toGranularity: .month)
        Text(L10n.monthName(cal.component(.month, from: month)))
            .diaryFont(CalendarLayout.flowLabelFontSize(compact: compact),
                       weight: isCurrent ? .bold : .semibold)
            .lineLimit(1)
            // 字号跟动态字体长大，窄格里靠缩放收住，别溢到隔壁列。
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .foregroundStyle(isCurrent ? Theme.primary() : Theme.onSurfaceVariant().opacity(0.85))
            .frame(width: cellW, height: bandH, alignment: .bottom)
            .offset(x: CGFloat(column) * cellW)
            .allowsHitTesting(false)
    }
}

// MARK: - Morph 源几何

/// 月→周 morph 的源几何：把按下那一刻**屏幕上真实画着的东西**冻结下来。
///
/// morph 视图照这份数字重画，所以切换的那一帧与原画面逐像素一致；反方向（周→月）
/// 用同一份源、同一条进度曲线倒放。`offset` 是冻结时的滚动偏移 —— 反向 morph 要在
/// 同一位置收尾，所以月视图保持挂载、偏移不动（见 `HomeView.calendarArea`）。
struct MonthFlowMorphSource {
    struct Row {
        var week: WeekDays
        /// 冻结时这一行在**日历区坐标**里的顶（已含标题槽、星期栏与滚动偏移）。
        var top: CGFloat
        var anchorMonth: Date
        /// 本块第一行不画分隔线（与 `MonthFlowView` 里的判断一致）。
        var showDivider: Bool
    }

    struct Label {
        var month: Date
        /// 冻结时小标题**底边**在日历区坐标里的 y（紧贴日期数字上方）。
        var bottom: CGFloat
    }

    var rows: [Row]
    var labels: [Label]
    /// `rows` 里被点中的那一行。
    var selectedIndex: Int
    /// 冻结时**顶部大标题显示的那个月**（点中的日期可能属于下一个月的行，
    /// morph 里的大标题要停在原来那一个上，不能中途换字）。
    var topMonth: Date
    var rowH: CGFloat
    /// 月份之间那一带的高度（小标题那一行字的高度）。
    var labelBandH: CGFloat
    /// 视口在日历区里的顶（= 标题槽 + 星期栏）。
    var viewportTop: CGFloat
    /// 紧凑形态（横屏左栏）—— 小标题字号要跟着走。
    var compact: Bool
    var size: CGSize

    var selectedRow: Row? { rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil }
}

// MARK: - 外部跳月

/// 外部要求「跳到某个月」的一次请求（今天 / 年历点月 / 旋转复位）。
///
/// 滚动位置由调用方持有，所以跳转要显式发起；`token` 让「连续两次跳到同一个月」
/// 也能被 `onChange` 看到。行高与静止偏移只有视图自己知道，所以换算放在视图里做。
struct MonthFlowJump: Equatable {
    var key: Int
    var animated: Bool
    var token: Int
}

// MARK: - 当前显示偏移

/// SwiftUI 每帧插值出来的「当前显示偏移」。
///
/// `MonthFlowView` 是 `Animatable`：滚动落定的惯性由 SwiftUI 逐帧插值 `animatableData`
/// 并**重新求值 body**，所以 body 里的 `offset` 始终是屏幕上那一帧的位置 —— 可见块、
/// 顶部大标题、指示条因此都跟着一起走。
///
/// 点日期时要拿这个值去冻结动画（morph 源必须与屏幕上那一帧逐像素一致，不能用还在
/// 动画中的目标值），所以把它记在一个引用盒子里给手势闭包读。
final class FlowRenderedOffset {
    var value: CGFloat = 0
}

// MARK: - 视图

struct MonthFlowView: View, Animatable {
    /// 滚动偏移（内容坐标）。**由调用方持有**，原因见 `FlowRenderedOffset` 的注释：
    /// 惯性要交给 SwiftUI 的动画逐帧插值，body 才会用「当前显示的位置」重算可见块
    /// 与顶部月份。若改成自己 `withAnimation` 改内部状态，整段惯性里可见块一直停在
    /// 终点那一批（中间几个月根本不画），顶部大标题也会在松手瞬间跳到终点月。
    var offset: CGFloat
    /// 拖动 / 惯性 / 复位时把新偏移写回调用方（`withAnimation` 由本视图包在调用外，
    /// 惯性才走 SwiftUI 的逐帧插值）。
    var onScroll: (CGFloat) -> Void
    var weekStart: String
    var selectedDate: Date
    var flags: Set<String>
    /// 日历区整块尺寸（含标题槽与星期栏）。
    var size: CGSize
    /// 单行的绘制参数（格宽 = 屏宽 / 7）。
    var metrics: DayMetrics
    var rowH: CGFloat
    var titleHeight: CGFloat = CalendarLayout.bigTitleH
    var weekdayHeight: CGFloat = CalendarLayout.weekdayHeaderH
    var titleFont: CGFloat = TypeSize.display
    /// 横屏左栏的紧凑形态（小标题与星期栏字号更小）。
    var compact: Bool = false
    /// 外部跳月请求（竖屏：今天 / 年历点月；横屏左栏不使用）。
    var jump: MonthFlowJump? = nil
    /// 点某一天：第二个参数是 morph 需要的源几何（横屏左栏不用，直接忽略）。
    var onTapDay: (Date, MonthFlowMorphSource) -> Void
    /// 滚动落定后回调「顶部现在是哪个月」（竖屏只改标题，横屏还要把选中日带过去）。
    var onSettle: (Date) -> Void = { _ in }

    @State private var rendered = FlowRenderedOffset()
    @State private var dragOrigin: CGFloat? = nil
    @State private var indicator: Double = 0
    @State private var indicatorTask: Task<Void, Never>? = nil

    var animatableData: CGFloat {
        get { offset }
        set {
            offset = newValue
            rendered.value = newValue
        }
    }

    /// 小标题与它下面那条分割线之间的间隙（「紧贴」的那个「紧」）。
    private static let labelTightGap: CGFloat = 3

    private var viewportH: CGFloat { max(0, size.height - titleHeight - weekdayHeight) }



    var body: some View {
        let layout = MonthFlowLayout.cached(weekStart: weekStart, rowH: rowH)
        let maxOff = layout.maxOffset(viewportH: viewportH)
        let labelH = CalendarLayout.flowLabelBandHeight(compact: compact)
        // 注意：这里**不做硬夹**。拖动时 `offset` 会带着橡皮筋超出两端，硬夹会把
        // 橡皮筋抵消掉（拖到头跟拖到一半手感一样）；越界值由 `blockIndex` 自己夹住。
        let off = offset
        // 记下屏幕上这一帧的位置（拖动起点、morph 源都用它）。写在引用盒子里，
        // 不是 @State，不会触发额外求值。
        rendered.value = off
        // 顶栏显示的是**占据视口最多的那个月**，不是「顶部那一行的月份」：
        // 后者在滑动时只要下一月的第一行露头就会切标题，看着像乱跳
        // （用户：「要显示的是占据屏幕主要的月份」）。
        let topIndex = layout.dominantBlockIndex(offset: off, viewportH: viewportH)
        let top = layout.blocks.indices.contains(topIndex) ? layout.blocks[topIndex] : nil
        let visible = layout.visibleBlocks(offset: off, viewportH: viewportH, margin: rowH)

        return VStack(spacing: 0) {
            // 顶栏：**不画任何底色**（页面背景直接透出来，与背景融为一体）
            header(top: top)

            // 内容区裁在顶栏下面：日期不会跑到顶栏后面去。顶栏曾经试过磨砂玻璃 +
            // 内容从下面穿过，用户看过之后要求回退，所以这里是最朴素的那一版。
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(visible) { block in
                    blockView(block, layout: layout, off: off, labelH: labelH)
                }
            }
            .frame(width: size.width, height: viewportH, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(layout: layout, off: rendered.value, maxOff: maxOff))
            .overlay(alignment: .topTrailing) {
                scrollIndicator(layout: layout, off: off, maxOff: maxOff)
            }
            // 整条流对 VoiceOver 是**一个**元素（与改造前的 `MonthCanvas` 一致）：
            // 逐个日期建元素会淹掉转子；默认动作打开选中日。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.fmt("date_month_title",
                                         DateUtil.calendar.component(.year, from: top?.month ?? Date()),
                                         L10n.monthName(DateUtil.calendar.component(.month, from: top?.month ?? Date()))))
            .accessibilityValue(L10n.formatDayKey(DateUtil.dayKeyOf(selectedDate)))
            .accessibilityAction {
                onTapDay(selectedDate, morphSource(layout: layout, off: off, tapped: nil))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .onChange(of: jump) { _, request in
            guard let request else { return }
            let target = layout.restOffset(forKey: request.key) ?? off
            if request.animated {
                withAnimation(.snappy(duration: 0.3)) { onScroll(target) }
            } else {
                var tr = Transaction()
                tr.disablesAnimations = true
                withTransaction(tr) { onScroll(target) }
            }
        }
    }

    // MARK: 内容块

    @ViewBuilder
    private func blockView(_ block: MonthFlowLayout.Block, layout: MonthFlowLayout, off: CGFloat,
                           labelH: CGFloat) -> some View {
        let weeks = layout.weeks(of: block)
        ZStack(alignment: .topLeading) {
            // 小标题在**分割线上方**（用户的次序：上个月日期 → 小标题 → 分割线 → 本月日期）。
            // 分割线画在本行顶部（见 `WeekRowCanvas`），所以标题底边落在行顶之上
            // `labelTightGap`；它借用的是上一行底部那段留白，不额外占高度。
            MonthFlowLabel(month: block.month,
                           cellW: size.width / 7,
                           column: CalendarLayout.monthLabelColumn(inMonth: block.month, ws: weekStart),
                           bandH: labelH,
                           compact: compact,
                           weekStart: weekStart)
                // 注意 `bottomLeading`：`MonthFlowLabel` 自己按列偏移，外层再用居中
                // 对齐会先把它摆到屏幕中间、再叠一次列偏移（实测偏了整整 3 列）。
                .frame(width: size.width, height: labelH, alignment: .bottomLeading)
                .offset(y: -Self.labelTightGap - labelH)
            // 整块（本月所有周行）画在**一张** Canvas 里，滚动时每帧只重画 2–3 张。
            MonthBlockCanvas(weeks: weeks,
                             anchorMonth: block.month,
                             metrics: metrics,
                             selectedDate: selectedDate,
                             flags: flags,
                             showsFirstDivider: block.index != 0,
                             onTapDay: { day, row in
                                 onTapDay(day, morphSource(layout: layout, off: off,
                                                           tapped: (block.index, row)))
                             })
                .frame(width: size.width, height: rowH * CGFloat(weeks.count))
        }
        .frame(width: size.width, height: block.bottom - block.top, alignment: .topLeading)
        .offset(y: block.top - off)
    }

    /// 顶栏：大月份标题 + 星期栏。**钉在顶部**，内容 = 占住视口顶部的那一个月。
    /// 刻意**不带背景**：页面背景（`BlobBackground` 的渐变）直接透上来，顶栏才「融入」
    /// 页面；画一层 `Theme.bg()` 会在渐变上留下一块颜色不一样的方块。
    @ViewBuilder
    private func header(top: MonthFlowLayout.Block?) -> some View {
        let bar = VStack(spacing: 0) {
            MonthBigTitle(month: top?.month ?? Date(), height: titleHeight, fontSize: titleFont)
                // UI 测试用它读当前月份（竖屏 morph、横屏翻月都靠这个断言）
                .accessibilityIdentifier("home.monthTitle")
                .frame(height: titleHeight)
            WeekdayHeaderView(weekStart: weekStart, cellW: size.width / 7)
                .frame(width: size.width, height: weekdayHeight)
        }
        .frame(width: size.width)
        bar
    }

    // MARK: 滚动

    private func dragGesture(layout: MonthFlowLayout, off: CGFloat, maxOff: CGFloat) -> some Gesture {
        // 2pt 就起手：6pt 的阈值会让内容在手指动了 6pt 之后才开始跟，明显「不跟手」。
        // 留一点点（不是 0）是为了不和行内的点击手势抢事件。
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // 手指追上正在滑行的惯性：把**当前显示位置**当作拖动起点。
                if dragOrigin == nil {
                    dragOrigin = rendered.value
                    freezeAnimation(at: off)
                    showIndicator()
                }
                let raw = (dragOrigin ?? off) - value.translation.height
                onScroll(rubberClamped(raw, maxOff: maxOff))
            }
            .onEnded { value in
                let origin = dragOrigin ?? off
                dragOrigin = nil
                // 自由滚动（无级）：按预测落点滑到位，用甩出的速度当弹簧初速，
                // 手感接近系统滚动；两端用同样的橡皮筋夹住。
                //
                // 阻尼：`damping ≈ 2·√(stiffness·mass) = 2√130 ≈ 22.8` 是临界阻尼，
                // 这里取 26（阻尼比 ≈ 1.14，**略过阻尼**）—— 松手后是一条平滑减速的
                // 滑行、到点即停，没有回弹/过冲（用户要求「调一下滑动阻尼」，之前
                // stiffness 140 / damping 22 的阻尼比 ≈ 0.93，末端会轻轻弹一下）。
                let projected = origin - value.predictedEndTranslation.height
                let target = min(maxOff, max(0, projected))
                let velocity = -value.velocity.height          // 内容偏移的速度（pt/s）
                // `interpolatingSpring` 的 `initialVelocity` 是**归一化**的
                // （Apple 文档：「a value in the range [0, 1] representing the magnitude
                // of the value being animated」，即「每秒走完这段距离的几分之几」）。
                // 之前直接把 pt/s 传进去，快了三个数量级 —— 快速甩动时弹簧一上来就飞，
                // 完全不跟手。这里按「位移」归一化，并夹在 ±12/s（位移很小时不至于爆掉）。
                let delta = target - origin
                let normalized: Double = abs(delta) > 4
                    ? min(max(Double(velocity / delta), -12), 12)
                    : 0
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 130, damping: 26,
                                                   initialVelocity: normalized)) {
                    onScroll(target)
                } completion: {
                    let i = layout.blockIndex(atOffset: rendered.value)
                    if layout.blocks.indices.contains(i) { onSettle(layout.blocks[i].month) }
                    hideIndicatorSoon()
                }
            }
    }

    /// 把一个正在播的惯性动画**停在当前这一帧**：写回同一个值（无动画）即可取消
    /// 原来的插值。拖动开始、或点日期要冻结 morph 源之前都要先做这一步。
    private func freezeAnimation(at value: CGFloat) {
        guard abs(rendered.value - offset) > 0.01 else { return }
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) { onScroll(value) }
    }

    private func rubberClamped(_ raw: CGFloat, maxOff: CGFloat) -> CGFloat {
        if raw < 0 { return -rubber(-raw) }
        if raw > maxOff { return maxOff + rubber(raw - maxOff) }
        return raw
    }

    private func rubber(_ x: CGFloat) -> CGFloat {
        let c = max(1, viewportH * 0.25)
        return c * x / (x + c)
    }

    // MARK: 滚动指示条

    private func scrollIndicator(layout: MonthFlowLayout, off: CGFloat, maxOff: CGFloat) -> some View {
        let h = max(36, viewportH * viewportH / max(layout.contentH, 1))
        let t = maxOff > 0 ? min(1, max(0, off / maxOff)) : 0
        return Capsule()
            .fill(Theme.onSurfaceVariant().opacity(0.35))
            .frame(width: 3, height: h)
            .offset(y: (viewportH - h) * t)
            .padding(.trailing, 2)
            .opacity(indicator)
            .allowsHitTesting(false)
    }

    private func showIndicator() {
        indicatorTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { indicator = 1 }
    }

    private func hideIndicatorSoon() {
        indicatorTask?.cancel()
        indicatorTask = Task {
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.35)) { indicator = 0 }
        }
    }

    // MARK: Morph 源

    /// 把当前可见的行 / 小标题冻结成 morph 源。`tapped` 是 (块序号, 行序号)；
    /// 为 nil 时（VoiceOver 的可调动作）以选中日所在的那一行为基准。
    private func morphSource(layout: MonthFlowLayout,
                             off: CGFloat,
                             tapped: (block: Int, row: Int)?) -> MonthFlowMorphSource {
        // morph 源必须与**屏幕上这一帧**一致：先把惯性停在当前帧，再按同一份数字建源。
        freezeAnimation(at: off)
        let visible = layout.visibleBlocks(offset: off, viewportH: viewportH, margin: 0)
        let topIndex = layout.dominantBlockIndex(offset: off, viewportH: viewportH)
        let topMonth = layout.blocks.indices.contains(topIndex) ? layout.blocks[topIndex].month : Date()
        var rows: [MonthFlowMorphSource.Row] = []
        var labels: [MonthFlowMorphSource.Label] = []
        var selected = 0
        for block in visible {
            let labelBottom = block.top - off + titleHeight + weekdayHeight - Self.labelTightGap
            labels.append(.init(month: block.month, bottom: labelBottom))
            let weeks = layout.weeks(of: block)
            for (i, week) in weeks.enumerated() {
                let top = block.top + CGFloat(i) * layout.rowH
                let y = top - off + titleHeight + weekdayHeight
                if let tapped, tapped.block == block.index, tapped.row == i { selected = rows.count }
                rows.append(.init(week: week,
                                  top: y,
                                  anchorMonth: block.month,
                                  showDivider: !(block.index == 0 && i == 0)))
            }
        }
        return MonthFlowMorphSource(rows: rows,
                                    labels: labels,
                                    selectedIndex: selected,
                                    topMonth: topMonth,
                                    rowH: layout.rowH,
                                    labelBandH: CalendarLayout.flowLabelBandHeight(compact: compact),
                                    viewportTop: titleHeight + weekdayHeight,
                                    compact: compact,
                                    size: size)
    }
}
