import SwiftUI

/// 版面判定：整套设计的**唯一**判据。
///
/// 关键约束（来自 Apple 的 iPhone Duo 适配指南与 HIG Layout）：
/// - 只看**当前可用宽度/高度**，不看 `UIDevice.idiom`、不看 orientation、
///   不读 `UIScreen.main` —— Duo 展开后仍是 iPhone 但宽高都是 regular，
///   任何按机型分支的代码在它上面都会错。
/// - 左右安全区**分别**读取（横屏时 `leading` 往往非 0）。
/// - 数值都要能从 `safeAreaInsets` 派生，不要写死设备常量。
///
/// 当前只做**手机竖屏 / 手机横屏**两套版面：横屏且内容宽度够时首页左右分栏。
/// iPad / Mac 的分栏与多列卡片是未定稿的「骨架先行版」，已按需求移除，等
/// 重新设计后再做（设计稿仍在 `docs/design/`）。
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
    /// 横屏时左侧那条系统浮条（`leading = 62`）不参与分栏计算 —— 否则
    /// 「874 够宽」会得出一个实际只有 750 能用的结论。
    var contentWidth: CGFloat {
        max(0, size.width - max(0, safeArea.leading) - max(0, safeArea.trailing))
    }

    /// 首页：左月历 + 右选中日（手机横屏）。
    ///
    /// **必须同时**满足「宽度够」与「横屏」两个条件：
    /// - 竖屏即使够宽也保持原来的年/月/周三态 morph —— 竖屏交互不动。
    /// - 横屏的可用宽度要扣掉左侧系统占位（750pt），所以阈值按内容宽度算。
    var splitsMasterDetail: Bool {
        contentWidth >= 700 && size.width > size.height
    }

    /// 「宽但不矮」的尺寸（竖屏、Duo 竖屏）：保持单栏。
    var isPortrait: Bool { size.height >= size.width }

    /// 主栏（月历）宽度。
    ///
    /// 月历 7 列每格至少 ~40pt 才好点，所以主栏取「可用宽度的 46%」并夹在
    /// 280…440 之间；比这更宽只是在拉大格子，并不会让内容更好读。
    var masterWidth: CGFloat {
        min(440, max(280, (contentWidth * 0.46).rounded()))
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
