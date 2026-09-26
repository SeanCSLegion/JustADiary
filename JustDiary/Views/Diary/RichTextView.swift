import SwiftUI
import UIKit

final class PlaceholderTextView: UITextView {
    var placeholder: String? {
        didSet { placeholderLabel.text = placeholder }
    }

    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = Theme.onSurfaceVariantUIColor()
        placeholderLabel.numberOfLines = 0
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Placeholder text is drawn by a plain `UILabel`, so it has to be scaled by
    /// hand — otherwise the hint stays at the design size while the text the
    /// user types next to it grows.
    func applyTypeSize(_ typeSize: DynamicTypeSize) {
        let font = UIFont.diary(EditorDesignSize.body, typeSize: typeSize)
        self.font = font
        placeholderLabel.font = font
        minimumHeight = (160 * DynamicTypeMetrics.multiplier(for: EditorDesignSize.body, typeSize: typeSize)).rounded()
        setNeedsLayout()
    }

    /// Minimum height of the input area: the 160pt the design shipped with,
    /// grown by the body style's Dynamic Type multiplier.
    ///
    /// It used to be a hard 160pt. That is right at the default text size, but at
    /// the largest accessibility sizes the placeholder grew while the field
    /// stayed put, so the hint filled most of the input area. Scaling by the
    /// *style's* factor (not one global number) keeps the default design
    /// untouched and matches how `TabBarClearance` and the other minimum heights
    /// in the app grow.
    /// 输入区的最小高度（`160 × 动态字号系数`）；`RichTextView.sizeThatFits` 也要用它，
    /// 否则 SwiftUI 会按「一行文字」的高度排版，编辑区塌成 41pt。
    private(set) var minimumHeight: CGFloat = 160

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 340
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minimumHeight, size.height))
    }

    /// 输入区宽度变化时的回调（旋转、分屏）。
    ///
    /// 不能只靠 `updateUIView`：SwiftUI 在「只有尺寸变化」时不保证再调它 —— 实测
    /// SE 横屏插入的图片（611pt）转过竖屏后仍是 611pt，而正文列只有 319pt。
    var onTextWidthChange: ((CGFloat) -> Void)?
    private var reportedWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        // 布局期间不能改文本存储（布局管理器正在用），推到下一轮 runloop 再做。
        if bounds.width > 40, abs(bounds.width - reportedWidth) > 1 {
            reportedWidth = bounds.width
            let width = bounds.width
            DispatchQueue.main.async { [weak self] in
                self?.onTextWidthChange?(width)
            }
        }
        let inset = textContainerInset
        // The placeholder must be able to grow: a fixed 22pt height clipped the
        // hint once the user raised the system text size.
        let height = placeholderLabel.font.lineHeight
        // 与正文左边界对齐（`textContainer.lineFragmentPadding` 是 0）。
        placeholderLabel.frame = CGRect(x: inset.left,
                                        y: inset.top,
                                        width: max(0, bounds.width - inset.left - inset.right - 10),
                                        height: ceil(height))
    }

    override var text: String! {
        didSet { placeholderLabel.isHidden = !text.isEmpty }
    }

    func refreshPlaceholder() {
        placeholderLabel.text = placeholder
        placeholderLabel.isHidden = !text.isEmpty
    }
}

struct RichTextView: UIViewRepresentable {
    let controller: RichEditorController
    var placeholder: String
    var autoFocus = false
    var loadToken: Int = 0
    var loadParts: [ContentPart] = []

