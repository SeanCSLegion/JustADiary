import SwiftUI
import UIKit

/// 一个由系统保留的区间（折痕 / 摄像头）。
///
/// 刻意用应用自己的值类型，而不是把 SwiftUI `ReservedRegion` 直接放进
/// `AdaptiveLayout`：后者是 iOS 27.1 才有的类型，会让整份版面模型、单元测试
/// 和 27.0 的调用方都被 `@available` 传染。Reader 在 27.1+ 转换一次即可。
nonisolated struct FoldRegion: Equatable, Sendable {
    /// 包含交互留白（margins）的区间，单位是 Reader 内容坐标。
    var frame: CGRect
    var margins: EdgeInsets
    var isActive: Bool
}

/// 分栏的结果。`gutter` 是两栏之间的总空隙（含中间 0.5pt 分隔线两侧的留白）；
/// 有折痕时它会比默认的 16pt 宽，正好跨过折痕。
nonisolated struct SplitMetrics: Equatable, Sendable {
    var master: CGFloat
    var detail: CGFloat
    var gutter: CGFloat
    var separatorWidth: CGFloat { gutter + 0.5 }
}

/// 版面判定：整套设计的**唯一**判据。
///
/// 关键约束（来自 Apple 的适配指南与 HIG Layout）：
/// - 只看**当前可用宽度/高度**，不看 `UIDevice.idiom`、不看 orientation、
///   不读 `UIScreen.main` —— 一个宽高都是 regular 的容器**仍然是 iPhone**
///   （分屏等），任何按机型分支的代码在它上面都会错。
/// - 左右安全区**分别**读取（横屏时 `leading` 往往非 0）。
/// - 数值优先从几何 / `safeAreaInsets` 派生，不要写死设备常量。唯一的例外是底部
///   系统浮条的高度：浮条由系统绘制，安全区里推不出来（SE 横屏 `bottomInset = 0`
///   但浮条照样占 64pt）。**iPhone Duo 的系统栏在侧边**，此时没有底部横条，
///   见 `tabBarClearance`。
///
/// 当前做**手机竖屏 / 手机横屏**两套版面，以及 iPhone Duo 的：
/// - 折痕避让（横屏分栏把折痕带当分隔区）；
/// - 侧置系统栏（`verticalBarEdge != nil` 时底部只让 home indicator）；
/// - 窗口尺寸（分屏 / 可缩放窗口，不是整块屏幕尺寸）。
struct AdaptiveLayout: Equatable {
    var size: CGSize
    /// 四边安全区，分别保存（横屏时 leading / trailing 常不相等）。
    var safeArea: EdgeInsets
    /// 当前窗口是否 regular width（Duo 内屏是 Regular/Regular）。
    var isRegularWidth: Bool = false
    /// 系统竖排栏在哪一侧；nil 表示使用底部横排系统栏（普通 iPhone）。
    var verticalBarEdge: HorizontalEdge? = nil
    /// 折痕 / 摄像头区间。27.0 上恒为空。
    var divisionRegions: [FoldRegion] = []
    var occlusionRegions: [FoldRegion] = []

    // MARK: 内容边距

    /// 底部为系统浮条 / 指示条预留的高度。
    ///
    /// 横屏时系统的浮动 tab bar 仍在底部居中、占 64pt（实测 bar `y 338–402`），
    /// 竖屏约 83pt —— 都体现在 `safeArea.bottom` 里，所以这里直接用它。
    var bottomInset: CGFloat { max(0, safeArea.bottom) }

    // MARK: 分栏

    /// 可用于放内容、且不会被系统占位吃掉的宽度。
    ///
    /// 横屏时左侧那条系统占位（`leading = 62`）不参与分栏计算 —— 否则
    /// 「874 够宽」会得出一个实际只有 750 能用的结论。
    var contentWidth: CGFloat {
        max(0, size.width - max(0, safeArea.leading) - max(0, safeArea.trailing))
    }

    /// 「宽但不矮」的尺寸（竖屏、Duo 竖屏）：保持单栏。
    var isPortrait: Bool { size.height >= size.width }

