import SwiftUI

enum TimeRangeKind: String {
    case all
    case d7
    case d30
    case custom
}

struct SearchView: View {
    var openDiary: (String) -> Void

    @State private var keyword = ""
    @State private var timeKind: TimeRangeKind = .all
    @State private var customFrom: Date?
    @State private var customTo: Date?
    @State private var locFilter = LocFilter(country: "", region1: "", noLoc: false)
    @State private var results: [SearchResultItem] = []
    @State private var total = 0
    @State private var hasMore = false
    @State private var searching = false
    @State private var indexing = false
    @State private var offset = 0
    @State private var showTimeSheet = false
    @State private var showLocSheet = false
    @State private var locOptions: [LocOption] = []
    @State private var noLocCount = 0
    @State private var locSearch = ""
    @State private var locLoading = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @FocusState private var locSearchFocused: Bool

    var body: some View {
        content
            .sheet(isPresented: $showTimeSheet) {
                timeSheet
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showLocSheet) {
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
            if total > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Theme.primary()).frame(width: 6, height: 6)
                    Text(L10n.fmt("search_result_count", total))
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
            TextField(L10n.str("search_placeholder"), text: $keyword)
                .font(.system(size: 15))
                .tint(Theme.primary())
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                }
                .onChange(of: keyword) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        await doSearch(reset: true)
                    }
                }
            if !keyword.isEmpty {
                Button {
                    keyword = ""
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
                    locChip(locFilterLabel, country: locFilter.country, region1: locFilter.region1,
                            noLoc: locFilter.noLoc, force: true)
                }
            }
        }
        .padding(10)
        .diaryGlassCard(cornerRadius: 22)
    }

    private var locFilterLabel: String {
        if locFilter.noLoc { return L10n.str("search_loc_no_loc") }
        if locFilter.country.isEmpty { return L10n.str("search_loc_picker") }
        if locFilter.region1.isEmpty { return "\(locFilter.country) · \(L10n.str("search_loc_country_only"))" }
        return "\(locFilter.country) · \(locFilter.region1)"
    }

    private func timeChip(_ label: String, kind: TimeRangeKind) -> some View {
        GlassChip(label: label, active: timeKind == kind) {
            if kind == .custom {
                showTimeSheet = true
            } else {
                timeKind = kind
                Task { await doSearch(reset: true) }
            }
        }
    }

    private func locChip(_ label: String, country: String, region1: String, noLoc: Bool, force: Bool = false) -> some View {
        let active = force || (locFilter.country == country && locFilter.region1 == region1 && locFilter.noLoc == noLoc)
        return GlassChip(label: label, active: active && force) {
            if force {
                if locFilter.country.isEmpty && !locFilter.noLoc {
                    showLocSheet = true
                } else {
                    locFilter = LocFilter(country: "", region1: "", noLoc: false)
                    Task { await doSearch(reset: true) }
                }
            } else {
                locFilter = LocFilter(country: "", region1: "", noLoc: false)
                Task { await doSearch(reset: true) }
            }
        }
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(results, id: \.id) { item in
                    resultItem(item)
                        .onTapGesture {
                            openDiary(item.dayKey)
                        }
                }
                if hasMore {
                    Button {
                        Task { await doSearch(reset: false) }
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
                if results.isEmpty, !searching {
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
        if indexing || searching {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.primary())
                Text(searching ? L10n.str("search_loading") : L10n.str("search_preparing"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.onSurface())
            }
            .padding(.top, 60)
        } else if !keyword.isEmpty || hasFilters {
            ContentUnavailableView.search(text: keyword)
                .padding(.top, 60)
        } else {
            ContentUnavailableView(L10n.str("search_empty"),
                                   systemImage: "magnifyingglass",
                                   description: Text(L10n.str("search_no_result_hint")))
                .padding(.top, 60)
        }
    }

    private var hasFilters: Bool {
        timeKind != .all || locFilter.country != "" || locFilter.noLoc
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
                HighlightedText(snippet: item.snippet, summary: item.summary, keyword: keyword)
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

    // MARK: - Search logic

    private func doSearch(reset: Bool) async {
        if !keyword.trimmingCharacters(in: .whitespaces).isEmpty || hasFilters {
            searching = true
        } else {
            results = []
            total = 0
            hasMore = false
            return
        }
        indexing = !DiaryRepository.shared.searchIndexReady()
        await DiaryRepository.shared.ensureSearchIndex()
        let range = currentRange()
        let fromKey = range.0
        let toKey = range.1
        let newOffset = reset ? 0 : offset
        let result = await DiaryRepository.shared.search(keyword: keyword,
                                                         fromKey: fromKey,
                                                         toKey: toKey,
                                                         filter: locFilter,
                                                         offset: newOffset)
        if reset {
            results = result.items
            offset = result.items.count
        } else {
            var merged = results
            merged.append(contentsOf: result.items)
            results = merged
            offset = merged.count
        }
        total = result.total
        hasMore = result.hasMore
        searching = false
    }

    private func currentRange() -> (String, String) {
        let today = Date()
        switch timeKind {
        case .d7:
            return (DateUtil.dayKeyOf(DateUtil.addDays(DateUtil.startOfDay(today), -6)), DateUtil.dayKeyOf(today))
        case .d30:
            return (DateUtil.dayKeyOf(DateUtil.addDays(DateUtil.startOfDay(today), -29)), DateUtil.dayKeyOf(today))
        case .custom:
            let from = customFrom ?? DateUtil.startOfDay(today)
            let to = customTo ?? DateUtil.startOfDay(today)
            let sorted = from <= to ? (from, to) : (to, from)
            return (DateUtil.dayKeyOf(sorted.0), DateUtil.dayKeyOf(sorted.1))
        case .all:
            return ("0000-01-01", "9999-12-31")
        }
    }

    private func loadLocationOptions() {
        locLoading = true
        Task {
            let range = currentRange()
            let result = await DiaryRepository.shared.getLocationOptions(keyword: "",
                                                                         fromKey: range.0,
                                                                         toKey: range.1)
            locOptions = result.options
            noLocCount = result.noLocCount
            locLoading = false
        }
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
                    showTimeSheet = false
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
                    timeKind = .d7
                    showTimeSheet = false
                    Task { await doSearch(reset: true) }
                }
                quickRangeChip(L10n.str("search_30d")) {
                    timeKind = .d30
                    showTimeSheet = false
                    Task { await doSearch(reset: true) }
                }
                quickRangeChip(L10n.str("search_time_month")) {
                    customFrom = DateUtil.monthFirst(Date())
                    customTo = Date()
                    timeKind = .custom
                    showTimeSheet = false
                    Task { await doSearch(reset: true) }
                }
                quickRangeChip(L10n.str("search_time_year")) {
                    var comps = Calendar.current.dateComponents([.year], from: Date())
                    comps.month = 1
                    comps.day = 1
                    customFrom = Calendar.current.date(from: comps)
                    customTo = Date()
                    timeKind = .custom
                    showTimeSheet = false
                    Task { await doSearch(reset: true) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.str("search_time_start"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
                DatePicker("", selection: Binding(
                    get: { customFrom ?? DateUtil.monthFirst(Date()) },
                    set: { customFrom = DateUtil.startOfDay($0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.primary())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.str("search_time_end"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant())
                DatePicker("", selection: Binding(
                    get: { customTo ?? Date() },
                    set: { customTo = DateUtil.startOfDay($0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.primary())
            }
            HStack(spacing: 12) {
                Button {
                    timeKind = .all
                    customFrom = nil
                    customTo = nil
                    showTimeSheet = false
                    Task { await doSearch(reset: true) }
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
                    timeKind = .custom
                    showTimeSheet = false
                    Task { await doSearch(reset: true) }
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
                    showLocSheet = false
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
                TextField(L10n.str("search_loc_search"), text: $locSearch)
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
                    if noLocCount > 0 {
                        locRow(label: "\(L10n.str("search_loc_no_loc")) (\(noLocCount))", country: "", region1: "", noLoc: true, count: nil)
                    }
                    ForEach(filteredOptions, id: \.self) { option in
                        locRow(label: "\(option.country)\(option.region1.isEmpty ? "" : " · \(option.region1)")",
                               country: option.country, region1: option.region1, noLoc: false, count: option.count)
                    }
                    if filteredOptions.isEmpty && !locLoading {
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
            if locOptions.isEmpty { loadLocationOptions() }
        }
    }

    private var filteredOptions: [LocOption] {
        guard !locSearch.isEmpty else { return locOptions }
        let kw = locSearch.lowercased()
        return locOptions.filter { $0.country.lowercased().contains(kw) || $0.region1.lowercased().contains(kw) }
    }

    private func locRow(label: String, country: String, region1: String, noLoc: Bool, count: Int?) -> some View {
        let active = locFilter.country == country && locFilter.region1 == region1 && locFilter.noLoc == noLoc
        return Button {
            Haptics.tap()
            locFilter = LocFilter(country: country, region1: region1, noLoc: noLoc)
            showLocSheet = false
            Task { await doSearch(reset: true) }
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