    @Environment(\.diaryDynamicTypeSize) private var typeSize

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// 让 UITextView 老老实实按**被提议的宽度**排版（`ReadTextView` 已有同款实现）。
    ///
    /// 不实现时 SwiftUI 走 `intrinsicContentSize`，那里的宽度兜底是 340pt：SE 上卡片
    /// 343 − 内边距 24 = 提议 319，却被兜底撑到 340 —— 正文与图片横向溢出卡片。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView,
                      context: Context) -> CGSize? {
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite, proposed > 0 {
            width = proposed
        } else if uiView.bounds.width > 0 {
            width = uiView.bounds.width
        } else {
            return nil
        }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // 不能用裸的 `sizeThatFits`：它不含输入区的最小高度（160 × 动态字号系数）。
        return CGSize(width: width, height: max(uiView.minimumHeight, ceil(measured.height)))
    }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let tv = PlaceholderTextView(frame: .zero, textContainer: nil)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        // 左右不再内缩：卡片自己的内边距（12）已经让出位置，再缩 12 会让编辑态的正文
        // 比阅读态窄 24pt（图片也跟着窄）。上下留 10pt 给首行与光标一点余量。
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.textColor = Theme.onSurfaceUIColor()
        tv.tintColor = Theme.primaryUIColor()
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = false
        tv.showsVerticalScrollIndicator = false
        tv.placeholder = placeholder
        controller.dynamicTypeSize = typeSize
        context.coordinator.appliedTypeSize = typeSize
        tv.applyTypeSize(typeSize)
        controller.textView = tv
        controller.onFormatChange = {
            context.coordinator.notifyFormatChange()
        }
        context.coordinator.tv = tv
        tv.onTextWidthChange = { [weak controller] width in
            controller?.handleTextWidthChange(width)
        }
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                tv.becomeFirstResponder()
            }
        }
        return tv
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        uiView.placeholder = placeholder
        if context.coordinator.appliedTypeSize != typeSize {
            context.coordinator.appliedTypeSize = typeSize
            uiView.applyTypeSize(typeSize)
            controller.reapplyTypeSize(typeSize)
        }
        // 宽度（旋转、分屏）交给 `handleTextWidthChange` 一处处理：`layoutSubviews`
        // 也会调它，因为 SwiftUI 在「只有尺寸变化」时不一定再调 `updateUIView`。
        controller.handleTextWidthChange(uiView.bounds.width)
        if loadToken != context.coordinator.lastToken {
            if loadParts.isEmpty {
                controller.clear()
            } else {
                controller.load(parts: loadParts)
            }
            context.coordinator.lastToken = loadToken
        }
        uiView.refreshPlaceholder()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: RichTextView
        weak var tv: PlaceholderTextView?
        var lastToken = 0
        var appliedTypeSize: DynamicTypeSize = .large

        init(_ parent: RichTextView) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // While a centered paragraph is empty, ignore a newline keystroke so
            // users cannot create a cascade of blank centered lines without typing.
            if text == "\n" {
                let caret = textView.selectedRange.location
                if parent.controller.shouldBlockNewline(at: caret) {
                    return false
                }
                // List/to-do items — and an empty quoted line, which ends the
                // quote — handle Return themselves: the marker for the next item
                // is a real character, not something UIKit's own newline can
                // carry over.
                if parent.controller.handleReturn(at: caret) {
                    return false
                }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            if let pv = textView as? PlaceholderTextView {
                pv.refreshPlaceholder()
            }
            parent.controller.notifyFormatChange()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.controller.notifyFormatChange()
        }

        func notifyFormatChange() {
            tv?.refreshPlaceholder()
        }
    }
}

/// 格式栏始终是**横排**的一行，贴在键盘上方（与 Apple 备忘录一致：备忘录的键盘上方
/// 工具栏在横竖屏都是横向、可横向滑动的）。
///
/// 它一度在横屏宽屏时改成贴在正文右侧的竖排面板，但 9 个按钮竖排比横屏可用高度还高
/// （iPhone 18 Pro 横屏只有 402pt，竖排约 454pt），条本身被屏幕裁掉、又贴在整个屏幕的
/// 底部中间，和正文列对不上，于是横屏一进编辑就看不出这是个格式栏。
struct FontToolbar: View {
    var controller: RichEditorController
    var onTap: (() -> Void)? = nil

