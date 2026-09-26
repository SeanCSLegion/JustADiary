import Foundation
import Observation
import SwiftUI
import UIKit
import os

@Observable
final class DiaryViewModel {
    var dayKey: String?
    var actualDayKey = ""
    var blocks: [EditBlock] = []
    var isRead = true
    var editingIndex: Int?
    var selectMode = false
    var selectedIds: Set<Int64> = []
    var showSearch = false
    var searchText = ""
    var hits: [SearchHit] = []
    var hitIndex = 0
    var previewImage: PreviewItem?
    var location: LocationSnapshot?
    var locating = false
    var keyboardHeight: CGFloat = 0
    var alertItem: AppAlertItem?
    var scrollTarget: String?
    var startUtc: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var loadToken = 0
    var loadParts: [ContentPart] = []
    var autoFocusEditor = false
    var shareImage: UIImage?
    /// 分享给系统的文件（`Documents/…` 之外，写进临时目录）。
    ///
    /// 给系统一个**文件 URL** 而不是 `UIImage`：分享面板头部会显示文件名
    /// （`2026-09-08.png`）与真实缩略图，而不是「图片」+ 占位图，也多出
    /// 「存储到“文件”」这类只接受文件 URL 的动作。渲染失败时退回 `UIImage`。
    var shareFileURL: URL?
    var showShareSheet = false
    var settings = SettingsStore.load()
    var editingOriginalParts: [ContentPart] = []
    var onDismiss: (() -> Void)?

    let controller = RichEditorController()

    private var searchGen = 0

    /// 是否显示「开始时间」。
    /// `auto_time` 关闭时只影响**显示**：`start_time_utc` 仍必须记录，
    /// 因为 `day_key` / `created_utc` / 排序都依赖它（跨端契约，不能写 0）。
    var showsTime: Bool { settings.autoTime }

    var canEditToday: Bool {
        actualDayKey == DateUtil.dayKeyOf(Date())
    }

    // MARK: - Loading

    func load() async {
        let key = dayKey ?? DateUtil.dayKeyOf(Date())
        actualDayKey = key
        hits = []
        hitIndex = 0
        startUtc = Int64(Date().timeIntervalSince1970 * 1000)
        if let diary = await DiaryRepository.shared.getDiaryByDay(key) {
            blocks = await DiaryRepository.shared.getBlocks(diaryId: diary.id)
        } else {
            blocks = []
        }
        isRead = true
    }

    func refreshSettings() {
        settings = SettingsStore.load()
    }

    // MARK: - In-page search

