import SwiftUI
import UIKit

// MARK: - Day content (diary of the selected day)

struct DayContentView: View {
    var blocks: [EditBlock]?
    var dayKey: String
    var isFuture: Bool
    var openEditor: (String) -> Void
    var openDiary: (String) -> Void
    var showFutureToast: () -> Void
    @State private var previewImage: PreviewItem?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let blocks, !blocks.isEmpty {
                    ForEach(blocks, id: \.id) { block in
                        DiaryBlockCard(block: block,
                                       onOpenDiary: { openDiary(dayKey) },
                                       onImageTap: { src, ratio in
                            previewImage = PreviewItem(src: src, ratio: ratio)
                        })
                    }
                    if dayKey == DateUtil.dayKeyOf(Date()) {
                        GlassPrimaryButton(title: L10n.str("index_continue_write")) {
                            Haptics.tap()
                            openEditor(dayKey)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fullScreenCover(item: $previewImage) { item in
            ImagePreviewView(item: item)
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
            if !isFuture, dayKey == DateUtil.dayKeyOf(Date()) {
                GlassPrimaryButton(title: L10n.str("index_write")) {
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
    var onOpenDiary: () -> Void
    var onImageTap: (String, CGFloat) -> Void

    var body: some View {
        let parts = ContentFlatten.parseContentCached(block.contentJson)
        VStack(alignment: .leading, spacing: 10) {
            if block.startTimeUtc > 0 || !block.locText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if block.startTimeUtc > 0 {
                        Label(L10n.timeOf(block.startTimeUtc), systemImage: "clock")
                    }
                    if !block.locText.isEmpty {
                        Label(block.locText, systemImage: "location.fill")
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.onSurfaceVariant())
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    onOpenDiary()
                }
            }
            DiaryPartsView(parts: parts,
                           onImageTap: onImageTap,
                           onTapText: {
                Haptics.tap()
                onOpenDiary()
            })
        }
        .padding(12)
        .diaryGlassCard(cornerRadius: 18)
    }
}
