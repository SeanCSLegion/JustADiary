import SwiftUI

struct SearchView: View {
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
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $vm.showLocSheet) {
                locSheet
                    .presentationDetents([.large])
                    .presentationBackground(.ultraThinMaterial)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
            if !hideTopControls {
                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    filterPanel
                        .padding(.horizontal, 16)
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
            if vm.hasAnyCondition {
                filterSummary
                    .padding(.horizontal, 16)
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
        .frame(height: 44)
        .diaryGlassCard(cornerRadius: 18)
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
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.primary())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Theme.primaryContainer())
                    .glassEffect(.regular.tint(Theme.primary()), in: Capsule())
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
                        .font(.system(size: 14, weight: .medium))
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
                .font(.system(size: 11))
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
                .font(.system(size: 11))
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
        .diaryGlassCard(cornerRadius: 22)
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
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 16)
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
                    .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 11))
                    Text(L10n.formatDayKey(item.dayKey))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.primary())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(Theme.primaryContainer())
                        .glassEffect(.regular.tint(Theme.primary()), in: Capsule())
                }
                HighlightedText(snippet: item.snippet, summary: item.summary, keyword: vm.combinedKeyword)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.onSurface())
                    .lineLimit(2)
            }
            Spacer()
            Text(L10n.timeOf(item.updatedUtc))
                .font(.system(size: 11))
                .foregroundStyle(Theme.onSurfaceVariant())
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.onSurfaceVariant())
        }
        .padding(14)
        .diaryGlassCard(cornerRadius: 20)
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
                    .font(.system(size: 12))
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
                    .font(.system(size: 12))
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
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onSurfaceVariant())
                TextField(L10n.str("search_loc_search"), text: $vm.locSearch)
                    .font(.system(size: 14))
                    .tint(Theme.primary())
                    .focused($locSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        locSearchFocused = false
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .diaryGlassCard(cornerRadius: 18, interactive: true)
            Text(L10n.str("search_loc_sort_hint"))
                .font(.system(size: 11))
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
                            .font(.system(size: 13))
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
                    .font(.system(size: 14))
                    .foregroundStyle(active ? Theme.primary() : Theme.onSurface())
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primary())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                s.font = .systemFont(ofSize: 13, weight: .medium)
            }
            attributed += s
        }
        return Text(attributed)
    }
}
