import SwiftUI

struct SearchView: View {
    @Environment(\.adaptiveLayout) private var layout
    var openDiary: (String) -> Void

    @State private var vm = SearchViewModel()
    @State private var hideTopControls = false
    @State private var topControlsHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @FocusState private var locSearchFocused: Bool

    var body: some View {
        content
            .onAppear { vm.openDiary = openDiary }
            .sheet(isPresented: $vm.showTimeSheet) {
                timeSheet
                    .presentationDetents([.medium])
                }
            .sheet(isPresented: $vm.showLocSheet) {
                locSheet
                    .presentationDetents([.large])
                }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .adaptivePagePadding()
            if !hideTopControls {
                VStack(spacing: 0) {
                    searchBar
                        .adaptivePagePadding()
                        .padding(.top, 10)
                    filterPanel
                        .adaptivePagePadding()
                        .padding(.top, 12)
                }
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { topControlsHeight = g.size.height }
                            .onChange(of: g.size.height) { _, h in
                                if h > 20 { topControlsHeight = h }
                            }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            // 当前关键词：单独一行，多关键词时能一眼看清「在搜什么」，每个都能单独点掉。
            // 竖屏与横屏共用同一行（横屏的搜索框更宽，这一行仍然需要）。
            if !vm.keywords.isEmpty {
                keywordChipsRow
                    .adaptivePagePadding()
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if vm.hasAnyCondition {
                filterSummary
                    .adaptivePagePadding()
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            resultsList
        }
        .padding(.top, 12)
        .animation(.diaryStandard, value: hideTopControls)
        .animation(.diaryQuick, value: vm.hasAnyCondition)
        .onChange(of: vm.keyword) { _, _ in
            vm.onKeywordChanged()
        }
        .onChange(of: searchFocused) { _, focused in
            if focused, hideTopControls {
                withAnimation(.diaryStandard) { hideTopControls = false }
            }
        }
    }

    /// 当前生效的关键词。每个胶囊可单独移除，右侧是「清除全部条件」。
    private var keywordChipsRow: some View {
        HStack(spacing: 8) {
            Text(L10n.str("search_filter_keyword"))
                .diaryFont(TypeSize.caption)
                .foregroundStyle(Theme.onSurfaceVariant())
                .lineLimit(1)
                .fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.keywords, id: \.self) { term in
                        Button {
                            Haptics.tap()
                            vm.removeKeyword(term)
                        } label: {
                            HStack(spacing: 4) {
                                Text(term)
                                    .diaryFont(TypeSize.badge, weight: .medium)
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .diaryFont(9, weight: .semibold)
                            }
                            .foregroundStyle(Theme.primary())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                Capsule().fill(Theme.primaryContainer())
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(term)
                        .accessibilityHint(L10n.str("search_clear_all"))
                    }
                }
            }
            Button {
                Haptics.tap()
                searchFocused = false
                vm.clearAll()
            } label: {
                Text(L10n.str("search_clear_all"))
                    .diaryFont(TypeSize.badge, weight: .medium)
                    .foregroundStyle(Theme.primary())
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background {
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .stroke(Theme.outlineVariant().opacity(0.45), lineWidth: 0.5)
                }
        }
    }

    private var filterSummary: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.activeFilterItems) { item in
                        filterCapsule(item)
                    }
                }
            }
            GlassIconButton(systemName: "xmark.circle.fill", size: 28,
                            accessibilityLabel: L10n.str("search_clear_all")) {
                searchFocused = false
                vm.clearAll()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 44)
        .diaryCard(cornerRadius: Radius.card)
    }

    private func filterCapsule(_ item: SearchFilterItem) -> some View {
        Button {
            Haptics.tap()
            if item.kind == .keyword {
                if let term = item.value {
                    vm.removeKeyword(term)
                } else {
                    searchFocused = false
                    vm.clearKeywordInput()
                }
            } else {
                vm.clearFilter(item.kind)
            }
        } label: {
            HStack(spacing: 4) {
                Text(item.label)
                    .diaryFont(TypeSize.badge, weight: .medium)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .diaryFont(9, weight: .semibold)
            }
            .foregroundStyle(Theme.primary())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Theme.primaryContainer())
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityHint(L10n.str("search_clear_all"))
    }

    private var header: some View {
        PageHeader(title: L10n.str("search_title")) {
            if vm.total > 0 {
                GlassCountBadge(text: L10n.fmt("search_result_count", vm.total), icon: "circle.fill")
            }
        }
    }

    private var searchBar: some View {
        GlassSearchField(text: $vm.keyword,
                         placeholder: L10n.str("search_placeholder"),
                         focus: $searchFocused,
                         onSubmit: { vm.commitKeyword() },
                         trailing: {
            if searchFocused {
                Button {
                    searchFocused = false
                } label: {
                    Text(L10n.str("search_cancel"))
                        .diaryFont(TypeSize.chip, weight: .medium)
                        .foregroundStyle(Theme.primary())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        })
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.str("search_filter_time"))
                .diaryFont(TypeSize.caption)
                .foregroundStyle(Theme.onSurfaceVariant())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    timeChip(L10n.str("search_all_time"), kind: .all)
                    timeChip(L10n.str("search_time_week"), kind: .thisWeek)
                    timeChip(L10n.str("search_time_month"), kind: .thisMonth)
                    timeChip(L10n.str("search_time_year"), kind: .thisYear)
                    timeChip(vm.timeRangeLabel, kind: .custom)
                }
            }
            Text(L10n.str("search_filter_loc"))
                .diaryFont(TypeSize.caption)
                .foregroundStyle(Theme.onSurfaceVariant())
                .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    locChip(L10n.str("search_all_loc"),
                            country: "", region1: "", noLoc: false)
                    locChip(vm.locFilterLabel, country: vm.locFilter.country, region1: vm.locFilter.region1,
                            noLoc: vm.locFilter.noLoc, custom: true)
                }
            }
        }
        .padding(10)
        .diaryCard(cornerRadius: Radius.card)
    }

    private func timeChip(_ label: String, kind: TimeRangeKind) -> some View {
        GlassChip(label: label, active: vm.timeKind == kind) {
            if kind == .custom {
                vm.showTimeSheet = true
            } else {
                vm.setTimeKind(kind)
            }
        }
    }

    private func locChip(_ label: String, country: String, region1: String, noLoc: Bool,
                         custom: Bool = false) -> some View {
        let active = custom ? (country != "" || noLoc)
            : (vm.locFilter.country == country && vm.locFilter.region1 == region1 && vm.locFilter.noLoc == noLoc)
        return GlassChip(label: label, active: active) {
            if active {
                vm.resetLocFilter()
            } else if custom && country.isEmpty && !noLoc {
                vm.showLocSheet = true
            } else {
                vm.selectLocRow(country: country, region1: region1, noLoc: noLoc)
            }
        }
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(vm.results, id: \.id) { item in
                    resultItem(item)
                        .onTapGesture {
                            Haptics.tap()
                            vm.openDiary?(item.dayKey)
                        }
                }
                if vm.hasMore {
                    GlassPrimaryButton(title: L10n.str("search_load_more"), compact: true) {
                        vm.loadMore()
                    }
                    .padding(.vertical, 8)
                }
                if vm.results.isEmpty, !vm.searching {
                    emptyState
                        .padding(.top, 60)
                }
                TabBarClearance()
            }
            .adaptivePagePadding()
            .padding(.top, 10)
        }
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geo in
            updateTopControls(geo)
        }
    }

    private func updateTopControls(_ geo: ScrollGeometry) {
        let y = geo.contentOffset.y
        let hide: Bool
        if hideTopControls {
            hide = y > 8
        } else {
            let extra = topControlsHeight > 20 ? topControlsHeight : 170
            hide = y > 24 && geo.contentSize.height > geo.containerSize.height + extra + 24
        }
        guard hide != hideTopControls else { return }
        withAnimation(.diaryStandard) { hideTopControls = hide }
    }

    @ViewBuilder
    private var emptyState: some View {
        if vm.indexing || vm.searching {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.primary())
                Text(vm.searching ? L10n.str("search_loading") : L10n.str("search_preparing"))
                    .diaryFont(TypeSize.rowTitle, weight: .medium)
                    .foregroundStyle(Theme.onSurface())
            }
            .padding(.top, 60)
        } else if vm.hasAnyCondition {
            VStack(spacing: 16) {
                ContentUnavailableView.search(text: vm.combinedKeyword)
                GlassPrimaryButton(title: L10n.str("search_clear_all"), compact: true) {
                    searchFocused = false
                    vm.clearAll()
                }
            }
            .padding(.top, 60)
        } else {
            ContentUnavailableView {
                Label(L10n.str("search_start_title"), systemImage: "magnifyingglass")
            } description: {
                Text(L10n.str("search_empty"))
            }
            .padding(.top, 60)
        }
    }

    private func resultItem(_ item: SearchResultItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .diaryFont(11)
                    Text(L10n.formatDayKey(item.dayKey))
                        .diaryFont(TypeSize.badge, weight: .medium)
                }
                .foregroundStyle(Theme.primary())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(Theme.primaryContainer())
                }
                HighlightedText(snippet: item.snippet, summary: item.summary, keyword: vm.combinedKeyword)
                    .diaryFont(TypeSize.meta)
                    .foregroundStyle(Theme.onSurface())
                    .lineLimit(2)
            }
            Spacer()
            Text(L10n.timeOf(item.updatedUtc))
                .diaryFont(TypeSize.caption)
                .foregroundStyle(Theme.onSurfaceVariant())
            Image(systemName: "chevron.right")
                .diaryFont(12)
                .foregroundStyle(Theme.onSurfaceVariant())
        }
        .padding(14)
        .diaryCard(cornerRadius: Radius.card)
    }

    // MARK: - Sheets

    private var timeSheet: some View {
        VStack(spacing: 16) {
            GlassSheetHeader(title: L10n.str("search_time_title")) {
                vm.showTimeSheet = false
            }
            HStack(spacing: 8) {
                quickRangeChip(L10n.str("search_time_week"), kind: .thisWeek)
                quickRangeChip(L10n.str("search_time_month"), kind: .thisMonth)
                quickRangeChip(L10n.str("search_time_year"), kind: .thisYear)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.str("search_time_start"))
                    .diaryFont(TypeSize.caption)
                    .foregroundStyle(Theme.onSurfaceVariant())
                DatePicker("", selection: Binding(
                    get: { vm.customFrom ?? DateUtil.monthFirst(Date()) },
                    set: { vm.customFrom = DateUtil.startOfDay($0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.primary())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.str("search_time_end"))
                    .diaryFont(TypeSize.caption)
                    .foregroundStyle(Theme.onSurfaceVariant())
                DatePicker("", selection: Binding(
                    get: { vm.customTo ?? Date() },
                    set: { vm.customTo = DateUtil.startOfDay($0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.primary())
            }
            HStack(spacing: 12) {
                GlassSecondaryButton(title: L10n.str("search_time_clear"), fullWidth: true) {
                    vm.clearTimeFilter()
                }
                GlassPrimaryButton(title: L10n.str("search_time_apply"), fullWidth: true) {
                    vm.applyCustomTime()
                }
            }
            .padding(.top, 12)
        }
        .padding(20)
        .padding(.bottom, 8)
    }

    private func quickRangeChip(_ label: String, kind: TimeRangeKind) -> some View {
        GlassChip(label: label, active: vm.timeKind == kind) {
            vm.applyQuickRange(kind)
        }
    }

    private var locSheet: some View {
        VStack(spacing: 10) {
            GlassSheetHeader(title: L10n.str("search_loc_title")) {
                vm.showLocSheet = false
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .diaryFont(14)
                    .foregroundStyle(Theme.onSurfaceVariant())
                TextField(L10n.str("search_loc_search"), text: $vm.locSearch)
                    .diaryFont(TypeSize.rowTitle)
                    .tint(Theme.primary())
                    .focused($locSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        locSearchFocused = false
                    }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .diaryCard(cornerRadius: Radius.field, interactive: true)
            Text(L10n.str("search_loc_sort_hint"))
                .diaryFont(TypeSize.caption)
                .foregroundStyle(Theme.onSurfaceVariant())
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    locRow(label: L10n.str("search_all_loc"), country: "", region1: "", noLoc: false, count: nil)
                    if vm.noLocCount > 0 {
                        locRow(label: "\(L10n.str("search_loc_no_loc")) (\(vm.noLocCount))", country: "", region1: "", noLoc: true, count: nil)
                    }
                    ForEach(vm.filteredOptions, id: \.self) { option in
                        locRow(label: "\(option.country)\(option.region1.isEmpty ? "" : " · \(option.region1)")",
                               country: option.country, region1: option.region1, noLoc: false, count: option.count)
                    }
                    if vm.filteredOptions.isEmpty && !vm.locLoading {
                        Text(L10n.str("search_loc_empty"))
                            .diaryFont(TypeSize.meta)
                            .foregroundStyle(Theme.onSurfaceVariant())
                            .padding(.top, 40)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(20)
        .padding(.bottom, 8)
        .onAppear {
            vm.loadLocationOptions()
        }
    }

    private func locRow(label: String, country: String, region1: String, noLoc: Bool, count: Int?) -> some View {
        let active = vm.locFilter.country == country && vm.locFilter.region1 == region1 && vm.locFilter.noLoc == noLoc
        return Button {
            vm.selectLocRow(country: country, region1: region1, noLoc: noLoc)
        } label: {
            HStack {
                Text(label)
                    .diaryFont(TypeSize.rowTitle)
                    .foregroundStyle(active ? Theme.primary() : Theme.onSurface())
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .diaryFont(TypeSize.badge)
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                if active {
                    Image(systemName: "checkmark")
                        .diaryFont(13, weight: .semibold)
                        .foregroundStyle(Theme.primary())
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background {
                RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                    .fill(active ? Theme.glowColor() : .clear)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HighlightedText: View {
    var snippet: String
    var summary: String
    var keyword: String

    @Environment(\.diaryDynamicTypeSize) private var typeSize

    var body: some View {
        let segments: [SearchUtil.Seg]
        if snippet.contains("<hl>") {
            segments = SearchUtil.highlightSnippet(snippet)
        } else if !keyword.isEmpty {
            segments = SearchUtil.highlightSegments(summary, keyword: keyword)
        } else {
            segments = [SearchUtil.Seg(text: summary, hit: false)]
        }
        var attributed = AttributedString()
        for seg in segments {
            var s = AttributedString(seg.text)
            if seg.hit {
                s.foregroundColor = Theme.primary()
                s.backgroundColor = Theme.primaryContainer()
                // A literal 13pt ignored the text-size setting, so a
                // highlighted word stayed small while the rest of the snippet
                // grew around it.
                s.font = .system(size: DynamicTypeMetrics.scaled(TypeSize.meta, for: typeSize),
                                 weight: .medium)
            }
            attributed += s
        }
        return Text(attributed)
    }
}