    // MARK: iPhone Duo

    /// 系统现在使用侧置的竖排栏（Duo 外屏、Duo 内屏横屏）。
    var usesVerticalBars: Bool { verticalBarEdge != nil }

    /// 当前是否有正在生效的折痕。平放时 `division` 是 inactive 的，这里返回 nil。
    var activeDivision: FoldRegion? {
        divisionRegions.first { $0.isActive && ($0.frame.width > 0.5 || $0.frame.height > 0.5) }
    }

    /// 折痕方向：横带（竖屏半折）还是竖带（横屏半折）。
    ///
    /// 注意 frame 是**带的形状**：竖折痕是一条窄而高的带（height > width），
    /// 横折痕是一条宽而矮的带（width > height）。
    var foldAxis: Axis? {
        guard let region = activeDivision else { return nil }
        return region.frame.height >= region.frame.width ? .vertical : .horizontal
    }

    // MARK: 分栏的两栏尺寸（判定与分配共用同一组数字）

    /// 主栏（月历）最窄宽度：7 列每格还有 ~37pt，日期才点得准。
    static let minMasterWidth: CGFloat = 260
    /// 主栏（月历）最宽宽度：比这更宽只是在拉大格子，并不会让内容更好读。
    static let maxMasterWidth: CGFloat = 440
    /// 详情栏（选中日日记）最窄宽度：再窄正文就每行只折 3–4 个字。
    static let minDetailWidth: CGFloat = 240
    /// 两栏之间的空隙：分隔线左右各一半。
    static let splitGutter: CGFloat = 16
    /// 分隔线本身 0.5pt；两栏之外的横向开销就是「页边距 ×2 + 栏间距 + 细线」。
    static let splitSeparatorWidth: CGFloat = splitGutter + 0.5
    /// 分栏区块距页面顶部的留白。
    static let splitTopPadding: CGFloat = 8
    /// 折痕带两侧还要再留的交互安全边。Apple 的 region frame 已经包含 20pt
    /// margins；这里再加 8pt，让文字/按钮离曲面更远一点。
    static let foldClearance: CGFloat = 8

    /// 首页分栏所需的**最小内容宽度**：260 + 240 + 16×2 + 16.5 = 548.5pt。
    ///
    /// 注意这不是「手机横屏」的下限：最窄的横屏 iPhone（SE 667×375，无安全区）
    /// 有 667pt，18 Pro（874×402，左右各 62 安全区）有 750pt，两者都在它之上。
    /// 这个下限只用来挡住「横屏但容器窄得放不下两栏」的窗口（分屏 / 折叠态）。
    static let minSplitContentWidth: CGFloat =
        2 * pagePadding + splitSeparatorWidth + minMasterWidth + minDetailWidth

    /// 首页：左月历 + 右选中日。
    ///
    /// 判据只有两条：**横屏** + **两栏都放得下**。
    /// - 竖屏即使够宽也保持原来的年/月/周三态 morph —— 竖屏交互不动。
    /// - 横屏的可用宽度按 `contentWidth` 算（扣掉左右系统占位）。
    ///
    /// 旧实现要求 `contentWidth >= 700`，本意是「月历 280 + 正文 320 + 边距」，
    /// 但那个阈值把 iPhone SE 横屏（667pt，无左右安全区）挡在门外：同样是横屏，
    /// 18 Pro 分栏、SE 却只是把竖屏版面横向拉长，两栏都读不了。现在改为按
    /// **两栏各自的最低可用宽度**判定，任何横屏 iPhone 都能拿到左右双列。
    var splitsMasterDetail: Bool {
        size.width > size.height && contentWidth >= Self.minSplitContentWidth
    }

    /// 分栏时两栏各自的宽度（不计折痕）。保留给既有调用/测试；
    /// 首页实际排版用 `splitMetrics(containerWidth:)`，它会返回动态 gutter。
    ///
    /// 传容器宽（页面几何），不要传 `contentWidth`：这里算的是**实际排版**，
    /// 必须和真正可用的容器对齐。
    func splitColumns(containerWidth: CGFloat) -> (master: CGFloat, detail: CGFloat) {
        let metrics = splitMetrics(containerWidth: containerWidth)
        return (metrics.master, metrics.detail)
    }

