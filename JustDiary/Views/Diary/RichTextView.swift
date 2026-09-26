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
    private var minimumHeight: CGFloat = 160

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 340
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minimumHeight, size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        // The placeholder must be able to grow: a fixed 22pt height clipped the
        // hint once the user raised the system text size.
        let height = placeholderLabel.font.lineHeight
        placeholderLabel.frame = CGRect(x: inset.left + 5,
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

    func makeUIView(context: Context) -> PlaceholderTextView {
        let tv = PlaceholderTextView(frame: .zero, textContainer: nil)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
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
        let width = uiView.bounds.width
        if width > 40 {
            let inset = uiView.textContainerInset
            let available = max(60, width - inset.left - inset.right)
            if controller.imageMaxWidth == nil || abs((controller.imageMaxWidth ?? 0) - available) > 1 {
                let measured = controller.imageMaxWidth
                controller.imageMaxWidth = available
                // A width change (rotation, split view) used to reload
                // `loadParts` — the snapshot this editor opened with — which
                // silently threw away everything typed since. Only the images
                // need re-fitting: the text and the caret stay where they are.
                // The first measurement needs no refit because the text has not
                // been loaded yet; the load below picks the width up.
                if measured != nil {
                    controller.refitImages(maxWidth: available)
                }
            }
        }
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

    @ViewBuilder
    var body: some View {
        // Observing the controller's format tick re-evaluates this body after
        // every edit/cursor move/format toggle, keeping the button states live.
        let styles = controller.activeStyles()
        let center = controller.isCenterActive()
        let list = controller.isListActive()
        let quote = controller.isQuoteActive()
        let todo = controller.isTodoActive()
        let blockStyleActive = list || quote || todo

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
