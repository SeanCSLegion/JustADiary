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
    /// 滚动内容底部的留白。竖屏要整屏滚动，留 96 让最后一张卡片能滚出浮条；
    /// 横屏分栏里整块只有 ~330pt 高，96 会把内容顶掉一大截，所以调用方传小值。
    var bottomPadding: CGFloat = 96
    /// 是否显示「开始时间」，由调用方从 `AppSettings.autoTime` 透传。
    /// 关闭时只隐藏首页时间行，`block.startTimeUtc` 本身不受影响。
    var showTime: Bool = true
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
                        },
                                       showTime: showTime)
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
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fullScreenCover(item: $previewImage) { item in
            ImagePreviewView(item: item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isFuture ? "moon.stars" : "square.and.pencil")
                .diaryFont(26)
                .foregroundStyle(Theme.onSurfaceVariant().opacity(0.5))
            Text(isFuture ? L10n.str("index_future_empty") : L10n.str("index_day_empty"))
                .diaryFont(TypeSize.rowTitle)
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
    /// 显式传入 `AppSettings.autoTime`：本视图拿不到 settings。
    /// 关闭时只隐藏时间行，`start_time_utc` 仍照常记录（`day_key` 等依赖它）。
    var showTime: Bool = true

    var body: some View {
        let parts = ContentFlatten.parseContentCached(block.contentJson)
        VStack(alignment: .leading, spacing: 10) {
            // 有地点、或（有开始时间且开关打开）时才显示头部信息行。
            if (block.startTimeUtc > 0 && showTime) || !block.locText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if block.startTimeUtc > 0 && showTime {
                        Label(L10n.timeOf(block.startTimeUtc), systemImage: "clock")
                    }
                    if !block.locText.isEmpty {
                        Label(block.locText, systemImage: "location.fill")
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .diaryFont(TypeSize.caption)
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
        .padding(Spacing.card)
        .diaryCard(cornerRadius: Radius.card)
    }
}
