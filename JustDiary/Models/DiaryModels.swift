import Foundation

nonisolated struct DiaryRecord {
    var id: Int64
    var dayKey: String
    var summary: String
    var searchText: String
    var createdUtc: Int64
    var updatedUtc: Int64
}

nonisolated struct EditBlock {
    var id: Int64
    var diaryId: Int64
    var startTimeUtc: Int64
    var locText: String
    var latitude: Double
    var longitude: Double
    var contentJson: String
    var searchText: String
    var locPrecision: String
    var locQuality: String
    var country: String
    var countryCode: String
    var region1: String
    var region2: String
    var region3: String
    var createdUtc: Int64
    var updatedUtc: Int64
}

nonisolated struct LocRegion {
    var country: String
    var countryCode: String
    var region1: String
    var region2: String
    var region3: String
    var locQuality: String
}

nonisolated struct LocFilter {
    var country: String
    var region1: String
    var noLoc: Bool
}

nonisolated struct LocOption: Hashable {
    var country: String
    var region1: String
    var count: Int
}

nonisolated struct FootprintRow {
    var id: Int64
    var dayKey: String
    var startTimeUtc: Int64
    var latitude: Double
    var longitude: Double
    var locText: String
    var locQuality: String
    var locPrecision: String
    var country: String
    var countryCode: String
    var region1: String
    var region2: String
    var region3: String
    var summary: String
}

nonisolated struct SearchResultItem {
    var id: Int64
    var dayKey: String
    var summary: String
    var snippet: String
    var updatedUtc: Int64
}

nonisolated struct SearchPageResult {
    var items: [SearchResultItem]
    var hasMore: Bool
    var total: Int
}

nonisolated enum LocPrecision {
    static let none = "none"
    static let province = "province"
    static let city = "city"
    static let district = "district"
    static let street = "street"
    static let exact = "exact"

    static let all: [String] = [exact, street, district, city, province]
}

nonisolated enum LocQuality {
    static let none = "none"
    static let coarse = "coarse"
    static let precise = "precise"
}