    /// 分栏的完整结果：两栏宽度 + 中间空隙。
    ///
    /// 默认按 46% 分主栏。当横屏半折、且折痕带落在分栏区域内时，把折痕带
    /// 整段变成 gutter：左栏在折痕前 `foldClearance` 结束，右栏在折痕后
    /// `foldClearance` 开始。这样内容不会压在曲面上，视觉上接近 Apple 的 50/50。
    /// 折痕贴边、或两栏会被挤到最低宽度以下时退回默认分栏。
    ///
    /// 竖屏半折的**横带**刻意不在这里处理：月历是连续滚动内容，按 Apple 指南
    /// 不需要避让折痕；只有横屏分栏才把竖带当 gutter（D2）。
    func splitMetrics(containerWidth: CGFloat) -> SplitMetrics {
        let base = baseSplitMetrics(containerWidth: containerWidth)
        guard let fold = activeDivision,
              fold.frame.height > fold.frame.width,   // 竖折痕（横屏半折）的带是窄而高
              fold.frame.width > 0,
              fold.frame.minX > Self.pagePadding + Self.foldClearance,
              fold.frame.maxX < containerWidth - Self.pagePadding - Self.foldClearance
        else { return base }

        let gutter = max(Self.splitGutter, fold.frame.width + 2 * Self.foldClearance)
        let master = fold.frame.minX - Self.pagePadding - Self.foldClearance
        let detail = containerWidth
            - 2 * Self.pagePadding
            - (gutter + 0.5)
            - master
        guard master >= Self.minMasterWidth, detail >= Self.minDetailWidth else {
            return base
        }
        return SplitMetrics(master: master, detail: detail, gutter: gutter)
    }

    private func baseSplitMetrics(containerWidth: CGFloat) -> SplitMetrics {
        let available = max(0, containerWidth - 2 * Self.pagePadding - Self.splitSeparatorWidth)
        let preferred = min(Self.maxMasterWidth,
                            max(Self.minMasterWidth, (containerWidth * 0.46).rounded()))
        let master = min(preferred, max(Self.minMasterWidth, available - Self.minDetailWidth))
        return SplitMetrics(master: master,
                            detail: max(Self.minDetailWidth, available - master),
                            gutter: Self.splitGutter)
    }

    /// 分栏时两栏共同的高度（日历区与详情区同高，底部让出系统浮条）。
    ///
    /// 下限 220 是「再矮也没有内容可放」的兜底：到那一步左侧日历会隐藏农历行、
    /// 行高夹在下限（见 `CalendarDensity`），不会把日期压扁。
    func splitPaneHeight(containerHeight: CGFloat) -> CGFloat {
        max(220, containerHeight - Self.splitTopPadding - tabBarClearance)
    }

    // MARK: 单栏（竖屏 / 窄窗口）首页的日历区

    /// 单栏（竖屏 / 窄窗口）首页在**头部之下、系统浮条之上**剩给日历区的整块高度。
    ///
    /// 首页的几何因为 `.ignoresSafeArea(edges: .bottom)` 一直延伸到屏幕底边，
    /// 而系统浮条是**悬在内容之上**的（竖屏 `safeArea.bottom` 只有 home indicator
    /// 的 34pt，浮条自身 83pt 不在安全区里）—— 所以底部必须在这里自己让出
    /// `tabBarClearance`。不让的话，18 Pro 竖屏（402×874，顶部安全区 62）上：
    /// 几何高 812、日历区顶在 y 126；六行月格的底边正好落在 812 + 62 = 874（屏底），
    /// 年历最后一行卡片 709→874，而竖屏浮条的顶边在 y 791 —— 年视图与月视图的
    /// 最后一整行日期都被浮条压住（came in as「首页年/月视图日期被底部导航栏遮挡」）。
    ///
    /// `headerHeight` 由调用方给（首页的头部整块：顶部 12 + 最小高度 52）：它是页面
    /// 自己的排版，不属于版面判定。
    ///
    /// 这里**没有下限兜底**（不同于 `splitPaneHeight` 的 220）：高度真的不够时宁可让
    /// 日历区变矮（内容自己会缩），也不能越过浮条 —— 那就是这次要修的 bug。窄横屏
    /// 单栏（分屏 / 折叠态，浮条 64pt 而屏高只有 375pt）正好落在这个区间。
    func singleColumnCalendarHeight(containerHeight: CGFloat, headerHeight: CGFloat) -> CGFloat {
        max(0, containerHeight - headerHeight - tabBarClearance)
    }

