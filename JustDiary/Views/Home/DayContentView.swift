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
            GlassPrimaryButton(title: L10n.str("index_write"), compact: true, enabled: !isFuture) {
                if isFuture {
                    showFutureToast()
                } else {
                    openEditor(dayKey)
                }
            }
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
            ReadTextView(parts: ContentFlatten.parseContentCached(block.contentJson),
                         textContainerInset: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
        }
        .padding(.bottom, 2)
    }
}
