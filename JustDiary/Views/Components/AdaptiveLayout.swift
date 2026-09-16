import SwiftUI

/// 版面判定：整套自适应设计的**唯一**判据。
///
/// 关键约束（来自 Apple 的 iPhone Duo 适配指南与 HIG Layout）：
/// - 只看**当前可用宽度/高度**，不看 `UIDevice.idiom`、不看 orientation、
///   不读 `UIScreen.main` —— Duo 展开后仍是 iPhone 但宽高都是 regular，
///   任何按机型分支的代码在它上面都会错。
/// - 左右安全区**分别**读取（横屏时 `leading` 往往非 0）。
/// - 数值都要能从 `safeAreaInsets` 派生，不要写死设备常量。
///
/// 三档宽度（对应 docs/adaptive-layout-plan.md §2.1）：
///
/// | 档 | 宽度 | 导航 | 页内分栏 | 卡片列数 |
/// |---|---|---|---|---|
/// | compact | < 700 | 底部浮条 | 无 | 1 |
/// | medium  | 700–999 | 底部浮条 | 有 | 1–2 |
/// | wide    | ≥ 1000 | 系统侧边栏（≥1100 时） | 有 | 2–3 |
struct AdaptiveLayout: Equatable {
    enum Tier: Equatable {
        case compact
        case medium
        case wide
    }

    var size: CGSize
    /// 四边安全区，分别保存（横屏时 leading / trailing 常不相等）。
    var safeArea: EdgeInsets

    var tier: Tier {
        if size.width >= 1000 { return .wide }
        if size.width >= 700 { return .medium }
        return .compact
    }

    // MARK: 内容边距

    /// 内容区的水平边距，直接采用系统的 layout margin（已包含安全区）。
    var contentInset: CGFloat { max(0, safeArea.leading) }
    var trailingInset: CGFloat { max(0, safeArea.trailing) }

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
    var contentWidth: CGFloat { max(0, size.width - contentInset - trailingInset) }

    /// 首页：左月历 + 右选中日。
    ///
    /// **必须同时**满足「宽度够」与「横屏」两个条件：
    /// - 竖屏即使够宽（iPad 竖屏 1032pt）也保持原来的年/月/周三态 morph —— 竖屏交互不动。
    /// - 横屏的可用宽度要扣掉左侧系统占位（750pt），所以阈值按内容宽度算。
    var splitsMasterDetail: Bool {
        contentWidth >= 700 && size.width > size.height
    }

    /// iPad 竖屏、Duo 竖屏这类「宽但不矮」的尺寸：保持单栏。
    var isPortrait: Bool { size.height >= size.width }
    /// 足迹：左统计 + 图表 / 右地点清单。
    var splitsDashboard: Bool { contentWidth >= 900 }
    /// 搜索：条件/结果分栏。
    var splitsSearch: Bool { contentWidth >= 800 }

    /// 主栏（月历）宽度。
    ///
    /// 月历 7 列每格至少 ~40pt 才好点，所以主栏取「可用宽度的 46%」并夹在
    /// 280…440 之间；比这更宽只是在拉大格子，并不会让内容更好读。
    var masterWidth: CGFloat {
        min(440, max(280, (contentWidth * 0.46).rounded()))
    }

    /// 卡片列数（设置页、宽屏卡片流）。
    var cardColumns: Int {
        if size.width >= 1000 { return 3 }
        if size.width >= 680 { return 2 }
        return 1
    }

    /// 正文列宽上限。宽屏必须限宽，否则一行 100+ 字。
    func contentColumn(_ maxWidth: CGFloat = 660) -> CGFloat {
        min(maxWidth, max(240, size.width - 80))
    }

    /// 页面统一的水平内边距。
    ///
    /// 四屏（首页 / 足迹 / 搜索 / 设置）都用这一组数字，宽度才不会各页不同：
    /// 左侧 = 系统占位 + 16，右侧 = 16。竖屏系统占位是 0，于是就是 16 / 16。
    static let pagePadding: CGFloat = 16
    var leadingPagePadding: CGFloat { contentInset + Self.pagePadding }
    var trailingPagePadding: CGFloat { Self.pagePadding }

    /// 日历密度：高度不足时从「月格」降级为「周条」。
    ///
    /// 一屏放得下几周，由可用高度决定；每行至少 44pt 才放得下 20pt 日号 +
    /// 农历行 + 选中圆。
    var calendarRows: Int {
        max(1, min(6, Int(availableCalendarHeight / 44)))
    }

    /// 日历可用高度：扣掉顶部标题行与底部预留。
    private var availableCalendarHeight: CGFloat {
        max(80, size.height - bottomInset - 20)
    }

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
                AdaptiveLayoutReader.log(next)
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
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else {
            return AdaptiveLayout(size: geometry.size, safeArea: geometry.safe)
        }
        let bounds = scene.screen.bounds.size
        guard bounds.width > 0, bounds.height > 0 else {
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

    /// TEMP: 只在带 `-dump-chrome` 启动时写日志，用来核对真实安全区。
    nonisolated static func log(_ layout: AdaptiveLayout) {
        guard ProcessInfo.processInfo.arguments.contains("-dump-chrome") else { return }
        let s = layout.safeArea
        let line = "size=\(Int(layout.size.width))x\(Int(layout.size.height)) "
            + "tier=\(layout.tier) "
            + "T\(Int(s.top)) L\(Int(s.leading)) B\(Int(s.bottom)) R\(Int(s.trailing)) "
            + "master=\(Int(layout.masterWidth))\n"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chrome.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
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
