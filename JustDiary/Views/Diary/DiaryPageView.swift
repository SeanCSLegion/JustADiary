import SwiftUI
import UIKit
import PhotosUI

struct DiaryPageView: View {
    @Environment(\.dismiss) private var dismiss
    var dayKey: String?

    @State private var actualDayKey = ""
    @State private var blocks: [EditBlock] = []
    @State private var isRead = true
    @State private var editingIndex: Int? = nil
    @State private var selectMode = false
    @State private var selectedIds: Set<Int64> = []
    @State private var controller = RichEditorController()
    @State private var showPhotoPicker = false
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var hits: [SearchHit] = []
    @State private var hitIndex = 0
    @State private var previewImage: PreviewItem?
    @State private var location: LocationSnapshot?
    @State private var locating = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showPrecisionMenu = false
    @State private var alertItem: AlertItem?
    @State private var scrollTarget: String?
    @State private var loaded = false
    @State private var startUtc: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    @State private var loadToken = 0
    @State private var loadParts: [ContentPart] = []
    @State private var autoFocusEditor = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var settings = SettingsStore.load()

    var body: some View {
        ZStack(alignment: .bottom) {
            BlobBackgroundDense()
            content
            if !isRead {
                FontToolbar(controller: controller, onTap: {
                    controller.textView?.becomeFirstResponder()
                })
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 8 : 84)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let screenHeight = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height
                    ?? 852
                keyboardHeight = frame.origin.y < screenHeight ? frame.height : 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            settings = SettingsStore.load()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { image in
                insertImage(image)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(L10n.formatDayKey(actualDayKey), image: Image(uiImage: image)))
                    .buttonStyle(.glassProminent)
                    .padding(24)
                    .presentationDetents([.height(170)])
            }
        }
        .fullScreenCover(item: $previewImage) { item in
            ImagePreviewView(item: item)
        }
        .alert(item: $alertItem) { item in
            if let secondary = item.secondaryLabel {
                return Alert(title: Text(item.title), message: Text(item.message),
                             primaryButton: .default(Text(secondary)) {
                    item.primaryAction?()
                },
                             secondaryButton: .cancel(Text(item.cancelLabel)))
            }
            return Alert(title: Text(item.title), message: Text(item.message),
                         dismissButton: .default(Text(item.cancelLabel)) {
                item.primaryAction?()
            })
        }
    }

    struct AlertItem: Identifiable {
        let id = UUID()
        var title: String
        var message: String
        var cancelLabel: String = L10n.str("cancel")
        var secondaryLabel: String?
        var primaryAction: (() -> Void)?

        static func confirm(title: String, message: String, confirmLabel: String,
                            action: (() -> Void)? = nil) -> AlertItem {
            AlertItem(title: title, message: message, secondaryLabel: confirmLabel, primaryAction: action)
        }

        static func info(title: String, message: String, action: (() -> Void)? = nil) -> AlertItem {
            AlertItem(title: title, message: message, primaryAction: action)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 4)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if isRead {
                            if showSearch {
                                readSearchBar
                            }
                            readHero
                            ForEach(blocks.indices, id: \.self) { i in
                                blockCard(blocks[i], index: i)
                                    .id("block-\(blocks[i].id)")
                            }
                        } else {
                            editorCard
                                .id("editor-card")
                        }
                        Color.clear.frame(height: keyboardHeight > 0 ? keyboardHeight + 160 : 140)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    self.scrollTarget = nil
                }
                .onChange(of: isRead) { _, read in
                    if !read {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("editor-card", anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: keyboardHeight) { _, height in
                    if !isRead, height > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("editor-card", anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            PressableGlassIcon(systemName: "chevron.left", size: 40) {
                handleBack()
            }
            Spacer()
            if selectMode {
                Text(L10n.fmt("editor_delete_count", selectedIds.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(Theme.primaryContainer())
                            .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                            .shadow(color: Theme.glowColor(), radius: 10, y: 2)
                    }
                    .onTapGesture {
                        confirmDeleteSelected()
                    }
            } else if isRead {
                PressableGlassIcon(systemName: "magnifyingglass", size: 40, active: showSearch) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showSearch.toggle()
                        if !showSearch { searchText = ""; hits = [] }
                    }
                }
                if canEditToday || settings.allowHistoryEdit {
                    PressableGlassIcon(systemName: "square.and.pencil", size: 40) {
                        enterWrite()
                    }
                }
                PressableGlassIcon(systemName: "square.and.arrow.up", size: 40) {
                    shareDiary()
                }
            } else {
                PressableGlassIcon(systemName: "photo", size: 40) {
                    showPhotoPicker = true
                }
                PressableGlassIcon(systemName: "arrow.uturn.backward", size: 40) {
                    loadParts = editingOriginalParts
                    loadToken += 1
                    controller.refreshTypingAttributes()
                }
                PressableGlassIcon(systemName: "checkmark", size: 40, active: true) {
                    saveEditor()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @State private var editingOriginalParts: [ContentPart] = []

    private var canEditToday: Bool {
        actualDayKey == DateUtil.dayKeyOf(Date())
    }

    // MARK: - In-page search

    private var readSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.onSurfaceVariant())
            TextField(L10n.str("read_search_placeholder"), text: $searchText)
                .font(.system(size: 14))
                .tint(Theme.primary())
                .onChange(of: searchText) { _, _ in
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        await MainActor.run { computeHits() }
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    hits = []
                    hitIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                .buttonStyle(.plain)
            }
            if hits.count > 0 {
                Text("\(min(hitIndex + 1, hits.count))/\(hits.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primary())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Theme.primaryContainer())
                            .glassEffect(.regular.tint(Theme.primary()), in: Capsule())
                    }
                Button {
                    stepHit(-1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onSurface())
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Button {
                    stepHit(1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onSurface())
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .diaryGlassCard(cornerRadius: 18, interactive: true)
    }

    private func computeHits() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            hits = []
            hitIndex = 0
            return
        }
        var found: [SearchHit] = []
        for block in blocks {
            let parts = ContentFlatten.parseContent(block.contentJson)
            for (pi, part) in parts.enumerated() {
                let text = ContentFlatten.flattenPart(part)
                let lower = text.lowercased()
                var searchRange = lower.startIndex..<lower.endIndex
                while let range = lower.range(of: keyword.lowercased(), range: searchRange) {
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

    private func stepHit(_ delta: Int) {
        guard !hits.isEmpty else { return }
        hitIndex = (hitIndex + delta + hits.count) % hits.count
        let hit = hits[hitIndex]
        scrollTarget = "block-\(hit.blockId)"
    }

    // MARK: - Read hero

    private var readHero: some View {
        ZStack(alignment: .topLeading) {
            FlowLightOverlay()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n.formatDayKey(actualDayKey))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.onSurface())
                    if canEditToday {
                        Text(L10n.str("index_card_today"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(Theme.primary())
                                    .glassEffect(.regular.tint(Theme.primary()), in: Capsule())
                            }
                            .shadow(color: Theme.glowColor(), radius: 6, y: 1)
                    }
                }
                HStack(spacing: 8) {
                    if let first = blocks.first {
                        Text(L10n.startLine(first.startTimeUtc, locText: first.locText))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.onSurfaceVariant())
                        Text(L10n.fmt("read_hero_segments", blocks.count))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.onSurfaceVariant())
                    } else {
                        Text(L10n.str("read_day_empty"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.onSurfaceVariant())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .diaryGlassCard(cornerRadius: 18)
        .padding(.bottom, 2)
    }

    // MARK: - Block card

    private func blockCard(_ block: EditBlock, index: Int) -> some View {
        let parts = ContentFlatten.parseContent(block.contentJson)
        let isSelected = selectedIds.contains(block.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if selectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? Theme.primary() : Theme.onSurfaceVariant())
                }
                Text(L10n.timeOf(block.startTimeUtc))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.primary())
                if !block.locText.isEmpty {
                    Text(block.locText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .lineLimit(1)
                }
                Spacer()
                if editingIndex == index {
                    Text(L10n.str("editor_editing"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(Theme.primary())
                                .glassEffect(.regular.tint(Theme.primary()), in: Capsule())
                        }
                }
            }
            ReadTextView(parts: parts,
                         keyword: showSearch ? searchText : "",
                         onToggleTodo: { partIndex, itemIndex in
                toggleTodo(block: block, partIndex: partIndex, itemIndex: itemIndex)
            },
                         onImageTap: { src, ratio in
                previewImage = PreviewItem(src: src, ratio: ratio)
            })
        }
        .padding(12)
        .diaryGlassCard(cornerRadius: 18)
        .scaleEffect(pressedIndex == index ? 0.98 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            handleBlockTap(block, index: index, parts: parts)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            enterSelect(block.id)
        }
    }

    @State private var pressedIndex: Int?

    private func handleBlockTap(_ block: EditBlock, index: Int, parts: [ContentPart]) {
        if selectMode {
            if selectedIds.contains(block.id) {
                selectedIds.remove(block.id)
            } else {
                selectedIds.insert(block.id)
            }
            return
        }
        guard !isRead else { return }
        enterEditBlock(index: index)
    }

    // MARK: - Editor

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L10n.timeOf(startUtc))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.primary())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(Theme.primaryContainer())
                    }
                if settings.autoLoc {
                    Button {
                        Haptics.tap()
                        if location == nil {
                            beginLocate()
                        } else {
                            showPrecisionMenu = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            Text(locationLabel)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.primary())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Theme.primaryContainer())
                        }
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(L10n.str("search_loc_title"), isPresented: $showPrecisionMenu) {
                        ForEach(LocationResolver.availablePrecisions(), id: \.self) { precision in
                            Button(L10n.precisionLabel(precision)) {
                                applyPrecision(precision)
                            }
                        }
                    }
                }
                Spacer()
            }
            RichTextView(controller: controller,
                         placeholder: L10n.str(editingIndex != nil ? "editor_placeholder_edit" : "editor_placeholder_new"),
                         autoFocus: autoFocusEditor,
                         loadToken: loadToken,
                         loadParts: loadParts)
                .frame(minHeight: 160)
        }
        .padding(10)
        .diaryGlassCard(cornerRadius: 20, interactive: true)
    }

    private var locationLabel: String {
        if locating { return L10n.str("editor_location_fetching") }
        return location?.locText.isEmpty == false ? location!.locText : L10n.str("editor_location_retry")
    }

    // MARK: - Data loading

    private func load() async {
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
        loaded = true
    }

    private func beginLocateIfNeeded() {
        guard settings.autoLoc, location == nil else { return }
        beginLocate()
    }

    private func beginLocate() {
        guard LocStatus.isAuthorized else {
            LocationService.shared.requestPermission()
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await beginLocateAfterPermission()
            }
            return
        }
        locating = true
        Task {
            guard let loc = await LocationService.shared.currentLocation() else {
                locating = false
                return
            }
            let snapshot = await LocationResolver.resolve(location: loc)
            await MainActor.run {
                location = snapshot
                locating = false
            }
        }
    }

    private func beginLocateAfterPermission() async {
        guard LocStatus.isAuthorized else {
            await MainActor.run { locating = false }
            return
        }
        await MainActor.run { locating = true }
        guard let loc = await LocationService.shared.currentLocation() else {
            await MainActor.run { locating = false }
            return
        }
        let snapshot = await LocationResolver.resolve(location: loc)
        await MainActor.run {
            location = snapshot
            locating = false
        }
    }

    private func applyPrecision(_ precision: String) {
        guard var snapshot = location else { return }
        snapshot.locPrecision = precision
        snapshot.locText = LocationResolver.text(for: snapshot.placemark, precision: precision)
        location = snapshot
    }

    // MARK: - Mode transitions

    private func enterWrite() {
        if actualDayKey != DateUtil.dayKeyOf(Date()), !settings.allowHistoryEdit {
            alertItem = .info(title: L10n.str("editor_history_no_add_title"),
                               message: L10n.str("editor_history_no_add_msg"))
            return
        }
        if !blocks.isEmpty {
            alertItem = .confirm(title: L10n.str("editor_edit_target_title"),
                                  message: L10n.str("editor_edit_target_msg"),
                                  confirmLabel: L10n.str("continue")) {
                loadParts = []
                loadToken += 1
                withAnimation(.easeOut(duration: 0.36)) {
                    isRead = false
                    editingIndex = nil
                }
                beginLocateIfNeeded()
            }
            return
        }
        loadParts = []
        loadToken += 1
        autoFocusEditor = true
        withAnimation(.easeOut(duration: 0.36)) {
            isRead = false
            editingIndex = nil
        }
        beginLocateIfNeeded()
    }

    private func enterEditBlock(index: Int) {
        guard index < blocks.count else { return }
        let block = blocks[index]
        if actualDayKey != DateUtil.dayKeyOf(Date()), !settings.allowHistoryEdit {
            alertItem = .info(title: L10n.str("editor_readonly_title"),
                               message: L10n.str("editor_readonly_msg"))
            return
        }
        let parts = ContentFlatten.parseContent(block.contentJson)
        editingOriginalParts = parts
        editingIndex = index
        loadParts = parts
        loadToken += 1
        autoFocusEditor = true
        startUtc = block.startTimeUtc
        withAnimation(.easeOut(duration: 0.36)) {
            isRead = false
        }
    }

    private func enterSelect(_ id: Int64) {
        withAnimation(.easeOut(duration: 0.28)) {
            selectMode = true
            selectedIds.insert(id)
        }
    }

    private func handleBack() {
        if selectMode {
            withAnimation(.easeOut(duration: 0.28)) {
                selectMode = false
                selectedIds = []
            }
            return
        }
        if !isRead, !controller.isEmpty() {
            alertItem = .confirm(title: L10n.str("editor_exit_title"),
                                  message: L10n.str("editor_exit_content_msg"),
                                  confirmLabel: L10n.str("discard")) {
                    dismiss()
                }
            return
        }
        dismiss()
    }

    // MARK: - Save

    private func saveEditor() {
        let parts = controller.currentParts()
        guard !parts.isEmpty else {
            if editingIndex == nil && blocks.isEmpty {
                dismiss()
            } else {
                withAnimation(.easeOut(duration: 0.36)) {
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
                saveByDayKey(blockDayKey, contentJson: contentJson)
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
                                                                   dayStartHour: self.settings.dayStartHour)
                }
                actualDayKey = dayKey
                DiaryRepository.shared.bumpDiaryVersion()
                await ReminderService.markTodayWritten()
                await reloadAndShowRead()
            } catch {
                showSaveFailed()
            }
        }
    }

    private func showSaveFailed() {
        alertItem = .info(title: L10n.str("editor_save_failed_title"),
                           message: L10n.str("editor_save_failed_msg"))
    }

    private func reloadAndShowRead() async {
        if let diary = await DiaryRepository.shared.getDiaryByDay(actualDayKey) {
            blocks = await DiaryRepository.shared.getBlocks(diaryId: diary.id)
        } else {
            blocks = []
        }
        autoFocusEditor = false
        withAnimation(.easeOut(duration: 0.36)) {
            isRead = true
            editingIndex = nil
            selectMode = false
            selectedIds = []
        }
    }

    // MARK: - Delete

    private func confirmDeleteSelected() {
        let count = selectedIds.count
        alertItem = .confirm(title: L10n.str("editor_delete_title"),
                              message: L10n.fmt("editor_delete_msg", count),
                              confirmLabel: L10n.str("delete")) {
            Task {
                do {
                    try await DiaryRepository.shared.deleteBlocks(Array(selectedIds))
                    DiaryRepository.shared.bumpDiaryVersion()
                    await reloadAndShowRead()
                } catch {}
            }
        }
    }

    // MARK: - Todo toggle

    private func toggleTodo(block: EditBlock, partIndex: Int, itemIndex: Int) {
        var parts = ContentFlatten.parseContent(block.contentJson)
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
                } catch {}
            }
        }
    }

    // MARK: - Image insert

    private func insertImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData() else { return }
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        let fileName = "img_\(stamp).jpg"
        let target = DiaryRepository.imagesDir().appendingPathComponent(fileName)
        try? FileManager.default.createDirectory(at: DiaryRepository.imagesDir(), withIntermediateDirectories: true)
        do {
            try data.write(to: target)
            controller.insertImage(image, src: "images/\(fileName)")
        } catch {
            alertItem = .info(title: L10n.str("editor_image_failed_title"),
                               message: L10n.str("editor_image_failed_msg"))
        }
    }

    // MARK: - Share

    private func shareDiary() {
        let shareBlocks = blocks.map { block in
            ShareBlock(time: block.startTimeUtc, loc: block.locText,
                       parts: ContentFlatten.parseContent(block.contentJson))
        }
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        guard let image = ShareRenderer.render(dayKey: actualDayKey, blocks: shareBlocks, isDark: isDark) else {
            alertItem = .info(title: L10n.str("read_share_failed_title"),
                               message: L10n.str("read_share_failed_msg"))
            return
        }
        shareImage = image
        showShareSheet = true
    }
}

