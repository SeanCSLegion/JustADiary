import SwiftUI
import UIKit

/// 分享面板：**上面（横屏时是左侧）是即将分享的长图预览，下面是系统的分享动作**。
///
/// 旧流程是「点顶部分享 → 弹出一个只有蓝色「分享」按钮的小菜单 → 再点一次才出系统面板」：
/// 多一步，而且点之前根本看不到要分享的是什么。现在顶部分享按钮直接把这块面板拉起来，
/// 预览与系统动作同屏 —— 与「照片」App 分享一张照片的形状一致。
///
/// 系统动作仍由 `UIActivityViewController` 提供（存储图像 / 拷贝 / AirDrop / 发到其它
/// App…），保存到相册等能力因此与系统完全一致，不需要我们自己维护动作列表。它是被
/// **嵌进**这块面板的（不是二次弹窗），所以会连它自己的条目行（缩略图 + 文件名 + 大小）
/// 一起显示 —— 那一行正好用来说明「要分享的是哪个文件」。
///
/// 面板**自己不画标题行、也不画关闭按钮**：预览图顶部就是日期，条目行就是文件名；
/// 关闭用系统条目行右上角那个叉（见 `systemCloseTarget`）。
struct ShareSheetView: View {
    /// 渲染好的分享长图；还没渲染完时为 nil（面板已经拉起，先显示进度）。
    var image: UIImage?
    /// 分享给系统的临时文件；拿不到时退回 `image`。
    var fileURL: URL?
    var onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            // 手机横屏只有 375pt 高：上下排会把预览挤没，改成左右排（预览在左、
            // 系统动作在右），和 App 其它页面的横屏处理保持一致。
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    previewColumn
                    if activityItem != nil {
                        separator
                        activityArea
                            .frame(width: min(430, geo.size.width * 0.55))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    previewColumn
                    if activityItem != nil {
                        separator
                        activityArea
                            .frame(height: activityHeight(in: geo.size.height))
                    }
                }
            }
        }
        .background(Theme.bg().ignoresSafeArea())
    }

    /// 交给系统的分享对象：优先文件 URL（条目行显示文件名 + 真实缩略图）。
    private var activityItem: Any? {
        if let fileURL { return fileURL }
        if let image { return image }
        return nil
    }

    private var separator: some View {
        Divider().overlay(Theme.outlineVariant().opacity(0.5))
    }

    @ViewBuilder
    private var activityArea: some View {
        if let item = activityItem {
            ShareActivityView(item: item, onFinish: onClose)
                .overlay(alignment: .topTrailing) { systemCloseTarget }
        }
    }

    // MARK: - 预览

    private var previewColumn: some View {
        ScrollView(showsIndicators: false) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // 分享图本身 720pt 宽；预览跟着面板宽度走，宽屏也不放大。
                    .frame(maxWidth: 720)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.image, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.image, style: .continuous)
                            .stroke(Theme.onSurface().opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: Theme.shadowColor(), radius: 18, y: 8)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .accessibilityLabel(L10n.str("share_preview_title"))
                    .accessibilityIdentifier("share.preview")
            } else {
                renderingPlaceholder
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var renderingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(L10n.str("share_rendering"))
                .diaryFont(TypeSize.meta)
                .foregroundStyle(Theme.onSurfaceVariant())
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityIdentifier("share.rendering")
    }

    // MARK: - 关闭

    /// 系统条目行右上角那个叉的**真实点击目标**。
    ///
    /// iOS 26/27 的分享面板由**远程视图服务**渲染（宿主视图叫 `ShareSheet.RemoteContainerView`，
    /// 内容在另一个进程里），所以：视图树里找不到那个叉、也没法给它挂 target；而它自带的
    /// dismiss 打在一个并不存在的 presentation controller 上 —— 实测连点四个相邻坐标，
    /// 面板纹丝不动，也就是「看得见、点不动」。
    ///
    /// 用户看到的就是那个叉，它就该能关掉面板，所以这里在它**压着的位置**上放一块透明点击区：
    /// 点到的是系统画的叉，收起来的是我们这块面板。方框取动作区右上角 96×96 ——
    /// 实测竖屏叉在（距右 40、距顶 76）、横屏在（距右 37、距顶 44），都落在框内，
    /// 而框内没有别的可点控件（应用行与动作行都在下方 100pt 开外）。
    private var systemCloseTarget: some View {
        Button {
            Haptics.tap()
            onClose()
        } label: {
            Color.clear
                .frame(width: 96, height: 96)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.str("cancel"))
        .accessibilityIdentifier("share.close")
    }

    /// 系统动作区的高度（竖排时）。
    ///
    /// 动作列表自己会滚动，但**默认**要能整行显示完：系统的「条目行 + 应用行 + 动作行」
    /// 实测约 330pt（iPhone SE 竖屏），少于这个数时最后一行「拷贝 / 保存图像 / 打印」
    /// 的标签会被切一半。上限再照顾预览：预览至少留 200pt。
    private func activityHeight(in sheetHeight: CGFloat) -> CGFloat {
        min(max(340, sheetHeight * 0.48), max(280, sheetHeight - 200))
    }
}

// MARK: - 系统分享动作

/// 包一层 `UIActivityViewController`，把它放进我们自己的面板里。
///
/// 它是普通的 UIViewController，`UIViewControllerRepresentable` 会按子控制器把它挂好，
/// 所以「存储图像」这类动作弹出的权限提示、进度都能正常 present。
private struct ShareActivityView: UIViewControllerRepresentable {
    var item: Any
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item],
                                                  applicationActivities: nil)
        // 动作完成后把整个面板收起来（系统面板本来就是这样：选完就消失）。
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.onFinish?()
        }
        context.coordinator.onFinish = onFinish
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    /// 动作列表是滚动视图，没有固有高度：按被提议的尺寸铺满，让它自己内部滚动。
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiViewController: UIActivityViewController,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 360)
    }

    final class Coordinator {
        var onFinish: (() -> Void)?
    }
}
