import Foundation
import Observation
import SwiftUI
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
    var showShareSheet = false
    var settings = SettingsStore.load()
    var editingOriginalParts: [ContentPart] = []
    var onDismiss: (() -> Void)?

    let controller = RichEditorController()

    private var searchGen = 0

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
        loadToken += 1
        autoFocusEditor = true
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
        autoFocusEditor = true
        startUtc = block.startTimeUtc
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

    func handleBack() {
        if selectMode {
            withAnimation(.diaryQuick) {
                selectMode = false
                selectedIds = []
            }
            return
        }
        if !isRead, !controller.isEmpty() {
            alertItem = .confirm(title: L10n.str("editor_exit_title"),
                                 message: L10n.str("editor_exit_content_msg"),
                                 confirmLabel: L10n.str("discard")) {
                    self.onDismiss?()
                }
            return
        }
        onDismiss?()
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
            Task {
                do {
                    try await DiaryRepository.shared.updateBlockContent(blockId: block.id, contentJson: contentJson)
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
        if blockDayKey != DateUtil.dayKeyOf(Date()) {
            let displayDay = L10n.formatDayKey(blockDayKey)
            alertItem = .confirm(title: L10n.str("editor_cross_day_title"),
                                 message: L10n.fmt("editor_cross_day_msg", displayDay),
                                 confirmLabel: L10n.str("editor_save_exit")) {
                self.saveByDayKey(blockDayKey, contentJson: contentJson)
            }
            return
        }
        saveByDayKey(blockDayKey, contentJson: contentJson)
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
        location = snapshot
        locating = false
    }

    func applyPrecision(_ precision: String) {
        guard var snapshot = location else { return }
        snapshot.locPrecision = precision
        snapshot.locText = LocationResolver.text(for: snapshot.placemark, precision: precision)
        location = snapshot
    }

    func refreshLocation() {
        location = nil
        beginLocate()
    }

    var locationLabel: String {
        if locating { return L10n.str("editor_location_fetching") }
        return location?.locText.isEmpty == false ? location!.locText : L10n.str("editor_location_retry")
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
        let shareBlocks = blocks.map { block in
            ShareBlock(time: block.startTimeUtc, loc: block.locText,
                       parts: ContentFlatten.parseContentCached(block.contentJson))
        }
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let dayKey = actualDayKey
        Task.detached(priority: .userInitiated) {
            let image = ShareRenderer.render(dayKey: dayKey, blocks: shareBlocks, isDark: isDark)
            await MainActor.run {
                if let image {
                    self.shareImage = image
                    self.showShareSheet = true
                } else {
                    self.alertItem = .info(title: L10n.str("read_share_failed_title"),
                                           message: L10n.str("read_share_failed_msg"))
                }
            }
        }
    }
}

struct SearchHit {
    var blockId: Int64
    var partIndex: Int
    var start: Int
    var len: Int
}