    // MARK: 底部系统浮条

    /// 底部浮条（tab bar）在两种方向上的实测高度：竖屏 83 / 横屏 64。
    ///
    /// 浮条由系统绘制，**两种形态在同一方向上一样高**，与机型、有没有 home
    /// indicator 都无关（UI 测试读 `app.tabBars` frame 实测）：
    /// - iPhone 18 Pro 竖屏 `(0, 791, 402, 83)`、横屏 `(0, 338, 874, 64)`；
    /// - iPhone SE 竖屏 `(0, 584, 375, 83)`、横屏 `(0, 311, 667, 64)`。
    /// 两条都是**紧贴屏幕底边**的，所以要让出的高度就是浮条自身的高度。
    static let tabBarHeightPortrait: CGFloat = 83
    static let tabBarHeightLandscape: CGFloat = 64

    /// 内容忽略底部安全区（`.ignoresSafeArea(edges: .bottom)`）时底部要让出的高度。
    ///
    /// 普通 iPhone 的浮条紧贴屏幕底边，按方向取实测的 83 / 64。iPhone Duo
    /// 的系统栏是**侧置**的（`verticalBarEdge != nil`）：底部没有横条，只剩
    /// home indicator，所以让 `bottomInset` 即可。以前一律按方向减 64/83，
    /// 在 Duo 横屏/外屏会白空一条。
    ///
    /// 旧写法是 `bottomInset + 44`：它在有 home indicator 的机型上（横屏
    /// `bottomInset = 20`）碰巧等于 64，于是 18 Pro 上看起来是对的；但 iPhone SE
    /// 横屏 `bottomInset = 0`，只让出 44pt，最后一行日期会被浮条压住。浮条高度本来
    /// 就与 home indicator 无关，所以横排时直接按方向取，不再叠加 `bottomInset`。
    var tabBarClearance: CGFloat {
        if usesVerticalBars { return bottomInset }
        return isPortrait ? Self.tabBarHeightPortrait : Self.tabBarHeightLandscape
    }

    /// 正文列宽上限。宽屏必须限宽，否则一行 100+ 字。
    ///
    /// 返回的是**去掉页面内边距后的正文列**宽度：调用方把它套在内层 `frame`
    /// 上，再把 `.adaptivePagePadding()`（左右各 16）加在外面。窄屏不能在这里
    /// 再缩一圈 —— 原来的 `size.width - 80` 和页面自己的 16 叠在一起后，竖屏
    /// 日记页的正文列只剩 290pt，顶部的卡片因此比下面的卡片明显偏小。
    func contentColumn(_ maxWidth: CGFloat = 660) -> CGFloat {
        min(maxWidth, max(240, size.width - 2 * Self.pagePadding))
    }

    /// 页面统一的水平内边距。
    ///
    /// 四屏（首页 / 足迹 / 搜索 / 设置）都用这一组数字，宽度才不会各页不同。
    ///
    /// **不要在这里再加安全区**：`adaptiveLayoutReader()` 读的是容器的
    /// 几何，页面内容本身已经落在安全区里（横屏的原点就是 x = 62）。第一版把
    /// `safeArea.leading` 又加了一遍，于是横屏所有页面的内容相对标题栏右移 62pt
    /// （页头在 78、卡片在 140），左半屏白掉一条 —— 和首页分栏那次是同一个错误。
    static let pagePadding: CGFloat = 16
    var leadingPagePadding: CGFloat { Self.pagePadding }
    var trailingPagePadding: CGFloat { Self.pagePadding }

