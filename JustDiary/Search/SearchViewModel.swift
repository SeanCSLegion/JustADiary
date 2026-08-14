import SwiftUI

enum TimeRangeKind: String {
    case all
    case thisWeek
    case thisMonth
    case thisYear
    case custom

    func dayKeyRange(customFrom: Date?, customTo: Date?) -> (String, String) {
        let today = Date()
        switch self {
        case .thisWeek:
            return (DateUtil.dayKeyOf(DateUtil.weekFirst(today)), DateUtil.dayKeyOf(today))
        case .thisMonth:
            return (DateUtil.dayKeyOf(DateUtil.monthFirst(today)), DateUtil.dayKeyOf(today))
        case .thisYear:
            let year = DateUtil.calendar.component(.year, from: today)
            let start = DateUtil.calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today
            return (DateUtil.dayKeyOf(start), DateUtil.dayKeyOf(today))
        case .custom:
            let from = customFrom ?? DateUtil.startOfDay(today)
            let to = customTo ?? DateUtil.startOfDay(today)
            let sorted = from <= to ? (from, to) : (to, from)
            return (DateUtil.dayKeyOf(sorted.0), DateUtil.dayKeyOf(sorted.1))
        case .all:
            return ("0000-01-01", "9999-12-31")
        }
    }
}

@Observable
final class SearchViewModel {
    var keyword = ""
    var timeKind: TimeRangeKind = .all
    var customFrom: Date?
    var customTo: Date?
    var locFilter = LocFilter(country: "", region1: "", noLoc: false)
    var results: [SearchResultItem] = []
    var total = 0
    var hasMore = false
    var searching = false
    var indexing = false
    var offset = 0
    var showTimeSheet = false
    var showLocSheet = false
    var locOptions: [LocOption] = []
    var noLocCount = 0
    var locSearch = ""
    var locLoading = false

    private var searchTask: Task<Void, Never>?
    private var currentSearchId = 0

    var openDiary: ((String) -> Void)?

    var locFilterLabel: String {
        if locFilter.noLoc { return L10n.str("search_loc_no_loc") }
        if locFilter.country.isEmpty { return L10n.str("search_loc_picker") }
        if locFilter.region1.isEmpty { return "\(locFilter.country) · \(L10n.str("search_loc_country_only"))" }
        return "\(locFilter.country) · \(locFilter.region1)"
    }

    var hasFilters: Bool {
        timeKind != .all || locFilter.country != "" || locFilter.noLoc
    }

    var timeRangeLabel: String {
        if timeKind == .custom, let from = customFrom, let to = customTo {
            return L10n.dateRange(from, to)
        }
        return L10n.str("search_custom")
    }

    var filteredOptions: [LocOption] {
        guard !locSearch.isEmpty else { return locOptions }
        let kw = locSearch.lowercased()
        return locOptions.filter { $0.country.lowercased().contains(kw) || $0.region1.lowercased().contains(kw) }
    }

    func onKeywordChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await doSearch(reset: true)
        }
    }

    func setTimeKind(_ kind: TimeRangeKind) {
        timeKind = kind
        Task { await doSearch(reset: true) }
    }

    func setLocFilter(country: String, region1: String, noLoc: Bool, showPicker: Bool) {
        locFilter = LocFilter(country: country, region1: region1, noLoc: noLoc)
        if showPicker {
            showLocSheet = true
        } else {
            Task { await doSearch(reset: true) }
        }
    }

    func resetLocFilter() {
        locFilter = LocFilter(country: "", region1: "", noLoc: false)
        Task { await doSearch(reset: true) }
    }

    func selectLocRow(country: String, region1: String, noLoc: Bool) {
        Haptics.tap()
        locFilter = LocFilter(country: country, region1: region1, noLoc: noLoc)
        showLocSheet = false
        Task { await doSearch(reset: true) }
    }

    func applyQuickRange(_ kind: TimeRangeKind, customFrom: Date? = nil, customTo: Date? = nil) {
        timeKind = kind
        self.customFrom = customFrom
        self.customTo = customTo
        showTimeSheet = false
        Task { await doSearch(reset: true) }
    }

    func clearTimeFilter() {
        timeKind = .all
        customFrom = nil
        customTo = nil
        showTimeSheet = false
        Task { await doSearch(reset: true) }
    }

    func applyCustomTime() {
        timeKind = .custom
        showTimeSheet = false
        Task { await doSearch(reset: true) }
    }

    func loadMore() {
        Task { await doSearch(reset: false) }
    }

    func loadLocationOptions() {
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

    func doSearch(reset: Bool) async {
        if !keyword.trimmingCharacters(in: .whitespaces).isEmpty || hasFilters {
            searching = true
        } else {
            results = []
            total = 0
            hasMore = false
            return
        }

        indexing = !DiaryRepository.shared.searchIndexReady()
        let searchId = currentSearchId + 1
        currentSearchId = searchId

        await DiaryRepository.shared.ensureSearchIndex()

        guard currentSearchId == searchId else { return }

        let range = currentRange()
        let fromKey = range.0
        let toKey = range.1
        let newOffset = reset ? 0 : offset
        let result = await DiaryRepository.shared.search(keyword: keyword,
                                                         fromKey: fromKey,
                                                         toKey: toKey,
                                                         filter: locFilter,
                                                         offset: newOffset)

        guard currentSearchId == searchId else { return }

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
        indexing = false
    }

    private func currentRange() -> (String, String) {
        timeKind.dayKeyRange(customFrom: customFrom, customTo: customTo)
    }
}
