import Foundation

struct DiaryRecord {
    var id: Int64
    var dayKey: String
    var summary: String
    var searchText: String
    var createdUtc: Int64
    var updatedUtc: Int64
}

struct EditBlock {
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

struct LocRegion {
    var country: String
    var countryCode: String
    var region1: String
    var region2: String
    var region3: String
    var locQuality: String
}

struct LocFilter {
    var country: String
    var region1: String
    var noLoc: Bool
}

struct LocOption: Hashable {
    var country: String
    var region1: String
    var count: Int
}

struct DiaryCardInfo {
    var dayKey: String
    var hasDiary: Bool
    var startTimeUtc: Int64
    var locText: String
    var preview: String
}

struct MapPointRow {
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

struct SearchResultItem {
    var id: Int64
    var dayKey: String
    var summary: String
    var snippet: String
    var updatedUtc: Int64
}

struct SearchPageResult {
    var items: [SearchResultItem]
    var hasMore: Bool
    var total: Int
}

enum LocPrecision {
    static let none = "none"
    static let province = "province"
    static let city = "city"
    static let district = "district"
    static let street = "street"
    static let exact = "exact"

    static let all: [String] = [exact, street, district, city, province]
}

enum LocQuality {
    static let none = "none"
    static let coarse = "coarse"
    static let precise = "precise"
}