    /// 兜底值只用于「还没读到几何」的一瞬间（例如预览）；真实布局由
    /// `.adaptiveLayoutReader()` 注入。
    static let defaultValue = AdaptiveLayout(
        size: CGSize(width: 390, height: 844),
        safeArea: EdgeInsets()
    )
}

// MARK: - Environment

private struct AdaptiveLayoutKey: EnvironmentKey {
    static let defaultValue = AdaptiveLayout.defaultValue
}

extension EnvironmentValues {
    var adaptiveLayout: AdaptiveLayout {
        get { self[AdaptiveLayoutKey.self] }
        set { self[AdaptiveLayoutKey.self] = newValue }
    }
}

extension View {
    /// 把当前几何与安全区解析成 `AdaptiveLayout` 下发。
    ///
    /// 只在这里读一次几何：页面内部不要再各自读 `UIScreen.main`，也不要用
    /// `GeometryReader` 猜尺寸。用 `onGeometryChange` 而不是包一层
    /// `GeometryReader` —— 后者会让 `TabView` 失去尺寸、还把安全区清零。
    func adaptiveLayoutReader() -> some View {
        modifier(AdaptiveLayoutReader())
    }
}

/// 只比较「会影响版面」的部分，避免滚动时每帧刷新。
/// 标 `nonisolated`：`onGeometryChange` 要求 `T: Sendable`，主 actor 隔离的
/// 一致性无法满足它（Swift 6 的 isolated conformance 规则）。
nonisolated private struct LayoutGeometry: Equatable, Sendable {
    var size: CGSize
    var safe: EdgeInsets
    var division: [FoldRegion]
    var occlusion: [FoldRegion]
}

/// 把 `toolbarVerticalEdge` 从 SwiftUI 环境里带出来。该 key 是 iOS 27.1 才有的，
/// 而 Reader 本身还要在 27.0 上编译，所以只用一个 availability-gated 的
/// 零尺寸探针 + PreferenceKey，而不是给整个 Reader 加 `@available`。
private struct ToolbarVerticalEdgeKey: PreferenceKey {
    static var defaultValue: HorizontalEdge?
    static func reduce(value: inout HorizontalEdge?, nextValue: () -> HorizontalEdge?) {
        value = nextValue() ?? value
    }
}

@available(iOS 27.1, *)
private struct ToolbarVerticalEdgeProbe: View {
    @Environment(\.toolbarVerticalEdge) private var edge

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .preference(key: ToolbarVerticalEdgeKey.self, value: edge)
    }
}

private struct AdaptiveLayoutReader: ViewModifier {
    @State private var layout = AdaptiveLayout.defaultValue
    @State private var verticalBarEdge: HorizontalEdge?