struct PreviewItem: Identifiable {
    let id = UUID()
    var src: String
    var ratio: CGFloat
}

struct SearchHit {
    var blockId: Int64
    var partIndex: Int
    var start: Int
    var len: Int
}

final class FittedTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 320
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

struct ReadTextView: UIViewRepresentable {
    var parts: [ContentPart]
    var keyword: String
    var onToggleTodo: (Int, Int) -> Void
    var onImageTap: (String, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FittedTextView {
        let tv = FittedTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
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
        context.coordinator.rebuild()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ReadTextView
        weak var textView: FittedTextView?
        var todoRanges: [NSRange] = []
        var todoCallbacks: [(Int, Int)] = []
        var imageRanges: [NSRange] = []
        var imageCallbacks: [(String, CGFloat)] = []

        init(_ parent: ReadTextView) {
            self.parent = parent
        }

        func rebuild() {
            guard let tv = textView else { return }
            let attributed = NSMutableAttributedString()
            todoRanges = []
            todoCallbacks = []
            imageRanges = []
            imageCallbacks = []
            for (pi, part) in parent.parts.enumerated() {
                switch part.type {
                case ContentPartType.h1:
                    appendRuns(part, to: attributed, size: 22)
                case ContentPartType.h2:
                    appendRuns(part, to: attributed, size: 18)
                case ContentPartType.quote:
                    appendRuns(part, to: attributed, size: 13, background: Theme.quoteBgUIColor())
                case ContentPartType.list:
                    for item in part.items ?? [] {
                        appendMarkerLine("bullet", done: false, text: item, to: attributed,
                                         strike: false, alpha: 1)
                    }
                case ContentPartType.todo:
                    let items = part.items ?? []
                    let done = part.done ?? Array(repeating: false, count: items.count)
                    for (ii, item) in items.enumerated() {
                        let isDone = done.indices.contains(ii) && done[ii]
                        let start = attributed.length
                        appendMarkerLine("todo", done: isDone, text: item, to: attributed,
                                         strike: isDone, alpha: isDone ? 0.45 : 1)
                        todoRanges.append(NSRange(location: start, length: 1 + (item as NSString).length))
                        todoCallbacks.append((pi, ii))
                    }
                case ContentPartType.image:
                    if let src = part.src, let image = UIImage(contentsOfFile: ImagePathUtil.resolveImagePath(src)) {
                        let attachment = NSTextAttachment()
                        attachment.image = image
                        let w = CGFloat(part.w ?? 300)
                        let h = CGFloat(part.h ?? 200)
                        attachment.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                        let att = NSMutableAttributedString(attachment: attachment)
                        let start = attributed.length
                        attributed.append(att)
                        attributed.append(NSAttributedString(string: "\n"))
                        imageRanges.append(NSRange(location: start, length: 1))
                        imageCallbacks.append((src, h / max(1, w)))
                    }
                default:
                    appendRuns(part, to: attributed, size: 15)
                }
            }
            let highlighted = NSMutableAttributedString(attributedString: attributed)
            if !parent.keyword.isEmpty {
                applyHighlight(highlighted)
            }
            if !highlighted.isEqual(to: tv.attributedText) {
                tv.attributedText = highlighted
            }
        }

        private func appendPlain(_ text: String, to target: NSMutableAttributedString, size: CGFloat,
                                 strike: Bool = false, alpha: CGFloat = 1) {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size),
                .foregroundColor: Theme.onSurfaceUIColor().withAlphaComponent(alpha)
            ]
            if strike { attrs[.strikethroughStyle] = 1 }
            target.append(NSAttributedString(string: text, attributes: attrs))
        }

