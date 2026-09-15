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
        placeholderLabel.font = UIFont.systemFont(ofSize: 15)
        placeholderLabel.numberOfLines = 0
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 340
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(160, size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        placeholderLabel.frame = CGRect(x: inset.left + 5,
                                        y: inset.top,
                                        width: bounds.width - inset.left - inset.right - 10,
                                        height: 22)
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
        tv.font = UIFont.systemFont(ofSize: 15)
        tv.textColor = Theme.onSurfaceUIColor()
        tv.tintColor = Theme.primaryUIColor()
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = false
        tv.showsVerticalScrollIndicator = false
        tv.placeholder = placeholder
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
        let width = uiView.bounds.width
        if width > 40 {
            let inset = uiView.textContainerInset
            let available = max(60, width - inset.left - inset.right)
            if controller.imageMaxWidth == nil || abs((controller.imageMaxWidth ?? 0) - available) > 1 {
                controller.imageMaxWidth = available
                if context.coordinator.lastToken == loadToken, !loadParts.isEmpty {
                    controller.load(parts: loadParts)
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
                .font(.system(size: 15, weight: .medium))
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

    @ViewBuilder
    var body: some View {
        // Observing the controller's format tick re-evaluates this body after
        // every edit/cursor move/format toggle, keeping the button states live.
        let styles = controller.activeStyles()
        let heading = controller.currentHeadingLevel() == 1
        let center = controller.isCenterActive()
        let list = controller.isListActive()
        let quote = controller.isQuoteActive()
        let todo = controller.isTodoActive()
        let blockStyleActive = list || quote || todo

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                btn("textformat.size", accessibilityLabel: L10n.str("editor_tool_heading"),
                    active: heading) {
                    controller.applyHeading(controller.currentHeadingLevel() == 1 ? 0 : 1)
                }
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
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Theme.outlineVariant().opacity(0.45), lineWidth: 0.5)
                }
                .shadow(color: Theme.shadowColor(), radius: 14, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        // Establishing a dependency on the @Observable formatTick makes SwiftUI
        // re-evaluate body (and thus the button active states) whenever the
        // controller mutation/tick changes — no explicit @State refetch needed.
        .onChange(of: controller.formatTick) { _, _ in }
    }
}