    func body(content: Content) -> some View {
        content
            .background {
                if #available(iOS 27.1, *) {
                    ToolbarVerticalEdgeProbe()
                }
            }
            .onPreferenceChange(ToolbarVerticalEdgeKey.self) { edge in
                verticalBarEdge = edge
            }
            .onGeometryChange(for: LayoutGeometry.self) { proxy in
                LayoutGeometry(size: proxy.size,
                               safe: proxy.safeAreaInsets,
                               division: AdaptiveLayoutReader.divisionRegions(in: proxy),
                               occlusion: AdaptiveLayoutReader.occlusionRegions(in: proxy))
            } action: { geometry in
                let next = AdaptiveLayoutReader.resolve(geometry, verticalBarEdge: verticalBarEdge)
                guard next != layout else { return }
                layout = next
            }
            .environment(\.adaptiveLayout, layout)
    }

    /// iOS 27.1 起系统才会报告折痕 / 摄像头区间；27.0 上返回空数组。
    nonisolated static func divisionRegions(in proxy: GeometryProxy) -> [FoldRegion] {
        guard #available(iOS 27.1, *) else { return [] }
        return proxy.reservedRegions(kind: .division, options: .includeInactive)
            .map(FoldRegion.init)
    }

    nonisolated static func occlusionRegions(in proxy: GeometryProxy) -> [FoldRegion] {
        guard #available(iOS 27.1, *) else { return [] }
        return proxy.reservedRegions(kind: .occlusion)
            .map(FoldRegion.init)
    }

    /// 把几何解析成真实**窗口**尺寸 + 四边安全区 + Duo 环境。
    ///
    /// `GeometryProxy.size` 是**扣掉安全区之后**的内容尺寸（横屏 874×402 会读成
    /// 750×382），拿它判档位会偏小。这里用 **key window 的 bounds**，而不是
    /// `screen.bounds`：iPhone Duo 的 50/50 分屏 / 可缩放窗口里，窗口可能只有
    /// 屏幕的一半，用屏幕尺寸会把 `contentColumn`、`isPortrait` 全部算错。
    /// 若读不到窗口（预览等），才退回内容尺寸。
    nonisolated static func resolve(_ geometry: LayoutGeometry,
                                    verticalBarEdge: HorizontalEdge?) -> AdaptiveLayout {
        // 几何回调由 SwiftUI 在主线程上触发，所以 UIKit 的读取可以安全地圈进
        // `MainActor.assumeIsolated`；只把 Sendable 的值带出这个作用域。
        // 不把整个函数标成 `@MainActor`：`onGeometryChange` 的 action 是
        // nonisolated 的，那样会在调用处换成另一个警告。
        let window = MainActor.assumeIsolated { () -> (size: CGSize, regular: Bool)? in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let window = scene?.keyWindow else { return nil }
            let size = window.bounds.size
            guard size.width > 0, size.height > 0 else { return nil }
            return (size, window.traitCollection.horizontalSizeClass == .regular)
        }
        guard let window else {
            return AdaptiveLayout(size: geometry.size,
                                  safeArea: geometry.safe,
                                  verticalBarEdge: verticalBarEdge,
                                  divisionRegions: geometry.division,
                                  occlusionRegions: geometry.occlusion)
        }
        let result = AdaptiveLayout(size: window.size,
                                    safeArea: geometry.safe,
                                    isRegularWidth: window.regular,
                                    verticalBarEdge: verticalBarEdge,
                                    divisionRegions: geometry.division,
                                    occlusionRegions: geometry.occlusion)
        return result
    }
}

@available(iOS 27.1, *)
extension FoldRegion {
    nonisolated init(_ region: ReservedRegion) {
        self.init(frame: region.frame,
                  margins: region.margins,
                  isActive: region.isActive)
    }
}

extension View {
    /// 应用四屏统一的页面水平边距（见 `AdaptiveLayout.leadingPagePadding`）。
    func adaptivePagePadding() -> some View {
        modifier(AdaptivePagePadding())
    }

    /// 常规宽度的竖屏（iPhone Duo 内屏）把内容限宽并居中。
    ///
    /// Duo 内屏竖屏是 669pt 的 Regular/Regular，直接把 iPhone 单栏拉宽会让
    /// 设置/足迹/搜索的行距显得空。按 D1 的决定只做**限宽居中**，不改这些
    /// 页面的单栏结构与交互；首页保持原样（年/月/周 morph 的几何不受影响）。
    /// 其他形态（普通 iPhone、Duo 横屏、Duo 外屏）不加这一层。
    func regularWidthContentCap(_ width: CGFloat = 600) -> some View {
        modifier(RegularWidthContentCap(width: width))
    }
}

private struct RegularWidthContentCap: ViewModifier {
    @Environment(\.adaptiveLayout) private var layout
    let width: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if layout.isRegularWidth && layout.isPortrait {
            content
                .frame(maxWidth: width)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }
}

private struct AdaptivePagePadding: ViewModifier {
    @Environment(\.adaptiveLayout) private var layout

    func body(content: Content) -> some View {
        content
            .padding(.leading, layout.leadingPagePadding)
            .padding(.trailing, layout.trailingPagePadding)
    }
}
