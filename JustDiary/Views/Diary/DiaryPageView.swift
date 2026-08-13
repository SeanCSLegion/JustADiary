import SwiftUI
import UIKit

struct DiaryPageView: View {
    @Environment(\.dismiss) private var dismiss
    var dayKey: String?

    @State private var vm = DiaryViewModel()
    @State private var showPhotoPicker = false
    @State private var showPrecisionMenu = false

    var body: some View {
        ZStack(alignment: .bottom) {
            BlobBackground(dense: true)
            content
            if !vm.isRead {
                FontToolbar(controller: vm.controller, onTap: {
                    vm.controller.textView?.becomeFirstResponder()
                })
                .padding(.bottom, vm.keyboardHeight > 0 ? vm.keyboardHeight + 8 : 84)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            vm.dayKey = dayKey
            vm.onDismiss = { dismiss() }
            await vm.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            handleKeyboard(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .diaryVersionChanged)) { _ in
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTickChanged)) { _ in
            vm.refreshSettings()
        }
        .onChange(of: vm.searchText) { _, _ in
            vm.onSearchTextChanged()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { image in
                vm.insertImage(image)
            }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let image = vm.shareImage {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(L10n.formatDayKey(vm.actualDayKey), image: Image(uiImage: image)))
                    .buttonStyle(.glassProminent)
                    .padding(24)
                    .presentationDetents([.height(170)])
            }
        }
        .fullScreenCover(item: $vm.previewImage) { item in
            ImagePreviewView(item: item)
        }
        .appAlert(item: $vm.alertItem)
    }

    // MARK: - Keyboard

    private func handleKeyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let height = frame.origin.y < Screen.height ? frame.height : 0
        guard height != vm.keyboardHeight else { return }
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveValue = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 0
        let animation: Animation
        switch curveValue {
        case 1: animation = .easeIn(duration: duration)
        case 2: animation = .easeOut(duration: duration)
        case 3: animation = .linear(duration: duration)
        default: animation = .easeInOut(duration: duration)
        }
        withAnimation(animation) {
            vm.keyboardHeight = height
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
                        if vm.isRead {
                            if vm.showSearch {
                                readSearchBar
                            }
                            readHero
                            ForEach(vm.blocks.indices, id: \.self) { i in
                                blockCard(vm.blocks[i], index: i)
                                    .id("block-\(vm.blocks[i].id)")
                            }
                        } else {
                            editorCard
                                .id("editor-card")
                        }
                        Color.clear.frame(height: vm.keyboardHeight > 0 ? vm.keyboardHeight + 160 : 140)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .animation(.diaryStandard, value: vm.blocks.map(\.id))
                }
                .onChange(of: vm.scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.diaryStandard) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    vm.scrollTarget = nil
                }
                .onChange(of: vm.isRead) { _, read in
                    if !read {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.diaryStandard) {
                                proxy.scrollTo("editor-card", anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: vm.keyboardHeight) { _, height in
                    if !vm.isRead, height > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.diaryStandard) {
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
            PressableGlassIcon(systemName: "chevron.left", size: 40,
                               accessibilityLabel: L10n.str("a11y_back")) {
                vm.handleBack()
            }
            Spacer()
            if vm.selectMode {
                GlassCountBadge(text: L10n.fmt("editor_delete_count", vm.selectedIds.count))
                    .onTapGesture {
                        Haptics.tap()
                        vm.confirmDeleteSelected()
                    }
                    .accessibilityAddTraits(.isButton)
            } else if vm.isRead {
                PressableGlassIcon(systemName: "magnifyingglass", size: 40, active: vm.showSearch,
                                   accessibilityLabel: L10n.str("search_title")) {
                    withAnimation(.diaryQuick) {
                        vm.showSearch.toggle()
                        if !vm.showSearch { vm.searchText = ""; vm.hits = [] }
                    }
                }
                if vm.canEditToday || vm.settings.allowHistoryEdit {
                    PressableGlassIcon(systemName: "square.and.pencil", size: 40,
                                       accessibilityLabel: L10n.str("index_write")) {
                        vm.enterWrite()
                    }
                }
                PressableGlassIcon(systemName: "square.and.arrow.up", size: 40,
                                   accessibilityLabel: L10n.str("a11y_share")) {
                    vm.shareDiary()
                }
            } else {
                PressableGlassIcon(systemName: "photo", size: 40,
                                   accessibilityLabel: L10n.str("a11y_insert_image")) {
                    showPhotoPicker = true
                }
                PressableGlassIcon(systemName: "arrow.uturn.backward", size: 40,
                                   accessibilityLabel: L10n.str("editor_redo")) {
                    vm.loadParts = vm.editingOriginalParts
                    vm.loadToken += 1
                    vm.controller.refreshTypingAttributes()
                }
                PressableGlassIcon(systemName: "checkmark", size: 40, active: true,
                                   accessibilityLabel: L10n.str("save")) {
                    vm.saveEditor()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - In-page search

    private var readSearchBar: some View {
        GlassSearchField(text: $vm.searchText,
                         placeholder: L10n.str("read_search_placeholder"),
                         cornerRadius: 18,
                         trailing: {
            if vm.hits.count > 0 {
                GlassCountBadge(text: "\(min(vm.hitIndex + 1, vm.hits.count))/\(vm.hits.count)")
                GlassIconButton(systemName: "chevron.up", size: 26) {
                    vm.stepHit(-1)
                }
                GlassIconButton(systemName: "chevron.down", size: 26) {
                    vm.stepHit(1)
                }
            }
        })
    }

    // MARK: - Read hero

    private var readHero: some View {
        ZStack(alignment: .topLeading) {
            FlowLightOverlay()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n.formatDayKey(vm.actualDayKey))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.onSurface())
                    if vm.canEditToday {
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
                    if let first = vm.blocks.first {
                        Text(L10n.startLine(first.startTimeUtc, locText: first.locText))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.onSurfaceVariant())
                        Text(L10n.fmt("read_hero_segments", vm.blocks.count))
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
        let parts = ContentFlatten.parseContentCached(block.contentJson)
        let isSelected = vm.selectedIds.contains(block.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if vm.selectMode {
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
                if vm.editingIndex == index {
                    GlassCountBadge(text: L10n.str("editor_editing"))
                }
            }
            ReadTextView(parts: parts,
                         keyword: vm.showSearch ? vm.searchText : "",
                         onToggleTodo: { partIndex, itemIndex in
                vm.toggleTodo(block: block, partIndex: partIndex, itemIndex: itemIndex)
            },
                         onImageTap: { src, ratio in
                vm.previewImage = PreviewItem(src: src, ratio: ratio)
            })
        }
        .padding(12)
        .diaryGlassCard(cornerRadius: 18)
        .contentShape(Rectangle())
        .onTapGesture {
            handleBlockTap(block, index: index, parts: parts)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            vm.enterSelect(block.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func handleBlockTap(_ block: EditBlock, index: Int, parts: [ContentPart]) {
        if vm.selectMode {
            Haptics.tap()
            if vm.selectedIds.contains(block.id) {
                vm.selectedIds.remove(block.id)
            } else {
                vm.selectedIds.insert(block.id)
            }
            return
        }
        guard !vm.isRead else { return }
        vm.enterEditBlock(index: index)
    }

    // MARK: - Editor

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L10n.timeOf(vm.startUtc))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.primary())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(Theme.primaryContainer())
                            .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                    }
                if vm.settings.autoLoc {
                    Button {
                        Haptics.tap()
                        if vm.location == nil {
                            vm.beginLocate()
                        } else {
                            showPrecisionMenu = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            Text(vm.locationLabel)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.primary())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Theme.primaryContainer())
                                .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(L10n.str("search_loc_title"), isPresented: $showPrecisionMenu) {
                        ForEach(LocationResolver.availablePrecisions(), id: \.self) { precision in
                            Button(L10n.precisionLabel(precision)) {
                                vm.applyPrecision(precision)
                            }
                        }
                    }
                }
                Spacer()
            }
            RichTextView(controller: vm.controller,
                         placeholder: L10n.str(vm.editingIndex != nil ? "editor_placeholder_edit" : "editor_placeholder_new"),
                         autoFocus: vm.autoFocusEditor,
                         loadToken: vm.loadToken,
                         loadParts: vm.loadParts)
                .frame(minHeight: 160)
        }
        .padding(10)
        .diaryGlassCard(cornerRadius: 20, interactive: true)
    }
}