    func onSearchTextChanged() {
        let gen = searchGen + 1
        searchGen = gen
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard searchGen == gen else { return }
            computeHits()
        }
    }

    func computeHits() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            hits = []
            hitIndex = 0
            return
        }
        var found: [SearchHit] = []
        let lowerKeyword = keyword.lowercased()
        for block in blocks {
            let parts = ContentFlatten.parseContentCached(block.contentJson)
            for (pi, part) in parts.enumerated() {
                let lower = ContentFlatten.flattenPart(part).lowercased()
                var searchRange = lower.startIndex..<lower.endIndex
                while let range = lower.range(of: lowerKeyword, range: searchRange) {
                    let start = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    found.append(SearchHit(blockId: block.id, partIndex: pi, start: start, len: keyword.count))
                    searchRange = range.upperBound..<lower.endIndex
                    if searchRange.isEmpty { break }
                }
            }
        }
        hits = found
        hitIndex = 0
    }

    func stepHit(_ delta: Int) {
        guard !hits.isEmpty else { return }
        hitIndex = (hitIndex + delta + hits.count) % hits.count
        scrollTarget = "block-\(hits[hitIndex].blockId)"
    }

    // MARK: - Mode transitions

    func enterWrite() {
        if actualDayKey != DateUtil.dayKeyOf(Date()) {
            alertItem = .info(title: L10n.str("editor_history_no_add_title"),
                              message: L10n.str("editor_history_no_add_msg"))
            return
        }
        loadParts = []
        // A brand-new entry has nothing to fall back to: without this a
        // "discard changes" in a new entry restored the block edited earlier in
        // the session, because `editingOriginalParts` outlived `enterEditBlock`.
        editingOriginalParts = []
        // Likewise the location: it belongs to the block being written, and
        // leaving the previous block's address here would save it onto this one.
        location = nil
        locating = false
        loadToken += 1
        autoFocusEditor = autoFocusAllowed
        withAnimation(.diaryStandard) {
            isRead = false
            editingIndex = nil
        }
        beginLocateIfNeeded()
    }

    func enterEditBlock(index: Int) {
        guard index < blocks.count else { return }
        let block = blocks[index]
        if actualDayKey != DateUtil.dayKeyOf(Date()), !settings.allowHistoryEdit {
            alertItem = .info(title: L10n.str("editor_readonly_title"),
                              message: L10n.str("editor_readonly_msg"))
            return
        }
        let parts = ContentFlatten.parseContentCached(block.contentJson)
        editingOriginalParts = parts
        editingIndex = index
        loadParts = parts
        loadToken += 1
        autoFocusEditor = autoFocusAllowed
        startUtc = block.startTimeUtc
        // Show the location this block was written with. It is not looked up
        // again — only its precision can still be changed.
        location = Self.locationSnapshot(from: block)
        locating = false
        withAnimation(.diaryStandard) {
            isRead = false
        }
    }

    func enterSelect(_ id: Int64) {
        if actualDayKey != DateUtil.dayKeyOf(Date()), !settings.allowHistoryEdit {
            alertItem = .info(title: L10n.str("editor_readonly_title"),
                              message: L10n.str("editor_readonly_msg"))
            return
        }
        withAnimation(.diaryQuick) {
            selectMode = true
            selectedIds.insert(id)
        }
    }

    /// 收起键盘。
    ///
    /// 编辑页的键盘只能靠「点空白」或下拉内容收起来 —— 之前两条路都没有：顶栏的
    /// `图片 / 放弃修改 / 保存` 一直被触控键盘压在下面，用户也没法先把键盘收起来
    /// 再选文字。统一走「让当前 first responder 辞职」，编辑器的 `UITextView` 与
    /// 阅读态页内搜索的 `TextField` 都适用。
    /// 进入编辑时是否自动弹出键盘。
    ///
    /// UI 测试可以带 `-ui-test-no-autofocus` 关掉它，好复现「键盘弹起前先点正文」这条
    /// 用户路径（否则键盘一进编辑就弹出来，没机会先把光标点到正文靠下的位置）。
    private var autoFocusAllowed: Bool {
        !ProcessInfo.processInfo.arguments.contains("-ui-test-no-autofocus")
    }

    func dismissKeyboard() {
        // `autoFocusEditor` 是「进入编辑时自动弹键盘」的开关：视图重建时
        // `RichTextView.makeUIView` 会据此再喊一次 `becomeFirstResponder`，用户
        // 刚收起的键盘会被它 0.25s 后又叫回来（表现就是「键盘收不掉」）。
        autoFocusEditor = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    func handleBack() {
        if selectMode {
            withAnimation(.diaryQuick) {
                selectMode = false
                selectedIds = []
            }
            return
        }
        // In the editor, back leaves the *edit*, not the page: the day's reading
        // view is what sits behind it. It used to dismiss the whole cover, so
        // cancelling an edit dropped the user straight back onto the home
        // calendar instead of the entry they were reading.
        if !isRead {
            if controller.isEmpty() {
                showRead()
            } else {
                alertItem = .confirm(title: L10n.str("editor_exit_title"),
                                     message: L10n.str("editor_exit_content_msg"),
                                     confirmLabel: L10n.str("discard")) {
                    self.discardEditing()
                    self.showRead()
                }
            }
            return
        }
        onDismiss?()
    }

    /// Leaves the editor for the day's reading view. The stored blocks are
    /// untouched — the editor never wrote them — so nothing has to be reloaded.
    private func showRead() {
        autoFocusEditor = false
        withAnimation(.diaryStandard) {
            isRead = true
            editingIndex = nil
        }
    }

    // MARK: - Discard

    /// "Discard changes" in the editor's top bar.
    ///
    /// It throws away every edit made since the editor was opened and there is
    /// no undo stack to get them back, so it asks first — the button used to be
    /// labelled "Redo" with an undo arrow and silently discarded the whole entry
    /// on a single tap.
    func confirmDiscardEditing() {
        guard !controller.isEmpty() else { return }
        alertItem = .confirm(title: L10n.str("editor_discard_title"),
                             message: L10n.str("editor_discard_msg"),
                             confirmLabel: L10n.str("discard")) {
            self.discardEditing()
        }
    }

    private func discardEditing() {
        loadParts = editingOriginalParts
        loadToken += 1
        controller.refreshTypingAttributes()
    }

    // MARK: - Save

    func saveEditor() {
        let parts = controller.currentParts()
        guard !parts.isEmpty else {
            if editingIndex == nil && blocks.isEmpty {
                onDismiss?()
            } else {
                withAnimation(.diaryStandard) {
                    isRead = true
                    editingIndex = nil
                }
            }
            return
        }
        let contentJson = ContentFlatten.serializeContent(parts)
        if let editingIndex {
            let block = blocks[editingIndex]
            // Editing never changes where a block is: the coordinates and the
            // address belong to the moment it was written. The precision (and
            // the address text derived from it) can still be adjusted.
            let locText = location?.locText ?? block.locText
            let locPrecision = location?.locPrecision ?? block.locPrecision
            Task {
                do {
                    try await DiaryRepository.shared.updateBlockContent(blockId: block.id,
                                                                       contentJson: contentJson,
                                                                       locText: locText,
                                                                       locPrecision: locPrecision)
                    DiaryRepository.shared.bumpDiaryVersion()
                    await reloadAndShowRead()
                } catch {
                    Log.editor.error("save block failed: \(String(describing: error), privacy: .public)")
                    showSaveFailed()
                }
            }
            return
        }

        let blockDayKey = DateUtil.dayKeyForUtc(startUtc, dayStartHour: settings.dayStartHour)
        if settings.autoLoc, location == nil {
            // Saving now means this entry will never have a location, because
            // only a new block looks one up.
            alertItem = .confirm(title: L10n.str("editor_location_retry"),
                                 message: L10n.str("editor_location_missing_msg"),
                                 confirmLabel: L10n.str("editor_save_anyway")) {
                // Another alert (the cross-day one) may follow, so let this one
                // finish dismissing first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.finishNewBlockSave(dayKey: blockDayKey, contentJson: contentJson)
                }
            }
            return
        }
        finishNewBlockSave(dayKey: blockDayKey, contentJson: contentJson)
    }

    /// Everything that happens after a new block's location question has been
    /// answered: the cross-day check, then the insert.
    private func finishNewBlockSave(dayKey: String, contentJson: String) {
        if dayKey != DateUtil.dayKeyOf(Date()) {
            let displayDay = L10n.formatDayKey(dayKey)
            alertItem = .confirm(title: L10n.str("editor_cross_day_title"),
                                 message: L10n.fmt("editor_cross_day_msg", displayDay),
                                 confirmLabel: L10n.str("editor_save_exit")) {
                self.saveByDayKey(dayKey, contentJson: contentJson)
            }
            return
        }
        saveByDayKey(dayKey, contentJson: contentJson)
    }

    private func saveByDayKey(_ dayKey: String, contentJson: String) {
        let region = location?.region ?? LocRegion(country: "", countryCode: "", region1: "",
                                                   region2: "", region3: "", locQuality: LocQuality.none)
        Task {
            do {
                if let diary = await DiaryRepository.shared.getDiaryByDay(dayKey) {
                    _ = try await DiaryRepository.shared.addBlockToDiary(diaryId: diary.id,
                                                                         startTimeUtc: startUtc,
                                                                         locText: location?.locText ?? "",
                                                                         latitude: location?.latitude ?? 0,
                                                                         longitude: location?.longitude ?? 0,
                                                                         locPrecision: location?.locPrecision ?? LocPrecision.none,
                                                                         region: region,
                                                                         contentJson: contentJson)
                } else {
                    _ = try await DiaryRepository.shared.addBlock(startTimeUtc: startUtc,
                                                                  locText: location?.locText ?? "",
                                                                  latitude: location?.latitude ?? 0,
                                                                  longitude: location?.longitude ?? 0,
                                                                  locPrecision: location?.locPrecision ?? LocPrecision.none,
                                                                  region: region,
                                                                  contentJson: contentJson,
                                                                  dayStartHour: settings.dayStartHour)
                }
                actualDayKey = dayKey
                DiaryRepository.shared.bumpDiaryVersion()
                await ReminderService.markTodayWritten()
                await reloadAndShowRead()
            } catch {
                Log.editor.error("save failed: \(String(describing: error), privacy: .public)")
                showSaveFailed()
            }
        }
    }

    private func showSaveFailed() {
        alertItem = .info(title: L10n.str("editor_save_failed_title"),
                          message: L10n.str("editor_save_failed_msg"))
    }

    func reloadAndShowRead() async {
        if let diary = await DiaryRepository.shared.getDiaryByDay(actualDayKey) {
            blocks = await DiaryRepository.shared.getBlocks(diaryId: diary.id)
        } else {
            blocks = []
        }
        autoFocusEditor = false
        withAnimation(.diaryStandard) {
            isRead = true
            editingIndex = nil
            selectMode = false
            selectedIds = []
        }
    }

    // MARK: - Delete

    func confirmDeleteSelected() {
        let count = selectedIds.count
        alertItem = .confirm(title: L10n.str("editor_delete_title"),
                             message: L10n.fmt("editor_delete_msg", count),
                             confirmLabel: L10n.str("delete")) {
            Task {
                do {
                    try await DiaryRepository.shared.deleteBlocks(Array(self.selectedIds))
                    DiaryRepository.shared.bumpDiaryVersion()
                    await self.reloadAndShowRead()
                } catch {
                    Log.editor.error("delete failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    // MARK: - Todo toggle

    func toggleTodo(block: EditBlock, partIndex: Int, itemIndex: Int) {
        var parts = ContentFlatten.parseContentCached(block.contentJson)
        guard partIndex < parts.count else { return }
        var part = parts[partIndex]
        var done = part.done ?? Array(repeating: false, count: part.items?.count ?? 0)
        if itemIndex < done.count {
            done[itemIndex].toggle()
            part.done = done
            parts[partIndex] = part
            let json = ContentFlatten.serializeContent(parts)
            Task {
                do {
                    try await DiaryRepository.shared.updateBlockContent(blockId: block.id, contentJson: json)
                    DiaryRepository.shared.bumpDiaryVersion()
                } catch {
                    Log.editor.error("todo toggle failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    // MARK: - Location

    func beginLocateIfNeeded() {
        guard settings.autoLoc, location == nil else { return }
        beginLocate()
    }

    func beginLocate() {
        // Only a block that does not exist yet looks a location up; an existing
        // block keeps the one it was written with.
        guard editingIndex == nil else { return }
        guard LocStatus.isAuthorized else {
            LocationService.shared.requestPermission()
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard LocStatus.isAuthorized else {
                    locating = false
                    return
                }
                locating = true
                await fetchLocation()
            }
            return
        }
        locating = true
        Task { await fetchLocation() }
    }

    func fetchLocation() async {
        guard let loc = await LocationService.shared.currentLocation() else {
            locating = false
            return
        }
        let snapshot = await LocationResolver.resolve(location: loc)
        // Coordinates with no address are not a usable record: treat that as "no
        // location" so the entry is saved without one instead of carrying an
        // empty place that can never be filled in later.
        location = snapshot.locText.isEmpty ? nil : snapshot
        locating = false
    }

    func applyPrecision(_ precision: String) {
        guard var snapshot = location else { return }
        snapshot.locPrecision = precision
        if let recorded = snapshot.recordedPrecision,
           precision == recorded,
           let text = snapshot.recordedText {
            // Back to the level the block was recorded at: keep its text
            // verbatim, since the place name / street it may hold are not stored
            // anywhere else.
            snapshot.locText = text
        } else if let placemark = snapshot.placemark {
            snapshot.locText = LocationResolver.text(for: placemark, precision: precision)
        } else {
            snapshot.locText = LocationResolver.text(for: snapshot.region, precision: precision)
        }
        location = snapshot
    }

    /// Looks the location up again. Only a new block may do this: the address of
    /// an existing block is part of what was recorded.
    func refreshLocation() {
        guard editingIndex == nil else { return }
        location = nil
        beginLocate()
    }

    /// Whether the block being edited was already saved.
    var isEditingExistingBlock: Bool { editingIndex != nil }

    /// A new block may still look its location up; an existing one may not.
    var canRelocate: Bool { editingIndex == nil }

    /// The address currently held by the editor, if any.
    var locationText: String { location?.locText ?? "" }

    /// Precisions the location menu offers for the current block.
    var precisionOptions: [String] {
        guard let location else { return [] }
        if let recorded = location.recordedPrecision {
            return LocationResolver.availablePrecisions(for: location.region, recorded: recorded)
        }
        return LocationResolver.availablePrecisions()
    }

    /// Rebuilds the editor's location state from a stored block.
    ///
    /// The coordinates and the address were fixed when the block was written —
    /// only the precision can still be adjusted — so this reconstructs what that
    /// needs from the block's own columns instead of looking anything up.
    private static func locationSnapshot(from block: EditBlock) -> LocationSnapshot? {
        let precision = block.locPrecision.isEmpty ? LocPrecision.none : block.locPrecision
        guard !block.locText.isEmpty || precision != LocPrecision.none else { return nil }
        let region = LocRegion(country: block.country, countryCode: block.countryCode,
                               region1: block.region1, region2: block.region2, region3: block.region3,
                               locQuality: block.locQuality)
        return LocationSnapshot(latitude: block.latitude,
                                longitude: block.longitude,
                                locText: block.locText,
                                locPrecision: precision,
                                region: region,
                                placemark: nil,
                                recordedPrecision: precision,
                                recordedText: block.locText)
    }

    // MARK: - Image insert

    func insertImage(_ image: UIImage) {
        let processed = DiaryImageStore.downsample(image, maxPixel: 2048) ?? image
        guard let data = processed.jpegData(compressionQuality: 0.85) ?? processed.pngData() else { return }
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        let fileName = "img_\(stamp).jpg"
        do {
            try FileManager.default.createDirectory(at: DiaryRepository.imagesDir(), withIntermediateDirectories: true)
            let target = DiaryRepository.imagesDir().appendingPathComponent(fileName)
            try data.write(to: target)
            controller.insertImage(processed, src: "images/\(fileName)")
        } catch {
            Log.editor.error("image insert failed: \(String(describing: error), privacy: .public)")
            alertItem = .info(title: L10n.str("editor_image_failed_title"),
                              message: L10n.str("editor_image_failed_msg"))
        }
    }

    // MARK: - Share

    func shareDiary() {
        // 面板已经开着时不再重复渲染（否则预览会闪回进度圈）。
        guard !showShareSheet else { return }
        let shareBlocks = blocks.map { block in
            ShareBlock(time: block.startTimeUtc, loc: block.locText,
                       parts: ContentFlatten.parseContentCached(block.contentJson))
        }
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let dayKey = actualDayKey
        // `auto_time` 只是显示开关：`ShareBlock.time` 仍照常带上 `startUtc`，
        // 这里只决定长图是否绘制时间行（数据层与备份格式不受影响）。
        let showTime = showsTime
        // 先把面板拉起来（里面显示「正在生成分享图…」），渲染完再把预览填进去，
        // 这样点按立刻有反馈，而不是等一两秒才「啪」地弹出一个面板。
        let previousFile = shareFileURL
        shareImage = nil
        shareFileURL = nil
        showShareSheet = true
        Task.detached(priority: .userInitiated) {
            // 上一张分享图已经用不上了（面板早已收起），顺手删掉，临时目录不留垃圾。
            if let previousFile { try? FileManager.default.removeItem(at: previousFile) }
            let image = ShareRenderer.render(dayKey: dayKey, blocks: shareBlocks,
                                             isDark: isDark, showTime: showTime)
            let fileURL = image.flatMap { Self.writeShareFile($0, dayKey: dayKey) }
            await MainActor.run {
                if let image, self.showShareSheet {
                    self.shareImage = image
                    self.shareFileURL = fileURL
                } else if image == nil {
                    self.showShareSheet = false
                    self.alertItem = .info(title: L10n.str("read_share_failed_title"),
                                           message: L10n.str("read_share_failed_msg"))
                }
            }
        }
    }

    /// 把分享长图写成临时文件（PNG，文字边缘不会被压糊）。
    ///
    /// 文件名带 `JustDiary-` 前缀再跟 day_key：别的 App 也常按日期建文件，
    /// 不加前缀的话「存储到“文件”」/ AirDrop 之后很容易和别人的 `2026-09-08.png`
    /// 撞名；系统分享面板又直接拿文件名当标题，所以这个名字也会显示给用户。
    /// 同一天重复分享会覆盖同一个文件，不会越攒越多。
    private nonisolated static func writeShareFile(_ image: UIImage, dayKey: String) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustDiary-\(dayKey).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.app.error("share: write temp image failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

struct SearchHit {
    var blockId: Int64
    var partIndex: Int
    var start: Int
    var len: Int
}