        private func appendMarkerLine(_ kind: String, done: Bool, text: String,
                                      to target: NSMutableAttributedString,
                                      strike: Bool, alpha: CGFloat) {
            let symbol = kind == "todo" ? (done ? "checkmark.square.fill" : "square") : "circle.fill"
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let tint = kind == "todo" && done ? Theme.primaryUIColor() : Theme.onSurfaceVariantUIColor()
            let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(tint, renderingMode: .alwaysTemplate)
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -2, width: 15, height: 15)
            let marker = NSMutableAttributedString(attachment: attachment)
            marker.addAttribute(.attachment,
                                value: AttachmentPayload(kind: kind, done: done),
                                range: NSRange(location: 0, length: 1))
            target.append(marker)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: Theme.onSurfaceUIColor().withAlphaComponent(alpha)
            ]
            if strike { attrs[.strikethroughStyle] = 1 }
            target.append(NSAttributedString(string: text, attributes: attrs))
            target.append(NSAttributedString(string: "\n"))
        }

        private func appendRuns(_ part: ContentPart, to target: NSMutableAttributedString, size: CGFloat,
                                background: UIColor? = nil) {
            let runs = part.runs ?? []
            if runs.isEmpty, let text = part.text {
                appendRun(TextRun(text: text), to: target, size: size, background: background, center: part.align == "center")
            } else {
                for run in runs {
                    appendRun(run, to: target, size: size, background: background, center: part.align == "center")
                }
            }
            target.append(NSAttributedString(string: "\n"))
        }

        private func appendRun(_ run: TextRun, to target: NSMutableAttributedString, size: CGFloat,
                               background: UIColor?, center: Bool) {
            let bold = run.bold == true
            var font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: Theme.onSurfaceUIColor()
            ]
            if run.italic == true, let desc = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                font = UIFont(descriptor: desc, size: size)
                attrs[.font] = font
            }
            if run.strike == true { attrs[.strikethroughStyle] = 1 }
            if run.underline == true { attrs[.underlineStyle] = 1 }
            if let runSize = run.size, runSize > 0, runSize != size {
                attrs[.font] = UIFont.systemFont(ofSize: runSize, weight: bold ? .bold : .regular)
            }
            if let bg = background { attrs[.backgroundColor] = bg }
            let style = NSMutableParagraphStyle()
            style.alignment = center ? .center : .left
            style.lineSpacing = size == 13 ? 7 : 2
            attrs[.paragraphStyle] = style
            target.append(NSAttributedString(string: run.text, attributes: attrs))
        }

        private func applyHighlight(_ attributed: NSMutableAttributedString) {
            let segments = SearchUtil.highlightSegments(attributed.string, keyword: parent.keyword)
            let ns = attributed.string as NSString
            var cursor = 0
            for seg in segments {
                let len = (seg.text as NSString).length
                let range = NSRange(location: cursor, length: len)
                if seg.hit {
                    attributed.addAttribute(.backgroundColor, value: Theme.primaryContainerUIColor(), range: range)
                    attributed.addAttribute(.foregroundColor, value: Theme.primaryUIColor(), range: range)
                    attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: 15, weight: .medium), range: range)
                }
                cursor += len
            }
            _ = ns
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
                parent.onToggleTodo(cb.0, cb.1)
                return
            }
            for (i, range) in imageRanges.enumerated() where NSLocationInRange(offset, range) {
                let cb = imageCallbacks[i]
                parent.onImageTap(cb.0, cb.1)
                return
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.parent.onPicked(image)
                    }
                }
            }
        }
    }
}

struct ImagePreviewView: View {
    let item: PreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(max(0, 1 - abs(dragOffset.height) / 600))
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            if let image = UIImage(contentsOfFile: ImagePathUtil.resolveImagePath(item.src)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(max(0.6, 1 - abs(dragOffset.height) / 800))
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let velocity = value.predictedEndTranslation.height
                                if abs(value.translation.height) > 140 || abs(velocity) > 900 {
                                    dismiss()
                                } else {
                                    withAnimation(.easeOut(duration: 0.22)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )
            }
        }
    }
}
