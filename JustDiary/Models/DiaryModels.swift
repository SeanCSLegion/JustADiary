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

nonisolated extension LocRegion {
    /// The region columns a stored block carries. Location columns are written
    /// once, when the block is created, so this is the only place the app can
    /// rebuild a coarser address text from (see `LocationResolver.shareText`).
    init(block: EditBlock) {
        self.init(country: block.country, countryCode: block.countryCode,
                  region1: block.region1, region2: block.region2, region3: block.region3,
                  locQuality: block.locQuality)
    }
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

    /// `LocPrecision` 的值域里唯一一个**不是级别**的成员：它只用于
    /// 「上一次手动选的精度」这个偏好，意思是「跟随定位权限算出来的上限」。
    static let auto = "auto"

    /// 由细到粗。**索引越大越粗**，梯子是本文件里所有「只能降级」判断的唯一依据
    /// （分享上限、权限上限、编辑器的可选级别）。
    static let all: [String] = [exact, street, district, city, province]

    /// 分享长图允许出现的级别：**精确地点与街道不在其中**。
    ///
    /// 这不是「默认值」而是硬约束：`shareText` 只按这三个级别重建地址，
    /// 用户在任何设置下都无法把地点名或街道分享出去（见 docs/location-recording.md）。
    static let shareable: [String] = [district, city, province]

    /// 在梯子上的位置：0 = 最细。`none`（没有地点）与任何未知值都按「最粗」处理，
    /// 这样 `coarser(_:_:)` 遇到坏数据时总是往安全的一侧倒。
    static func rank(_ precision: String) -> Int {
        all.firstIndex(of: precision) ?? all.count
    }

    /// 两个级别里更粗的那个。
    static func coarser(_ a: String, _ b: String) -> String {
        rank(a) >= rank(b) ? a : b
    }

    /// 梯子上**不细于** `cap` 的级别（由细到粗）。
    ///
    /// 上限只砍掉更细的那几级：`cappedAt(city)` = [city, province]，
    /// 于是「只给了模糊位置」的菜单里不会出现区县、街道与精确地点。
    /// （注意 `rank` 越小越**细**，所以这里是 `>=`。）
    static func levels(cappedAt cap: String) -> [String] {
        let levels = all.filter { rank($0) >= rank(cap) }
        return levels.isEmpty ? [province] : levels
    }
}

nonisolated enum LocQuality {
    static let none = "none"
    static let coarse = "coarse"
    static let precise = "precise"
}
