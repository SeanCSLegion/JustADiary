import SwiftUI
import UIKit

// MARK: - Day content (diary of the selected day)

struct DayContentView: View {
    var blocks: [EditBlock]?
    var dayKey: String
    var isFuture: Bool
    var openEditor: (String) -> Void
    var showFutureToast: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let blocks, !blocks.isEmpty {
                    ForEach(blocks, id: \.id) { block in
                        DiaryBlockCard(block: block)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isFuture ? "moon.stars" : "square.and.pencil")
                .font(.system(size: 26))
                .foregroundStyle(Theme.onSurfaceVariant().opacity(0.5))
            Text(isFuture ? L10n.str("index_future_empty") : L10n.str("index_day_empty"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.onSurfaceVariant())
            Button {
                Haptics.tap()
                if isFuture {
                    showFutureToast()
                } else {
                    openEditor(dayKey)
                }
            } label: {
                Text(L10n.str("index_write"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.primary()))
                    .shadow(color: Theme.glowColor(), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .opacity(isFuture ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }
}

struct DiaryBlockCard: View {
    var block: EditBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if block.startTimeUtc > 0 || !block.locText.isEmpty {
                HStack(spacing: 10) {
                    if block.startTimeUtc > 0 {
                        Label(L10n.timeOf(block.startTimeUtc), systemImage: "clock")
                    }
                    if !block.locText.isEmpty {
                        Label(block.locText, systemImage: "location.fill")
                    }
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.onSurfaceVariant())
            }
            ReadOnlyRichText(parts: ContentFlatten.parseContent(block.contentJson))
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Read-only rich text

struct ReadOnlyRichText: UIViewRepresentable {
    var parts: [ContentPart]

    func makeUIView(context: Context) -> ReadOnlyTextView {
        let tv = ReadOnlyTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        return tv
    }

    func updateUIView(_ uiView: ReadOnlyTextView, context: Context) {
        uiView.attributedText = PartsCodec.attributedString(from: parts)
    }
}

final class ReadOnlyTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 340
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(20, size.height))
    }
}
