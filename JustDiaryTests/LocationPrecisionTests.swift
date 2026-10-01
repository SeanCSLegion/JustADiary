import XCTest
import Contacts
import CoreLocation
import MapKit
@testable import JustDiary

/// 地点精度：与 Apple 定位权限对齐的「上限」梯子，以及分享长图的降级规则。
///
/// 这里不碰 CoreLocation 的实时状态 —— `LocationResolver.maxPrecision` 是纯函数，
/// 直接按「权限 × horizontalAccuracy」逐格断言，跑在毫秒级。
final class LocationPrecisionTests: XCTestCase {

    private func region(country: String = "中国",
                        region1: String = "广东省",
                        region2: String = "深圳市",
                        region3: String = "南山区") -> LocRegion {
        LocRegion(country: country, countryCode: "CN", region1: region1,
                  region2: region2, region3: region3, locQuality: LocQuality.precise)
    }

    // MARK: - 权限 / 精度 → 上限

    /// 模糊位置：SDK 说坐标会被吸附到「所在区域」的代表点、误差约 5km，
    /// 所以无论那次定位报多少精度，上限都只到城市。
    func testReducedAccuracyAlwaysCapsAtCity() {
        for accuracy in [5.0, 100.0, 1000.0, 5000.0, 50000.0, -1.0] {
            XCTAssertEqual(LocationResolver.maxPrecision(accuracyAuthorization: .reducedAccuracy,
                                                         horizontalAccuracy: accuracy),
                           LocPrecision.city,
                           "模糊位置（hAcc=\(accuracy)）的上限只到城市")
        }
    }

    /// 精确位置：上限跟着这一次定位的 `horizontalAccuracy` 走。
    func testFullAccuracyLadderFollowsHorizontalAccuracy() {
        let cases: [(CLLocationAccuracy, String)] = [
            (5, LocPrecision.exact),
            (10, LocPrecision.exact),
            (11, LocPrecision.street),
            (100, LocPrecision.street),
            (101, LocPrecision.district),
            (1000, LocPrecision.district),
            (1001, LocPrecision.city),
            (3000, LocPrecision.city),
            (5000, LocPrecision.city),
            (5001, LocPrecision.province),
            (25000, LocPrecision.province),
            // Apple：负值表示经纬度无效 —— 只能往最粗的一侧倒。
            (-1, LocPrecision.province)
        ]
        for (accuracy, expected) in cases {
            XCTAssertEqual(LocationResolver.maxPrecision(accuracyAuthorization: .fullAccuracy,
                                                         horizontalAccuracy: accuracy),
                           expected, "hAcc=\(accuracy) 应记到 \(expected)")
        }
    }

    /// 上限只会砍掉更细的级别：模糊位置的菜单里不能再出现区县 / 街道 / 精确地点
    /// （旧实现给了 fullAccuracy 之外一律把区县摆出来，菜单比权限更细）。
    func testPrecisionMenuNeverOffersLevelsFinerThanTheCap() {
        XCTAssertEqual(LocationResolver.availablePrecisions(maxPrecision: LocPrecision.city),
                       [LocPrecision.city, LocPrecision.province])
        XCTAssertEqual(LocationResolver.availablePrecisions(maxPrecision: LocPrecision.district),
                       [LocPrecision.district, LocPrecision.city, LocPrecision.province])
        XCTAssertEqual(LocationResolver.availablePrecisions(maxPrecision: LocPrecision.exact),
                       LocPrecision.all)
    }

