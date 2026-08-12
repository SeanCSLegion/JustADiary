import SwiftUI

struct SearchView: View {
    var openDiary: (String) -> Void

    @State private var vm = SearchViewModel()
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
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
            filterPanel
                .padding(.horizontal, 16)
                .padding(.top, 12)
            resultsList
        }
        .padding(.top, 12)
    }

    private var header: some View {
        HStack {
            Text(L10n.str("search_title"))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.onSurface())
            Spacer()
            if vm.total > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Theme.primary()).frame(width: 6, height: 6)
                    Text(L10n.fmt("search_result_count", vm.total))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primary())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(Theme.primaryContainer())
                        .shadow(color: Theme.glowColor(), radius: 6, y: 2)
                }
            }
        }
        .frame(height: 52)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.onSurfaceVariant())
            TextField(L10n.str("search_placeholder"), text: $vm.keyword)
                .font(.system(size: 15))
                .tint(Theme.primary())
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                }
                .onChange(of: vm.keyword) { _, _ in
                    vm.onKeywordChanged()
                }
            if !vm.keyword.isEmpty {
                Button {
                    vm.keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                .buttonStyle(.plain)
            }
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
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .diaryGlassCard(cornerRadius: 28, interactive: true)
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
                    timeChip(L10n.str("search_7d"), kind: .d7)
                    timeChip(L10n.str("search_30d"), kind: .d30)
                    timeChip(L10n.str("search_custom"), kind: .custom)
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
                            noLoc: vm.locFilter.noLoc, force: true)
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

    private func locChip(_ label: String, country: String, region1: String, noLoc: Bool, force: Bool = false) -> some View {
        let active = force || (vm.locFilter.country == country && vm.locFilter.region1 == region1 && vm.locFilter.noLoc == noLoc)
        return GlassChip(label: label, active: active && force) {
            if force {
                if vm.locFilter.country.isEmpty && !vm.locFilter.noLoc {
                    vm.showLocSheet = true
                } else {
                    vm.resetLocFilter()
                }
            } else {
                vm.resetLocFilter()
            }
        }
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(vm.results, id: \.id) { item in
                    resultItem(item)
                        .onTapGesture {
                            vm.openDiary?(item.dayKey)
                        }
                }
                if vm.hasMore {
                    Button {
                        vm.loadMore()
                    } label: {
                        Text(L10n.str("search_load_more"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background {
                                Capsule().fill(Theme.primary())
                                    .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                                    .shadow(color: Theme.glowColor(), radius: 8, y: 2)
                            }
                    }
                    .buttonStyle(.plain)
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
        } else if !vm.keyword.isEmpty || vm.hasFilters {
            ContentUnavailableView.search(text: vm.keyword)
                .padding(.top, 60)
        } else {
            ContentUnavailableView(L10n.str("search_empty"),
                                   systemImage: "magnifyingglass",
                                   description: Text(L10n.str("search_no_result_hint")))
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
                }
                HighlightedText(snippet: item.snippet, summary: item.summary, keyword: vm.keyword)
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
            HStack {
                Text(L10n.str("search_time_title"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
                Spacer()
                Button {
                    vm.showTimeSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            HStack(spacing: 8) {
                quickRangeChip(L10n.str("search_7d")) {
                    vm.applyQuickRange(.d7)
                }
                quickRangeChip(L10n.str("search_30d")) {
                    vm.applyQuickRange(.d30)
                }
                quickRangeChip(L10n.str("search_time_month")) {
                    vm.applyQuickRange(.custom,
                                       customFrom: DateUtil.monthFirst(Date()),
                                       customTo: Date())
                }
                quickRangeChip(L10n.str("search_time_year")) {
                    var comps = Calendar.current.dateComponents([.year], from: Date())
                    comps.month = 1
                    comps.day = 1
                    vm.applyQuickRange(.custom,
                                       customFrom: Calendar.current.date(from: comps),
                                       customTo: Date())
                }
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
                Button {
                    vm.clearTimeFilter()
                } label: {
                    Text(L10n.str("search_time_clear"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            Capsule().fill(Theme.glassDim())
                                .glassEffect(.regular, in: Capsule())
                        }
                }
                .buttonStyle(.plain)
                Button {
                    vm.applyCustomTime()
                } label: {
                    Text(L10n.str("search_time_apply"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            Capsule().fill(Theme.primary())
                                .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                                .shadow(color: Theme.glowColor(), radius: 10, y: 3)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .padding(.bottom, 8)
    }

    private func quickRangeChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primary())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(Theme.primaryContainer())
                        .glassEffect(tintedGlass(nil), in: Capsule())
                }
        }
        .buttonStyle(.plain)
    }

    private var locSheet: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L10n.str("search_loc_title"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
                Spacer()
                Button {
                    vm.showLocSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onSurfaceVariant())
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
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
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.glassDim())
                    .glassEffect(tintedGlass(nil),
                                 in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.glassBorder(), lineWidth: 1)
                    }
            }
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
            if vm.locOptions.isEmpty { vm.loadLocationOptions() }
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
