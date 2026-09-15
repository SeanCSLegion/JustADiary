import Foundation
import Observation
import os

@Observable
final class FootprintViewModel {
    var years: [String] = []
    var yearFilter = "all"
    var timeKind: TimeRangeKind = .all
    var customFrom: Date?
    var customTo: Date?

    var stats = FootprintStats()
    var nodes: [FootprintNode] = []
    var yearly: [FootprintYearStat] = []
    var locatedCount = 0
    var unlocated = 0

    /// Ids of the tree nodes the user has expanded.
    var expanded: Set<String> = []

    private var loaded = false

    var timeRangeLabel: String {
        if timeKind == .custom, let from = customFrom, let to = customTo {
            return L10n.dateRange(from, to)
        }
        return L10n.str("footprint_time_custom")
    }

    var hasPlaces: Bool { !nodes.isEmpty }

    func applyTimeKind(_ kind: TimeRangeKind) {
        timeKind = kind
        if kind != .custom {
            customFrom = nil
            customTo = nil
        }
    }

    func clearTimeFilter() {
        timeKind = .all
        customFrom = nil
        customTo = nil
    }

    func applyCustomTime() {
        timeKind = .custom
    }

    func toggle(_ node: FootprintNode) {
        guard !node.isLeaf else { return }
        if expanded.contains(node.id) {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        await reload()
    }

    func reload() async {
        let rows = await DiaryRepository.shared.allFootprintRows()
        let located = rows.filter(FootprintDataService.hasPlace)

        var filtered = located
        if yearFilter != "all" {
            filtered = filtered.filter { $0.dayKey.hasPrefix(yearFilter) }
        }
        if timeKind != .all {
            let range = timeKind.dayKeyRange(customFrom: customFrom, customTo: customTo)
            filtered = filtered.filter { $0.dayKey >= range.0 && $0.dayKey <= range.1 }
        }

        stats = FootprintDataService.stats(filtered)
        nodes = FootprintDataService.buildTree(filtered)
        yearly = FootprintDataService.buildYearly(filtered)
        locatedCount = filtered.count
        // Blocks with no place information at all, independent of the filters.
        unlocated = rows.count - located.count

        var yearSet = Set<String>()
        for row in located where row.dayKey.count >= 4 {
            yearSet.insert(String(row.dayKey.prefix(4)))
        }
        years = yearSet.sorted(by: >)

        // Drop expansions that no longer exist so the state cannot grow unbounded
        // while the user changes the filters.
        pruneExpanded()
    }

    private func pruneExpanded() {
        guard !expanded.isEmpty else { return }
        var alive = Set<String>()
        func walk(_ list: [FootprintNode]) {
            for node in list {
                alive.insert(node.id)
                walk(node.children)
            }
        }
        walk(nodes)
        expanded.formIntersection(alive)
    }
}
