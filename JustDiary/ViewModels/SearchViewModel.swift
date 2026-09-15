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

enum SearchFilterKind: Hashable {
    case keyword
    case time
    case location
}

struct SearchFilterItem: Identifiable {
    var kind: SearchFilterKind
    var label: String
    var value: String?
    var id: String { value.map { "\(String(describing: kind))-\($0)" } ?? String(describing: kind) }
}

@Observable
final class SearchViewModel {
    var keyword = ""
    var keywords: [String] = []
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

    var effectiveKeywords: [String] {
        var list = keywords
        let input = keyword.trimmingCharacters(in: .whitespaces)
        if !input.isEmpty, !list.contains(input) {
            list.append(input)
        }
        return list
    }

    var combinedKeyword: String {
        effectiveKeywords.joined(separator: " ")
    }

    var hasAnyCondition: Bool {
        !effectiveKeywords.isEmpty || hasFilters
    }

    var activeFilterItems: [SearchFilterItem] {
        var items: [SearchFilterItem] = []
        let input = keyword.trimmingCharacters(in: .whitespaces)
        if !input.isEmpty, !keywords.contains(input) {
            items.append(SearchFilterItem(kind: .keyword, label: "“\(input)”", value: nil))
        }
        for term in keywords {
            items.append(SearchFilterItem(kind: .keyword, label: "“\(term)”", value: term))
        }
        switch timeKind {
        case .thisWeek:
            items.append(SearchFilterItem(kind: .time, label: L10n.str("search_time_week"), value: nil))
        case .thisMonth:
            items.append(SearchFilterItem(kind: .time, label: L10n.str("search_time_month"), value: nil))
        case .thisYear:
            items.append(SearchFilterItem(kind: .time, label: L10n.str("search_time_year"), value: nil))
        case .custom:
            if let from = customFrom, let to = customTo {
                items.append(SearchFilterItem(kind: .time, label: L10n.dateRange(from, to), value: nil))
            } else {
                items.append(SearchFilterItem(kind: .time, label: L10n.str("search_custom"), value: nil))
            }
        case .all:
            break
        }
        if locFilter.noLoc {
            items.append(SearchFilterItem(kind: .location, label: L10n.str("search_loc_no_loc"), value: nil))
        } else if !locFilter.country.isEmpty {
            if locFilter.region1.isEmpty {
                items.append(SearchFilterItem(kind: .location,
                                              label: "\(locFilter.country) · \(L10n.str("search_loc_country_only"))",
                                              value: nil))
            } else {
                items.append(SearchFilterItem(kind: .location,
                                              label: "\(locFilter.country) · \(locFilter.region1)",
                                              value: nil))
            }
        }
        return items
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

    func clearAll() {
        keyword = ""
        keywords = []
        timeKind = .all
        customFrom = nil
        customTo = nil
        locFilter = LocFilter(country: "", region1: "", noLoc: false)
        Task { await doSearch(reset: true) }
    }

    func commitKeyword() {
        let term = keyword.trimmingCharacters(in: .whitespaces)
        keyword = ""
        guard !term.isEmpty else { return }
        if !keywords.contains(term) {
            keywords.append(term)
        }
        Task { await doSearch(reset: true) }
    }

    func removeKeyword(_ term: String) {
        keywords.removeAll { $0 == term }
        Task { await doSearch(reset: true) }
    }

    func clearKeywordInput() {
        keyword = ""
        Task { await doSearch(reset: true) }
    }

    func clearFilter(_ kind: SearchFilterKind) {
        switch kind {
        case .keyword:
            keyword = ""
            keywords = []
        case .time:
            timeKind = .all
            customFrom = nil
            customTo = nil
        case .location:
            locFilter = LocFilter(country: "", region1: "", noLoc: false)
        }
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
        let query = combinedKeyword
        if !query.isEmpty || hasFilters {
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
        let result = await DiaryRepository.shared.search(keyword: query,
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
