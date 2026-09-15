import Foundation

/// A node in the footprint tree: country → province → city.
///
/// The tree is built from the non-empty place components of each diary block, so
/// it degrades gracefully in places where a level does not exist (for example a
/// municipality such as 北京市 has no province, and a country with no region data
/// yields a single-level node).
nonisolated struct FootprintNode: Identifiable, Hashable {
    /// `\u{1}`-joined component path, unique per node and stable across reloads.
    var id: String
    var name: String
    /// Number of diary blocks recorded at or below this node.
    var count: Int
    var children: [FootprintNode]

    var isLeaf: Bool { children.isEmpty }
}

nonisolated struct FootprintYearStat: Identifiable, Hashable {
    var id: String { year }
    var year: String
    var days: Int
    var places: Int
}

nonisolated struct FootprintStats {
    var provinces = Set<String>()
    var cities = Set<String>()
    var countries = Set<String>()
    var blocks = 0
    var days = Set<String>()
}

/// Aggregates diary blocks into the footprints shown on the 足迹 tab.
///
/// Unlike the previous map implementation this is purely a data aggregation: it
/// needs no coordinates and no bundled boundary data, so it works for every
/// country rather than only those with GeoJSON shipped in the app.
nonisolated enum FootprintDataService {
    private static let separator = "\u{1}"

    /// A row counts as located when it carries any place information at all.
    /// This replaces the old map-specific rule (which additionally required a
    /// usable coordinate or a same-city/same-province centroid), because the
    /// footprint list no longer needs coordinates.
    static func hasPlace(_ row: FootprintRow) -> Bool {
        !row.country.isEmpty || !row.region1.isEmpty || !row.region2.isEmpty
            || !row.region3.isEmpty || !row.locText.isEmpty
    }

    /// Non-empty place components, e.g. ["中国", "广东省", "深圳市"].
    static func path(of row: FootprintRow) -> [String] {
        var parts: [String] = []
        if !row.country.isEmpty { parts.append(row.country) }
        if !row.region1.isEmpty { parts.append(row.region1) }
        if !row.region2.isEmpty { parts.append(row.region2) }
        if parts.isEmpty, !row.locText.isEmpty { parts.append(row.locText) }
        return parts
    }

    static func stats(_ rows: [FootprintRow]) -> FootprintStats {
        var s = FootprintStats()
        for row in rows where hasPlace(row) {
            if !row.country.isEmpty { s.countries.insert(row.country) }
            if !row.region1.isEmpty {
                s.provinces.insert(row.country + separator + row.region1)
            }
            if !row.region2.isEmpty {
                s.cities.insert(row.country + separator + row.region1 + separator + row.region2)
            }
            s.blocks += 1
            if !row.dayKey.isEmpty { s.days.insert(row.dayKey) }
        }
        return s
    }

    static func buildTree(_ rows: [FootprintRow]) -> [FootprintNode] {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        var childKeys: [String: Set<String>] = [:]
        let root = ""

        for row in rows {
            var accumulated: [String] = []
            var parent = root
            for part in path(of: row) {
                accumulated.append(part)
                let key = accumulated.joined(separator: separator)
                names[key] = part
                childKeys[parent, default: []].insert(key)
                counts[key, default: 0] += 1
                parent = key
            }
        }

        func order(_ keys: Set<String>) -> [String] {
            keys.sorted { a, b in
                let ca = counts[a] ?? 0, cb = counts[b] ?? 0
                if ca != cb { return ca > cb }
                return (names[a] ?? a).localizedStandardCompare(names[b] ?? b) == .orderedAscending
            }
        }

        func make(_ key: String) -> FootprintNode {
            let children = order(childKeys[key] ?? []).map(make)
            return FootprintNode(id: key,
                                 name: names[key] ?? key,
                                 count: counts[key] ?? 0,
                                 children: children)
        }

        return order(childKeys[root] ?? []).map(make)
    }

    /// Distinct recorded days and distinct places per calendar year, oldest first.
    static func buildYearly(_ rows: [FootprintRow]) -> [FootprintYearStat] {
        struct Acc {
            var days = Set<String>()
            var places = Set<String>()
        }
        var byYear: [String: Acc] = [:]
        for row in rows where hasPlace(row) {
            guard row.dayKey.count >= 4 else { continue }
            let year = String(row.dayKey.prefix(4))
            var acc = byYear[year] ?? Acc()
            if !row.dayKey.isEmpty { acc.days.insert(row.dayKey) }
            let key = path(of: row).joined(separator: separator)
            if !key.isEmpty { acc.places.insert(key) }
            byYear[year] = acc
        }
        return byYear.keys.sorted().map { year in
            let acc = byYear[year] ?? Acc()
            return FootprintYearStat(year: year, days: acc.days.count, places: acc.places.count)
        }
    }
}