    private func btn(_ systemName: String, accessibilityLabel: String, active: Bool,
                     disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
            onTap?()
        } label: {
            Image(systemName: systemName)
                .diaryFont(15, weight: .medium)
                .foregroundStyle(active ? .white : Theme.onSurface())
                .frame(minWidth: 34, minHeight: 40)
                .contentShape(Capsule())
                .background {
                    Capsule().fill(active ? Theme.primary() : .clear)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// Paragraph-style picker, the equivalent of the style list in Notes' "Aa"
    /// menu. It replaces the old heading toggle, which could only ever switch
    /// between h1 and body — an h2 was reachable only in imported documents.
    private var styleMenu: some View {
        let current = controller.currentBlockStyle()
        let active = current != .body
        return Menu {
            ForEach(EditorBlockStyle.menuStyles, id: \.self) { style in
                Button {
                    Haptics.tap()
                    controller.applyBlockStyle(style)
                    onTap?()
                } label: {
                    if style == current {
                        Label(L10n.str(style.localizationKey), systemImage: "checkmark")
                    } else {
                        Text(L10n.str(style.localizationKey))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "textformat.size")
                    .diaryFont(15, weight: .medium)
                Image(systemName: "chevron.down")
                    .diaryFont(9, weight: .semibold)
            }
            .foregroundStyle(active ? .white : Theme.onSurface())
            .frame(minWidth: 46, minHeight: 40)
            .contentShape(Capsule())
            .background {
                Capsule().fill(active ? Theme.primary() : .clear)
            }
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityLabel(L10n.str("editor_tool_style"))
        .accessibilityValue(L10n.str(current.localizationKey))
    }

    /// The buttons at their intrinsic width.
    ///
    /// Spacing is 4pt, not 6: at the default text size the nine controls then
    /// add up to ~360pt and the whole bar fits a 402pt phone in one piece
    /// (with 6pt it came to ~404pt and the last button hung off the edge).
    private var barRow: some View {
        // 状态在这里重新取一次：`ViewThatFits` 会量两遍，而且这些读取本来就让
        // body 依赖 `formatTick`（按钮状态才会跟着光标 / 编辑实时更新）。
        let styles = controller.activeStyles()
        let center = controller.isCenterActive()
        let list = controller.isListActive()
        let quote = controller.isQuoteActive()
        let todo = controller.isTodoActive()
        let blockStyleActive = list || quote || todo
        return HStack(spacing: 4) {
            styleMenu
            btn("text.aligncenter", accessibilityLabel: L10n.str("editor_tool_center"),
                active: center, disabled: blockStyleActive) {
                controller.toggleCenter()
            }
            Divider()
                .frame(height: 20)
                .overlay(Theme.outlineVariant().opacity(0.5))
            btn("list.bullet", accessibilityLabel: L10n.str("editor_tool_list"),
                active: list) {
                controller.toggleList()
            }
            btn("text.quote", accessibilityLabel: L10n.str("editor_tool_quote"),
                active: quote) {
                controller.toggleQuote()
            }
            btn("checklist", accessibilityLabel: L10n.str("editor_tool_todo"),
                active: todo) {
                controller.toggleTodo()
            }
            Divider()
                .frame(height: 20)
                .overlay(Theme.outlineVariant().opacity(0.5))
            btn("bold", accessibilityLabel: L10n.str("editor_tool_bold"),
                active: styles.bold) {
                controller.toggleBold()
            }
            btn("italic", accessibilityLabel: L10n.str("editor_tool_italic"),
                active: styles.italic) {
                controller.toggleItalic()
            }
            btn("strikethrough", accessibilityLabel: L10n.str("editor_tool_strike"),
                active: styles.strike) {
                controller.toggleStrike()
            }
            btn("underline", accessibilityLabel: L10n.str("editor_tool_underline"),
                active: styles.underline) {
                controller.toggleUnderline()
            }
        }
        .padding(.vertical, 8)
    }

    var body: some View {
        // The bar is only as wide as its buttons (centred by the page), instead
        // of stretching across the whole screen: in landscape a full-width strip
        // under a 620pt column read as a toolbar twice the size it needed. When
        // the buttons genuinely cannot fit — a large accessibility text size —
        // the second variant takes over and scrolls, like Notes' toolbar.
        ViewThatFits(in: .horizontal) {
            barRow
            ScrollView(.horizontal, showsIndicators: false) {
                barRow
            }
        }
        .padding(.horizontal, 12)
        // Exposed as a container so a UI test can assert the bar's own frame
        // (横屏曾经竖排、比屏幕还高，只能从整条的 frame 上看出来).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.formatBar")
        .background {
            // The formatting bar floats above the editor's content, which is
            // precisely the navigation/control layer Liquid Glass is for. It
            // used to be an opaque grouped-background rect, so it read as one
            // more content card rather than as a control.
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.interactive(true),
                             in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                .shadow(color: Theme.shadowColor(), radius: 14, y: 4)
        }
        // Establishing a dependency on the @Observable formatTick makes SwiftUI
        // re-evaluate body (and thus the button active states) whenever the
        // controller mutation/tick changes — no explicit @State refetch needed.
        .onChange(of: controller.formatTick) { _, _ in }
    }
}
