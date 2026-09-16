import SwiftUI
import UIKit

final class FittedTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 320
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

struct ReadTextView: UIViewRepresentable {
    var parts: [ContentPart]
    var keyword: String = ""
    var onToggleTodo: ((Int, Int) -> Void)? = nil
    var onImageTap: ((String, CGFloat) -> Void)? = nil
    var onTapText: (() -> Void)? = nil
    var textContainerInset: UIEdgeInsets = .zero

    @Environment(\.diaryDynamicTypeSize) private var typeSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FittedTextView {
        let tv = FittedTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = textContainerInset
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = nil
        tv.isSelectable = false
        context.coordinator.textView = tv
        context.coordinator.rebuild()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)
        return tv
    }

    func updateUIView(_ uiView: FittedTextView, context: Context) {
        context.coordinator.parent = self
        let sizeChanged = context.coordinator.typeSize != typeSize
        if !sizeChanged, context.coordinator.lastParts == parts, context.coordinator.lastKeyword == keyword {
            return
        }
        context.coordinator.typeSize = typeSize
        context.coordinator.lastParts = parts
        context.coordinator.lastKeyword = keyword
        context.coordinator.rebuild()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ReadTextView
        weak var textView: FittedTextView?
        var todoRanges: [NSRange] = []
        var todoCallbacks: [(Int, Int)] = []
        var imageRanges: [NSRange] = []
        var imageCallbacks: [(String, CGFloat)] = []
        var lastParts: [ContentPart]?
        var lastKeyword: String?
        var typeSize: DynamicTypeSize = .large

        init(_ parent: ReadTextView) {
            self.parent = parent
        }

        func rebuild() {
            guard let tv = textView else { return }
            let attributed = NSMutableAttributedString(
                attributedString: PartsCodec.attributedString(from: parent.parts, typeSize: typeSize)
            )
            todoRanges = []
            todoCallbacks = []
            imageRanges = []
            imageCallbacks = []
            var todoOrder: [(Int, Int)] = []
            for (pi, part) in parent.parts.enumerated() where part.style == ContentPartStyle.todo {
                for ii in (part.items ?? []).indices { todoOrder.append((pi, ii)) }
            }
            var todoIdx = 0
            let ns = attributed.string as NSString
            var cursor = 0
            while cursor < ns.length {
                var effective = NSRange()
                guard let payload = (attributed.attribute(.attachment, at: cursor, effectiveRange: &effective) as? PayloadAttachment)?.payload else {
                    cursor += 1
                    continue
                }
                let markerRange = effective
                if payload.kind == "todo" {
                    let lineEnd = ns.rangeOfCharacter(from: .newlines, options: [],
                                                       range: NSRange(location: markerRange.location,
                                                                      length: ns.length - markerRange.location))
                    let end = lineEnd.location == NSNotFound ? ns.length : lineEnd.location
                    todoRanges.append(NSRange(location: markerRange.location, length: end - markerRange.location))
                    if todoIdx < todoOrder.count { todoCallbacks.append(todoOrder[todoIdx]) }
                    todoIdx += 1
                } else if payload.kind == "image", !payload.src.isEmpty {
                    imageRanges.append(NSRange(location: markerRange.location, length: 1))
                    imageCallbacks.append((payload.src, payload.h / max(1, payload.w)))
                }
                cursor = markerRange.location + markerRange.length
            }
            if !parent.keyword.isEmpty {
                applyHighlight(attributed)
            }
            if !attributed.isEqual(to: tv.attributedText) {
                tv.attributedText = attributed
            }
        }

        private func applyHighlight(_ attributed: NSMutableAttributedString) {
            let segments = SearchUtil.highlightSegments(attributed.string, keyword: parent.keyword)
            var cursor = 0
            for seg in segments {
                let len = (seg.text as NSString).length
                let range = NSRange(location: cursor, length: len)
                if seg.hit, range.length > 0, range.location < attributed.length {
                    attributed.addAttribute(.backgroundColor, value: Theme.primaryContainerUIColor(), range: range)
                    attributed.addAttribute(.foregroundColor, value: Theme.primaryUIColor(), range: range)
                    // This used to hard-code a 15pt medium font, which both
                    // ignored the text-size setting and reset a highlighted
                    // heading to body size. Resolve the run's own design size
                    // instead and keep it on the Dynamic Type curve.
                    let current = attributed.attributes(at: range.location, effectiveRange: nil)
                    let design = EditorFont.designSize(of: current, typeSize: typeSize) ?? EditorDesignSize.body
                    let bold = (current[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
                    for (key, value) in EditorFont.attributes(design,
                                                              block: EditorFont.blockStyle(of: current),
                                                              weight: bold ? .bold : .medium,
                                                              typeSize: typeSize) {
                        attributed.addAttribute(key, value: value, range: range)
                    }
                }
                cursor += len
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let tv = textView else { return }
            let location = gesture.location(in: tv)
            var position = UITextPosition()
            if let pos = tv.closestPosition(to: location) {
                position = pos
            }
            let offset = tv.offset(from: tv.beginningOfDocument, to: position)
            for (i, range) in todoRanges.enumerated() where NSLocationInRange(offset, range) {
                let cb = todoCallbacks[i]
                parent.onToggleTodo?(cb.0, cb.1)
                return
            }
            for (i, range) in imageRanges.enumerated() where NSLocationInRange(offset, range) {
                let cb = imageCallbacks[i]
                parent.onImageTap?(cb.0, cb.1)
                return
            }
            parent.onTapText?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
