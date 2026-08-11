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

        func textViewDidChange(_ textView: UITextView) {
            if let pv = textView as? PlaceholderTextView {
                pv.refreshPlaceholder()
            }
            parent.controller.onFormatChange?()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.controller.onFormatChange?()
        }

        func notifyFormatChange() {
            tv?.refreshPlaceholder()
        }
    }
}

struct FontToolbar: View {
    var controller: RichEditorController
    var onTap: (() -> Void)? = nil

    private func btn(_ label: String, active: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onTap?()
        } label: {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(active ? .white : Theme.onSurface())
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(active ? Theme.primary() : .clear)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .scaleEffect(1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                btn(L10n.str("editor_tool_heading"), active: controller.currentHeadingLevel() == 1) {
                    controller.applyHeading(controller.currentHeadingLevel() == 1 ? 0 : 1)
                }
                btn(L10n.str("editor_tool_center"), active: controller.isCenterActive()) {
                    controller.toggleCenter()
                }
                btn(L10n.str("editor_tool_list"), active: false) {
                    controller.toggleList()
                }
                let styles = controller.activeStyles()
                btn(L10n.str("editor_tool_bold"), active: styles.bold) {
                    controller.toggleBold()
                }
                btn(L10n.str("editor_tool_quote"), active: controller.isQuoteActive()) {
                    controller.toggleQuote()
                }
                btn(L10n.str("editor_tool_todo"), active: false) {
                    controller.toggleTodo()
                }
                btn(L10n.str("editor_tool_italic"), active: styles.italic) {
                    controller.toggleItalic()
                }
                btn(L10n.str("editor_tool_strike"), active: styles.strike) {
                    controller.toggleStrike()
                }
                btn(L10n.str("editor_tool_underline"), active: styles.underline) {
                    controller.toggleUnderline()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background {
            GlassCapsule(cornerRadius: 26, blur: 24)
                .shadow(color: Theme.shadowColor(), radius: 14, y: 4)
        }
    }
}
