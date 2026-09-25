import SwiftUI

/// 版面判定：整套设计的**唯一**判据。
///
/// 关键约束（来自 Apple 的 iPhone Duo 适配指南与 HIG Layout）：
/// - 只看**当前可用宽度/高度**，不看 `UIDevice.idiom`、不看 orientation、
///   不读 `UIScreen.main` —— Duo 展开后仍是 iPhone 但宽高都是 regular，
///   任何按机型分支的代码在它上面都会错。
/// - 左右安全区**分别**读取（横屏时 `leading` 往往非 0）。
/// - 数值优先从几何 / `safeAreaInsets` 派生，不要写死设备常量。唯一的例外是底部
///   系统浮条的高度：浮条由系统绘制，安全区里推不出来（SE 横屏 `bottomInset = 0`
///   但浮条照样占 64pt），所以按方向取实测值，见 `tabBarClearance`。
///
/// 当前只做**手机竖屏 / 手机横屏**两套版面：横屏首页左右分栏（两栏都放得下时），
/// 其余页面仍是单栏。
struct AdaptiveLayout: Equatable {
    var size: CGSize
    /// 四边安全区，分别保存（横屏时 leading / trailing 常不相等）。
    var safeArea: EdgeInsets

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

    /// 分栏时两栏各自的宽度。
    ///
    /// 主栏先按容器宽的 46% 取（夹在 `minMasterWidth…maxMasterWidth`），但必须给
    /// 详情栏留够 `minDetailWidth`，所以上界再夹一次；详情栏吃掉剩下的宽度。
    /// 两栏之和 + 页边距 + 分隔线**正好**等于容器宽，横屏任何宽度都不会横向溢出
    /// （由 `SplitLayoutTests` 在阈值以上的每一档宽度上守住）。
    ///
    /// 传容器宽（页面几何），不要传 `contentWidth`：这里算的是**实际排版**，
    /// 必须和真正可用的容器对齐。
    func splitColumns(containerWidth: CGFloat) -> (master: CGFloat, detail: CGFloat) {
        let available = max(0, containerWidth - 2 * Self.pagePadding - Self.splitSeparatorWidth)
        let preferred = min(Self.maxMasterWidth,
                            max(Self.minMasterWidth, (containerWidth * 0.46).rounded()))
        let master = min(preferred, max(Self.minMasterWidth, available - Self.minDetailWidth))
        return (master, max(Self.minDetailWidth, available - master))
    }

    /// 分栏时两栏共同的高度（日历区与详情区同高，底部让出系统浮条）。
    ///
    /// 下限 220 是「再矮也没有内容可放」的兜底：到那一步日历密度会自己降级成
    /// 周条，不会把日期压扁。
    func splitPaneHeight(containerHeight: CGFloat) -> CGFloat {
        max(220, containerHeight - Self.splitTopPadding - tabBarClearance)
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
    /// 旧写法是 `bottomInset + 44`：它在有 home indicator 的机型上（横屏
    /// `bottomInset = 20`）碰巧等于 64，于是 18 Pro 上看起来是对的；但 iPhone SE
    /// 横屏 `bottomInset = 0`，只让出 44pt，最后一行日期会被浮条压住。浮条高度本来
    /// 就与 home indicator 无关，所以这里直接按方向取，不再叠加 `bottomInset`。
    var tabBarClearance: CGFloat {
        isPortrait ? Self.tabBarHeightPortrait : Self.tabBarHeightLandscape
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
}

private struct AdaptiveLayoutReader: ViewModifier {
    @State private var layout = AdaptiveLayout.defaultValue

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: LayoutGeometry.self) { proxy in
                LayoutGeometry(size: proxy.size, safe: proxy.safeAreaInsets)
            } action: { geometry in
                let next = AdaptiveLayoutReader.resolve(geometry)
                guard next != layout else { return }
                layout = next
            }
            .environment(\.adaptiveLayout, layout)
    }

    /// 把几何解析成真实界面尺寸 + 四边安全区。
    ///
    /// `GeometryProxy.size` 是**扣掉安全区之后**的内容尺寸（横屏 874×402 会读成
    /// 750×382），拿它判档位会偏小，所以这里用场景的 `screen.bounds` 作为界面尺寸，
    /// 并把「内容尺寸 → 界面尺寸」的差值当作安全区。若读不到场景（预览等），
    /// 就退回内容尺寸 + 0 安全区 —— 那条路径只影响预览，不影响真机。
    nonisolated static func resolve(_ geometry: LayoutGeometry) -> AdaptiveLayout {
        // 几何回调由 SwiftUI 在主线程上触发，所以 UIKit 的读取可以安全地圈进
        // `MainActor.assumeIsolated`；只把 Sendable 的 `CGSize` 带出这个作用域。
        // 不把整个函数标成 `@MainActor`：`onGeometryChange` 的 action 是
        // nonisolated 的，那样会在调用处换成另一个警告。
        let screenSize = MainActor.assumeIsolated { () -> CGSize? in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let size = scene?.screen.bounds.size, size.width > 0, size.height > 0 else {
                return nil
            }
            return size
        }
        guard let bounds = screenSize else {
            return AdaptiveLayout(size: geometry.size, safeArea: geometry.safe)
        }
        let dw = max(0, bounds.width - geometry.size.width)
        let dh = max(0, bounds.height - geometry.size.height)
        var insets = geometry.safe
        if insets.leading + insets.trailing < dw - 1 {
            // 差值多于左右安全区之和：说明还夹着导航条之类的条带，补到后沿。
            insets.trailing = max(insets.trailing, dw - insets.leading)
        }
        if insets.top + insets.bottom < dh - 1 {
            insets.bottom = max(insets.bottom, dh - insets.top)
        }
        return AdaptiveLayout(size: bounds, safeArea: insets)
    }
}

extension View {
    /// 应用四屏统一的页面水平边距（见 `AdaptiveLayout.leadingPagePadding`）。
    func adaptivePagePadding() -> some View {
        modifier(AdaptivePagePadding())
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
