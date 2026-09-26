import SwiftUI
import UIKit

struct DiaryPageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var layout
    var dayKey: String?

    @State private var vm = DiaryViewModel()
    @State private var showPhotoPicker = false
    /// 顶栏实测高度：顶栏不再挂在滚动视图上，改成按这个高度给内容让位。
    @State private var topBarHeight: CGFloat = 0
    /// 格式栏上沿（屏幕坐标）：它浮在键盘上方，光标要连它一起让开。
    ///
    /// 用「上沿」而不是「栏高」：栏高只在它出现时量一次（键盘弹起只改它的**位置**），
    /// 而位置是随时可读的，且无论键盘在不在，光标都该待在栏的上方。
    @State private var formatBarTop: CGFloat = .greatestFiniteMagnitude
    /// 滚动位置交给 SwiftUI 管：直接改底下那个 `UIScrollView` 的 `contentOffset` 会被
    /// 下一次布局覆盖回去（实测滚动没有任何效果），所以用 `ScrollPosition` 驱动。
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollOffsetY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            BlobBackground(dense: true)
            content
            // 顶栏钉在页面顶部，**不放进滚动视图**：它原本是 ScrollView 的
            // `safeAreaInset`，而键盘弹起时页面会 `scrollTo` 把编辑卡片带进视野，
            // 横屏（可用高度只有 402pt）连这条 inset 一起被滚出屏幕 —— 实测返回
            // 按钮跑到 y = −51，用户看到的就是「顶栏没有按钮」。
            topBarOverlay
            if !vm.isRead {
                FontToolbar(controller: vm.controller, onTap: {
                    vm.controller.textView?.becomeFirstResponder()
                })
                // 格式栏横竖屏都在键盘上方（与备忘录一致，见 `FontToolbar`）：
                // 横屏曾经竖排贴右，但竖排比横屏可用高度还高，会被屏幕裁掉。
                // Above the keyboard when it is up, otherwise just above the home
                // indicator. The bar sits over the content, so the ignored bottom
                // safe area has to be added back here.
                // 量的是格式栏自己的上沿：必须在底下那层
                // `padding(.bottom, keyboardHeight + 8)` **之前**，否则量到被垫高的位置。
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    formatBarTop = frame.minY
                    revealCaret(animated: false)
                }
                .padding(.bottom, vm.keyboardHeight > 0 ? vm.keyboardHeight + 8 : Screen.safeAreaBottom + 12)
                .transition(.opacity)
            }
        }
        // 底部安全区由页面自己让位（格式栏用 `keyboardHeight` 抬到键盘上方、内容
        // 末尾补一块等高占位），所以不要再让系统避让一次：两套叠加会多出一份键盘
        // 高度的空白。顶栏不在这一层 —— 它由 `topBarOverlay` 钉在页面顶部。
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        // 打字与移动光标都会 bump formatTick：随时把光标保持在可见区里（不带动画，
        // 以免每次按键都重启一次滚动动画）。
        .onChange(of: vm.controller.formatTick) { _, _ in
            revealCaret(animated: false)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { image in
                vm.insertImage(image)
            }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            ShareSheetView(image: vm.shareImage, fileURL: vm.shareFileURL) {
                vm.showShareSheet = false
            }
            // 预览 + 系统动作需要整屏高度；与「照片」App 的分享面板一致。
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $vm.previewImage) { item in
            ImagePreviewView(item: item)
        }
        .overlay(alignment: .topLeading) {
            // UI-test-only probe, mirroring `RootView`'s `-ui-test-state`. It
            // exposes the block types (and text) the editor would persist, so a
            // test can assert the load → edit → save round trip without reading
            // the app container's database.
            if ProcessInfo.processInfo.arguments.contains("-ui-test-editor-caret") {
                // 光标在窗口坐标里的位置，给「键盘有没有挡住光标」那条用例断言。
                Text(caretProbeText())
                    .diaryFont(1)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("editor.caret")
            }
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

    /// UI-test-only: 光标在窗口坐标里的 `"minY,maxY"`，没有光标时是 `"none"`。
    private func caretProbeText() -> String {
        _ = vm.controller.formatTick
        guard let caret = vm.controller.caretRectInWindow() else { return "none" }
        return "\(Int(caret.minY)),\(Int(caret.maxY))"
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

    /// 让光标停在可见区里：底部让开格式栏（键盘在它下面，所以让开栏就够了），
    /// 顶部让开悬浮顶栏。
    ///
    /// 键盘弹起时布局要分几帧才稳定（内容末尾那块「键盘高度 + 160」的占位、格式栏的
    /// 位置都是随后才落定的），一次滚动往往不够 —— 所以这里按几个时间点各试一次，
    /// 已经可见的那几次会在 `revealCaret` 里直接返回，代价可以忽略。
    private func revealCaret(animated: Bool, retries: [Double] = []) {
        guard !vm.isRead else { return }
        applyCaretReveal(animated: animated)
        for delay in retries {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !vm.isRead else { return }
                self.applyCaretReveal(animated: false)
            }
        }
    }

    private func applyCaretReveal(animated: Bool) {
        // 键盘在格式栏下面，所以「让开栏的上沿」就同时让开了键盘。
        guard formatBarTop < .greatestFiniteMagnitude,
              let caret = vm.controller.caretRectInWindow() else { return }
        let bottomLimit = formatBarTop - 8
        let topLimit = topBarHeight + 8
        var delta: CGFloat = 0
        if caret.maxY > bottomLimit {
            delta = caret.maxY - bottomLimit
        } else if caret.minY < topLimit {
            delta = caret.minY - topLimit
        }
        guard abs(delta) > 1 else { return }
        let target = max(0, scrollOffsetY + delta)
        if animated {
            withAnimation(.diaryQuick) { scrollPosition.scrollTo(y: target) }
        } else {
            scrollPosition.scrollTo(y: target)
        }
    }

    private func handleKeyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        // 不能拿 `frame.height` 直接当键盘高度：横屏时它可能是竖屏坐标系的（见
        // `Screen.keyboardObscuredHeight`）。
        let height = Screen.keyboardObscuredHeight(screenFrame: frame)
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
                    // 两块占位都不参与命中：否则「点正文下方空白收键盘」会点在
                    // 这两块透明视图上，手势落不到外层的 contentShape。
                    if vm.keyboardHeight > 0 {
                        Color.clear.frame(height: vm.keyboardHeight + 160)
                            .allowsHitTesting(false)
                            // 这块占位的高度就是「让开键盘」的量：它一变（键盘弹起 /
                            // 布局落定）就重新确认一次光标可见 —— 比按固定延时重试可靠，
                            // 因为 SwiftUI 可能在这个阶段把滚动位置重置回顶部。
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                                revealCaret(animated: false)
                            }
                    } else {
                        TabBarClearance(base: 140)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, topBarHeight + 10)
                // 限宽只作用于正文列本身；页面内边距加在外面，窄屏才不会被
                // `contentColumn` 和 `adaptivePagePadding` 叠着缩两遍。
                // 阅读态与编辑态**同宽**（原来编辑态小 40pt，横屏进出编辑时整张卡片
                // 会跳一下）。数值取阅读列的 660：它是正文的阅读宽度，编辑同一篇
                // 日记没有理由更窄。
                .frame(maxWidth: layout.contentColumn(660))
                .adaptivePagePadding()
                .frame(maxWidth: .infinity)
                // 点内容里的空白（卡片之间、正文下方）收起键盘：卡片 / 按钮自己的
                // 手势优先，落不到别处的手势才会走到这里。
                .contentShape(Rectangle())
                .onTapGesture { vm.dismissKeyboard() }
                .animation(.diaryStandard, value: vm.blocks.map(\.id))
            }
            // 下拉内容也可以把键盘带走（系统标准的交互式收起）。
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                scrollOffsetY = y
            }
            // 顶栏是悬浮在内容之上的，这里不再用 `safeAreaInset` 给它让位：键盘弹起
            // 时那条 inset 会把滚动视图撑高（实测 457pt 高的滚动视图被挤到 y = −55），
            // 让位改用内容自己的顶部 padding（见上面的 `topBarHeight`）。
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
            // 键盘弹起：把**光标**滚到键盘（与浮在它上面的格式栏）之上。
            // 原来是把整张卡片 `scrollTo(anchor: .center)` 到视口中心，而那个视口是
            // 整屏 —— 横屏下卡片下半张连光标一起被键盘盖住（SE 横屏可用高度只有
            // 198pt），用户得先上滑才看得到自己正在输入的位置。
            .onChange(of: vm.keyboardHeight) { _, height in
                guard !vm.isRead, height > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 键盘与「内容末尾那块等高占位」要分几帧才稳定：多试几次，已经
                    // 可见的那几次在 `revealCaret` 里直接返回，代价可以忽略。
                    revealCaret(animated: true,
                                retries: [0.15, 0.3, 0.5, 0.75, 1.0, 1.4])
                }
            }
        }
    }

    /// 顶栏本体：钉在 ZStack 顶部，并把自己的高度报给内容当让位高度。
    private var topBarOverlay: some View {
        topBar
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 10, abs(height - topBarHeight) > 0.5 { topBarHeight = height }
            }
            // 顶栏中间的空白也是一处「点空白收键盘」：按钮自己的手势优先，落不到
            // 按钮上的点才走到这里。
            .contentShape(Rectangle())
            .onTapGesture { vm.dismissKeyboard() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diary.blockCard")
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
        // 与阅读卡片同内边距（`Spacing.card`）：这样两个模式的**输入区**一样宽，
        // 进出编辑时正文的左右边界不会跳。
        .padding(Spacing.card)
        .diaryCard(cornerRadius: Radius.card, interactive: true)
        // 供 UI 测试比较「阅读卡片 / 编辑卡片」的宽度。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diary.editorCard")
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
