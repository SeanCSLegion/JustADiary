import SwiftUI
import UIKit

struct DiaryPageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var layout
    var dayKey: String?

    @State private var vm = DiaryViewModel()
    @State private var showPhotoPicker = false

    var body: some View {
        ZStack(alignment: .bottom) {
            BlobBackground(dense: true)
            content
            if !vm.isRead {
                FontToolbar(controller: vm.controller, onTap: {
                    vm.controller.textView?.becomeFirstResponder()
                })
                // 横屏且宽度够时，格式栏是正文右侧的竖排面板（见 mockup
                // docs/design/landscape/screens/write-pad.png）；窄屏仍贴键盘上方。
                .environment(\.fontToolbarVertical, layout.splitsMasterDetail)
                // Above the keyboard when it is up, otherwise just above the home
                // indicator. The bar sits over the content, so the ignored bottom
                // safe area has to be added back here.
                .padding(.bottom, vm.keyboardHeight > 0 ? vm.keyboardHeight + 8 : Screen.safeAreaBottom + 12)
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
        .overlay(alignment: .topLeading) {
            // UI-test-only probe, mirroring `RootView`'s `-ui-test-state`. It
            // exposes the block types (and text) the editor would persist, so a
            // test can assert the load → edit → save round trip without reading
            // the app container's database.
            if ProcessInfo.processInfo.arguments.contains("-ui-test-editor-state") {
                Text(editorProbeText())
                    .diaryFont(1)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("editor.state")
            }
        }
        .appAlert(item: $vm.alertItem)
    }

    /// UI-test-only: `"<block types>|<text>"` for the open editor, or
    /// `"read:<block types>"` for the saved day.
    private func editorProbeText() -> String {
        // Reading the format tick here makes the probe re-evaluate on every
        // edit / cursor move / format toggle, exactly like the format bar.
        _ = vm.controller.formatTick
        if vm.isRead {
            let types = vm.blocks
                .flatMap { ContentFlatten.parseContentCached($0.contentJson) }
                .map(\.style)
            return "read:" + types.joined(separator: ",")
        }
        let parts = vm.controller.currentParts()
        let text = parts.map(ContentFlatten.flattenPart).joined()
        return parts.map(\.style).joined(separator: ",") + "|" + text
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
                    if vm.keyboardHeight > 0 {
                        Color.clear.frame(height: vm.keyboardHeight + 160)
                    } else {
                        TabBarClearance(base: 140)
                    }
                }
                .padding(.top, 10)
                // 限宽只作用于正文列本身；页面内边距加在外面，窄屏才不会被
                // `contentColumn` 和 `adaptivePagePadding` 叠着缩两遍。
                .frame(maxWidth: layout.contentColumn(vm.isRead ? 660 : 620))
                .adaptivePagePadding()
                .frame(maxWidth: .infinity)
                .animation(.diaryStandard, value: vm.blocks.map(\.id))
            }
            // 顶栏是**悬浮**在内容之上的：用 `safeAreaInset` 只给滚动内容留出
            // 起始让位，不占一条实心横带 —— 日记上滑时会从玻璃按钮后面穿过去。
            // 系统在顶边（状态栏那一条）保留默认的 scroll edge effect，避免正文
            // 压到时间/电量；按钮之间透出的仍是正文。
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
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

    private var topBar: some View {
        HStack(spacing: 8) {
            PressableGlassIcon(systemName: "chevron.left",
                               accessibilityLabel: L10n.str("a11y_back")) {
                vm.handleBack()
            }
            Spacer()
            if vm.selectMode {
                GlassPrimaryButton(title: L10n.fmt("editor_delete_count", vm.selectedIds.count),
                                   icon: "trash") {
                    Haptics.tap()
                    vm.confirmDeleteSelected()
                }
            } else if vm.isRead {
                PressableGlassIcon(systemName: "magnifyingglass", active: vm.showSearch,
                                   accessibilityLabel: L10n.str("search_title")) {
                    withAnimation(.diaryQuick) {
                        vm.showSearch.toggle()
                        if !vm.showSearch { vm.searchText = ""; vm.hits = [] }
                    }
                }
                if vm.canEditToday {
                    PressableGlassIcon(systemName: "square.and.pencil",
                                       accessibilityLabel: L10n.str("index_write")) {
                        vm.enterWrite()
                    }
                }
                PressableGlassIcon(systemName: "square.and.arrow.up",
                                   accessibilityLabel: L10n.str("a11y_share")) {
                    vm.shareDiary()
                }
            } else {
                PressableGlassIcon(systemName: "photo",
                                   accessibilityLabel: L10n.str("a11y_insert_image")) {
                    showPhotoPicker = true
                }
                PressableGlassIcon(systemName: "arrow.counterclockwise",
                                   accessibilityLabel: L10n.str("editor_discard")) {
                    vm.confirmDiscardEditing()
                }
                PressableGlassIcon(systemName: "checkmark", active: true,
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
                         trailing: {
            if vm.hits.count > 0 {
                GlassCountBadge(text: "\(min(vm.hitIndex + 1, vm.hits.count))/\(vm.hits.count)")
                searchStepButton("chevron.up", label: L10n.str("read_search_prev")) {
                    vm.stepHit(-1)
                }
                searchStepButton("chevron.down", label: L10n.str("read_search_next")) {
                    vm.stepHit(1)
                }
            }
        })
    }

    /// Stepper for the in-entry search hits.
    ///
    /// Deliberately a plain button: it sits *inside* the search field's glass
    /// capsule, and stacking Liquid Glass on Liquid Glass leaves nothing to
    /// refract — the control would read as a muddy circle. It also carries a
    /// real VoiceOver label, which the previous glass-button version lacked
    /// (it announced the raw symbol name, "chevron.up").
    private func searchStepButton(_ systemName: String, label: String,
                                  action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .diaryFont(TypeSize.meta, weight: .semibold)
                .foregroundStyle(Theme.onSurfaceVariant())
                .frame(minWidth: Spacing.hitTarget, minHeight: Spacing.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Read hero

    private var readHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L10n.formatDayKey(vm.actualDayKey))
                    .diaryFont(TypeSize.cardTitle, weight: .medium)
                    .foregroundStyle(Theme.onSurface())
                if vm.canEditToday {
                    Text(L10n.str("index_card_today"))
                        .diaryFont(TypeSize.caption, weight: .medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(Theme.primary())
                        }
                        .shadow(color: Theme.glowColor(), radius: 6, y: 1)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let first = vm.blocks.first {
                    HStack(spacing: 8) {
                        // `auto_time` 关闭时只隐藏开始时间；`start_time_utc` 仍照常记录
                        // （`day_key` / `created_utc` / 排序依赖它，不能写 0）。
                        if vm.showsTime {
                            Text(L10n.timeOf(first.startTimeUtc))
                                .diaryFont(TypeSize.meta)
                                .foregroundStyle(Theme.onSurfaceVariant())
                        }
                        Text(L10n.fmt("read_hero_segments", vm.blocks.count))
                            .diaryFont(TypeSize.meta)
                            .foregroundStyle(Theme.onSurfaceVariant())
                    }
                    if !first.locText.isEmpty {
                        Label(first.locText, systemImage: "location.fill")
                            .diaryFont(TypeSize.meta)
                            .foregroundStyle(Theme.onSurfaceVariant())
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(L10n.str("read_day_empty"))
                        .diaryFont(TypeSize.meta)
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diaryCard(cornerRadius: Radius.card)
        .padding(.bottom, 2)
    }

    // MARK: - Block card

    private func blockCard(_ block: EditBlock, index: Int) -> some View {
        let parts = ContentFlatten.parseContentCached(block.contentJson)
        let isSelected = vm.selectedIds.contains(block.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if vm.selectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .diaryFont(16)
                        .foregroundStyle(isSelected ? Theme.primary() : Theme.onSurfaceVariant())
                        .padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    // 关闭 `auto_time` 时隐藏块时间；地点 Label 仍独立显示。
                    if vm.showsTime {
                        Text(L10n.timeOf(block.startTimeUtc))
                            .diaryFont(TypeSize.meta, weight: .bold)
                            .foregroundStyle(Theme.primary())
                    }
                    if !block.locText.isEmpty {
                        Label(block.locText, systemImage: "location.fill")
                            .diaryFont(TypeSize.caption)
                            .foregroundStyle(Theme.onSurfaceVariant())
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                if vm.editingIndex == index {
                    GlassCountBadge(text: L10n.str("editor_editing"))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleBlockTap(block, index: index, parts: parts)
            }
            DiaryPartsView(parts: parts,
                           keyword: vm.showSearch ? vm.searchText : "",
                           onToggleTodo: { partIndex, itemIndex in
                vm.toggleTodo(block: block, partIndex: partIndex, itemIndex: itemIndex)
            },
                           onImageTap: { src, ratio in
                vm.previewImage = PreviewItem(src: src, ratio: ratio)
            },
                           onTapText: {
                handleBlockTap(block, index: index, parts: parts)
            })
        }
        .padding(Spacing.card)
        .diaryCard(cornerRadius: Radius.card)
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
        vm.enterEditBlock(index: index)
    }

    // MARK: - Editor

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                // 关闭 `auto_time` 时不显示编辑器时间胶囊；`vm.startUtc` 仍照常保存。
                if vm.showsTime {
                    Text(L10n.timeOf(vm.startUtc))
                        .diaryFont(TypeSize.meta, weight: .bold)
                        .foregroundStyle(Theme.primary())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Theme.primaryContainer())
                        }
                }
                locationRow
            }
            RichTextView(controller: vm.controller,
                         placeholder: L10n.str(vm.editingIndex != nil ? "editor_placeholder_edit" : "editor_placeholder_new"),
                         autoFocus: vm.autoFocusEditor,
                         loadToken: vm.loadToken,
                         loadParts: vm.loadParts)
                // No `minHeight` here: the representable reports its own minimum
                // (160pt scaled by the body style's Dynamic Type factor). A fixed
                // 160pt was mostly placeholder at accessibility sizes.
        }
        .padding(10)
        .diaryCard(cornerRadius: Radius.card, interactive: true)
    }

    /// The entry's location.
    ///
    /// Only a *new* block looks a location up. An existing block keeps whatever
    /// it was written with — editing it can still change the precision, but it
    /// can no longer fetch a place, and a block saved without one stays without
    /// one (`DiaryViewModel.saveEditor` asks before that happens).
    @ViewBuilder
    private var locationRow: some View {
        if vm.isEditingExistingBlock {
            if vm.location != nil {
                locationMenu(text: vm.locationText)
            } else if vm.settings.autoLoc {
                locationChipLabel(L10n.str("search_loc_no_loc"), tint: Theme.onSurfaceVariant())
            }
        } else if vm.settings.autoLoc {
            if vm.location != nil {
                locationMenu(text: vm.locationText)
            } else if vm.locating {
                locationChipLabel(L10n.str("editor_location_fetching"), tint: Theme.primary())
            } else {
                Button {
                    Haptics.tap()
                    vm.beginLocate()
                } label: {
                    locationChipLabel(L10n.str("editor_location_retry_action"), tint: Theme.primary())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Location chip that opens the precision menu (and, for a block that does
    /// not exist yet, "look it up again").
    private func locationMenu(text: String) -> some View {
        Menu {
            ForEach(vm.precisionOptions, id: \.self) { precision in
                Button {
                    Haptics.tap()
                    vm.applyPrecision(precision)
                } label: {
                    if precision == vm.location?.locPrecision {
                        Label(L10n.precisionLabel(precision), systemImage: "checkmark")
                    } else {
                        Text(L10n.precisionLabel(precision))
                    }
                }
            }
            if vm.canRelocate {
                Divider()
                Button {
                    Haptics.tap()
                    vm.refreshLocation()
                } label: {
                    Text(L10n.str("editor_location_retry_action"))
                }
            }
        } label: {
            locationChipLabel(text, tint: Theme.primary())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityLabel(L10n.str("search_loc_title"))
        .accessibilityValue(text)
    }

    private func locationChipLabel(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .diaryFont(TypeSize.caption)
            Text(text)
                .diaryFont(TypeSize.meta)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(Theme.primaryContainer())
        }
    }
}