    /// 实时定位造出来的快照要带上**这一次**的上限，编辑器的菜单就是照它给的。
    ///
    /// 回归点：`LocationSnapshot.maxPrecision` 曾经有个默认值 `province`，而
    /// `resolve` 忘了传 —— 于是「已经给了精确位置，编辑页却只能选省份」。
    /// 现在这个字段没有默认值（漏传编译不过），这条用例再盯一遍接线。
    func testLiveSnapshotCarriesThePermissionCap() {
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 22.54, longitude: 114.06),
                             altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                             timestamp: Date())
        let precise = LocationResolver.snapshot(location: fix, placemark: nil,
                                                preferred: LocPrecision.auto,
                                                accuracyAuthorization: .fullAccuracy)
        XCTAssertEqual(precise.maxPrecision, LocPrecision.exact, "精确位置 + 5m 的上限是精确地点")
        XCTAssertEqual(precise.locPrecision, LocPrecision.exact, "auto 就按上限记录")
        XCTAssertEqual(LocationResolver.availablePrecisions(maxPrecision: precise.maxPrecision),
                       LocPrecision.all, "菜单要给得出全部级别")

        let reduced = LocationResolver.snapshot(location: fix, placemark: nil,
                                                preferred: LocPrecision.auto,
                                                accuracyAuthorization: .reducedAccuracy)
        XCTAssertEqual(reduced.maxPrecision, LocPrecision.city)
        XCTAssertEqual(LocationResolver.availablePrecisions(maxPrecision: reduced.maxPrecision),
                       [LocPrecision.city, LocPrecision.province],
                       "模糊位置的菜单里不该有区县 / 街道 / 精确地点")

        // 记着「省份」时：快照按省份记录，但上限仍然是权限给的 —— 用户随时能在
        // 菜单里改回更细的级别。
        let remembered = LocationResolver.snapshot(location: fix, placemark: nil,
                                                   preferred: LocPrecision.province,
                                                   accuracyAuthorization: .fullAccuracy)
        XCTAssertEqual(remembered.locPrecision, LocPrecision.province)
        XCTAssertEqual(remembered.maxPrecision, LocPrecision.exact)
    }

    /// 手动选过的精度只会让记录更粗，不会顶穿权限算出来的上限。
    func testRememberedPrecisionOnlyEverCoarsens() {
        XCTAssertEqual(LocationResolver.effective(precision: LocPrecision.auto, cap: LocPrecision.city),
                       LocPrecision.city, "auto = 跟随权限")
        XCTAssertEqual(LocationResolver.effective(precision: LocPrecision.exact, cap: LocPrecision.city),
                       LocPrecision.city, "记着「精确地点」也不能突破权限上限")
        XCTAssertEqual(LocationResolver.effective(precision: LocPrecision.district, cap: LocPrecision.exact),
                       LocPrecision.district, "手动选过区县，就一直只记到区县")
        XCTAssertEqual(LocationResolver.effective(precision: LocPrecision.province, cap: LocPrecision.exact),
                       LocPrecision.province)
        XCTAssertEqual(LocationResolver.effective(precision: "garbage", cap: LocPrecision.city),
                       LocPrecision.city, "坏值按 auto 处理")
    }

    /// 梯子本身：`rank` 越小越细，`coarser` 取更粗的那个，`none` 永远最粗。
    func testLadderOrdering() {
        XCTAssertLessThan(LocPrecision.rank(LocPrecision.exact), LocPrecision.rank(LocPrecision.street))
        XCTAssertLessThan(LocPrecision.rank(LocPrecision.street), LocPrecision.rank(LocPrecision.district))
        XCTAssertLessThan(LocPrecision.rank(LocPrecision.district), LocPrecision.rank(LocPrecision.city))
        XCTAssertLessThan(LocPrecision.rank(LocPrecision.city), LocPrecision.rank(LocPrecision.province))
        XCTAssertEqual(LocPrecision.coarser(LocPrecision.exact, LocPrecision.city), LocPrecision.city)
        XCTAssertEqual(LocPrecision.coarser(LocPrecision.province, LocPrecision.city), LocPrecision.province)
        XCTAssertEqual(LocPrecision.coarser(LocPrecision.none, LocPrecision.city), LocPrecision.none)
        XCTAssertEqual(LocPrecision.levels(cappedAt: LocPrecision.province), [LocPrecision.province])
        XCTAssertEqual(LocPrecision.levels(cappedAt: LocPrecision.city),
                       [LocPrecision.city, LocPrecision.province])
    }

    // MARK: - 分享：只从地区列重建，并且只能更粗

    /// 分享图里的地点**不可能**出现地点名与街道。
    ///
    /// `shareText` 的入参里根本没有 `loc_text`：一条记录在「精确地点」的日记，
    /// 按区县上限分享时得到的是地区列拼出的区县地址。
    func testShareTextRebuildsFromRegionColumnsOnly() {
        let text = LocationResolver.shareText(recorded: LocPrecision.exact,
                                              region: region(),
                                              cap: LocPrecision.district)
        XCTAssertEqual(text, "南山区 · 深圳市 · 广东省 · 中国")
        for leaked in ["深南大道", "腾讯", "大厦", "街道"] {
            XCTAssertFalse(text.contains(leaked), "分享文案里不该出现「\(leaked)」")
        }
    }

    /// 上限 = 隐藏：一个字都不给。
    func testShareTextIsEmptyWhenHidden() {
        for recorded in LocPrecision.all {
            XCTAssertEqual(LocationResolver.shareText(recorded: recorded,
                                                      region: region(),
                                                      cap: LocPrecision.none),
                           "", "隐藏时记录精度是 \(recorded) 也不显示地点")
        }
    }

    /// 记录精度比上限更粗时按记录的来：分享只能更粗，不会凭空变细。
    func testShareTextHonoursCoarserRecordedLevel() {
        XCTAssertEqual(LocationResolver.shareText(recorded: LocPrecision.province,
                                                  region: region(), cap: LocPrecision.district),
                       "广东省 · 中国")
        XCTAssertEqual(LocationResolver.shareText(recorded: LocPrecision.city,
                                                  region: region(), cap: LocPrecision.district),
                       "深圳市 · 广东省 · 中国")
    }

    /// 地区列缺失（早期版本、或这行本来没有地点）时宁可不显示，也不退回原文。
    func testShareTextStaysEmptyWithoutRegionColumns() {
        let empty = LocRegion(country: "", countryCode: "", region1: "",
                              region2: "", region3: "", locQuality: LocQuality.none)
        XCTAssertEqual(LocationResolver.shareText(recorded: LocPrecision.exact,
                                                  region: empty, cap: LocPrecision.district), "")
        // 没有有效精度标签的记录（`none` / 空 / 坏值）同样不分享地点。
        for recorded in [LocPrecision.none, "", "garbage"] {
            XCTAssertEqual(LocationResolver.shareText(recorded: recorded,
                                                      region: region(), cap: LocPrecision.district), "")
        }
    }

    /// 设置层已经挡过一次，这里再挡一次：比区县更细的上限也只按区县重建。
    func testShareTextClampsCapsFinerThanDistrict() {
        for cap in [LocPrecision.exact, LocPrecision.street, "garbage"] {
            let text = LocationResolver.shareText(recorded: LocPrecision.exact,
                                                  region: region(), cap: cap)
            XCTAssertEqual(text, "南山区 · 深圳市 · 广东省 · 中国",
                           "上限 \(cap) 只该退到可分享的最细一级")
        }
    }

    /// 从库里的一条片段走到分享块：`loc_text` 里的地点名与街道一个都不能带出来。
    ///
    /// 这条路径就是 `DiaryViewModel.shareDiary()` 走的那条，所以它在测「分享」
    /// 这件事本身，而不只是某个字符串函数。
    func testShareBlockFromStoredBlockNeverCarriesPlaceOrStreet() {
        let block = EditBlock(id: 1, diaryId: 1, startTimeUtc: 1_788_700_000_000,
                              locText: "腾讯滨海大厦, 深南大道 · 南山区 · 深圳市 · 广东省 · 中国",
                              latitude: 22.54, longitude: 114.06,
                              contentJson: #"{"v":2,"parts":[{"style":"body","text":"正文"}]}"#,
                              searchText: "正文",
                              locPrecision: LocPrecision.exact, locQuality: LocQuality.precise,
                              country: "中国", countryCode: "CN",
                              region1: "广东省", region2: "深圳市", region3: "南山区",
                              createdUtc: 0, updatedUtc: 0)

        let capped = ShareBlock.capped(block, cap: LocPrecision.district)
        XCTAssertEqual(capped.loc, "南山区 · 深圳市 · 广东省 · 中国")
        XCTAssertEqual(capped.parts.count, 1)
        XCTAssertFalse(capped.loc.contains("深南大道"))
        XCTAssertFalse(capped.loc.contains("腾讯"))

        XCTAssertEqual(ShareBlock.capped(block, cap: LocPrecision.none).loc, "",
                       "设置为隐藏时分享块不带地点")
        XCTAssertEqual(ShareBlock.capped(block, cap: LocPrecision.province).loc, "广东省 · 中国")
    }

    // MARK: - 从地区列重建的文案

    func testRegionTextPerLevel() {
        let r = region()
        XCTAssertEqual(LocationResolver.text(for: r, precision: LocPrecision.district),
                       "南山区 · 深圳市 · 广东省 · 中国")
        XCTAssertEqual(LocationResolver.text(for: r, precision: LocPrecision.city),
                       "深圳市 · 广东省 · 中国")
        XCTAssertEqual(LocationResolver.text(for: r, precision: LocPrecision.province),
                       "广东省 · 中国")
        // 精确地点 / 街道没有存地点名与街道，只能退到区县。
        XCTAssertEqual(LocationResolver.text(for: r, precision: LocPrecision.exact),
                       "南山区 · 深圳市 · 广东省 · 中国")
        // 区县列为空时自然退到城市。
        let noDistrict = region(region3: "")
        XCTAssertEqual(LocationResolver.text(for: noDistrict, precision: LocPrecision.district),
                       "深圳市 · 广东省 · 中国")
    }

    /// 区县级的地址文案要取 `subLocality`（中国的「南山区」在这里）。
    ///
    /// 以前只看 `subAdministrativeArea`，于是「区县」级在中国常常只显示到市，
    /// 与地区列重建出来的文案对不上。
    func testDistrictPlacemarkTextUsesSubLocality() {
        let mark = placemark(street: "深南大道", subLocality: "南山区",
                             city: "深圳市", state: "广东省", country: "中国")
        XCTAssertEqual(LocationResolver.text(for: mark, precision: LocPrecision.district),
                       "南山区 · 深圳市 · 广东省 · 中国")
        // 街道级仍然是道路 + 城市/省/国家，不含地点名。
        let street = LocationResolver.text(for: mark, precision: LocPrecision.street)
        XCTAssertEqual(street, "深南大道 · 深圳市 · 广东省 · 中国")
    }

    // MARK: - 临时精确位置的用途键

    /// 用途键必须和 `Info.plist`、`en.lproj/InfoPlist.strings` 对得上。
    ///
    /// Apple 的规则（`CLLocationManager.h` 里那段注释）：`Info.plist` 里没有这个键
    /// 就不弹授权框；弹框文案则是 CoreLocation 拿**用途键本身**去 `InfoPlist.strings`
    /// 里查，查不到才退回 `Info.plist` 的值。代码里只看得到那个常量，所以在这里锁一次。
    func testFullAccuracyPurposeKeyMatchesPlistAndStrings() throws {
        let purposeKey = LocationService.fullAccuracyPurposeKey
        let dictionary = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "NSLocationTemporaryUsageDescriptionDictionary") as? [String: String],
            "Info.plist 应有 NSLocationTemporaryUsageDescriptionDictionary")
        XCTAssertNotNil(dictionary[purposeKey], "用途键「\(purposeKey)」必须在字典里")

        let url = try XCTUnwrap(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings",
                                                subdirectory: nil, localization: "en"),
                                "应有 en.lproj/InfoPlist.strings")
        let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertNotNil(strings[purposeKey], "en.lproj/InfoPlist.strings 里应有「\(purposeKey)」")
    }

    /// 造一个带着地区字段的 placemark。
    ///
    /// `MKPlacemark` 在 iOS 26 被标为废弃（MapKit 改推 `MKAddressRepresentations`），
    /// 但那是**展示用**的类型，构造不出 `CLPlacemark` 的 `subLocality` / `locality`
    /// 等结构字段 —— 与 `MKMapItem+Placemark.swift` 里那处 `@diagnose` 同一个理由，
    /// 这里也只对这一个声明放行。
    @diagnose(DeprecatedDeclaration, as: ignored,
              reason: "tests need a CLPlacemark carrying subLocality/locality for the district address text; MKPlacemark is the only constructible entry point")
    private func placemark(street: String, subLocality: String, city: String,
                           state: String, country: String) -> MKPlacemark {
        let address = CNMutablePostalAddress()
        address.street = street
        address.subLocality = subLocality
        address.city = city
        address.state = state
        address.country = country
        return MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 22.54, longitude: 114.06),
                           postalAddress: address)
    }
}
