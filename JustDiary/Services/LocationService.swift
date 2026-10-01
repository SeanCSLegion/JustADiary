import CoreLocation
import Foundation
import MapKit
import os

// Reuse a single CLLocationManager for reading authorization state instead of
// allocating a throwaway instance on every access.
private let statusManager = CLLocationManager()

enum LocStatus {
    static func current() -> CLAuthorizationStatus {
        statusManager.authorizationStatus
    }

    /// Apple 的「精确位置 / 模糊位置」开关（`accuracyAuthorization`）。
    ///
    /// 它是**独立于**授权状态的第二档权限：用户可以在只给模糊位置的情况下
    /// 正常授权。记录精度必须同时看这两者（见 `LocationResolver.maxPrecision`）。
    static var accuracy: CLAccuracyAuthorization {
        statusManager.accuracyAuthorization
    }

    static var isAuthorized: Bool {
        let status = current()
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static var isPrecise: Bool {
        isAuthorized && (statusManager.accuracyAuthorization == .fullAccuracy)
    }

    /// 已授权、但用户在系统里关掉了「精确位置」。
    ///
    /// SDK 对 `CLAccuracyAuthorizationReducedAccuracy` 的说明：定位会被吸附到
    /// 「设备所在区域」的代表点，`horizontalAccuracy` 约 5km，且两次定位之间
    /// 可能隔上 20 分钟。所以它支撑不起区县以上的精度。
    static var isReducedAccuracy: Bool {
        isAuthorized && !isPrecise
    }
}

final class LocationService {
    static let shared = LocationService()

    /// `Info.plist` › `NSLocationTemporaryUsageDescriptionDictionary` 里的键。
    ///
    /// 只授了模糊位置时，Apple 允许 App 用这条用途说明向用户**临时**申请一次精确位置
    /// （`requestTemporaryFullAccuracyAuthorization`）。SDK 的规则：用途键必须能在那个
    /// 字典里找到，否则**根本不会弹框**；弹框文案则是 CoreLocation 拿这个键去
    /// `InfoPlist.strings` 里查，查不到才用 `Info.plist` 里的值 —— 所以改这个常量时
    /// `Info.plist`、`en.lproj/InfoPlist.strings` 要一起改，
    /// `LocationPrecisionTests.testFullAccuracyPurposeKeyMatchesPlistAndStrings` 会盯着。
    static let fullAccuracyPurposeKey = "JustDiaryPreciseLocation"

    private let manager = CLLocationManager()

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// 临时申请精确位置（只在用户主动要更细的级别时调用，不主动打扰）。
    ///
    /// 返回是否真的拿到了 `fullAccuracy`：用户可以拒绝，也可能早已在系统设置里
    /// 关掉授权，所以调用方必须按返回值决定后续行为。
    ///
    /// 走 Apple 的 `requestTemporaryFullAccuracyAuthorization`（Swift 把它导入成
    /// `async throws`）。SDK 说明了它在两种情况下都会回调：用户回答之后（无错误），
    /// 以及 CoreLocation 决定**不弹**的时候（带一个 NSError，例如已在后台、
    /// 或本来就有精确位置）。拿到结果后再查一次 `accuracyAuthorization` 才算数。
    func requestTemporaryFullAccuracy() async -> Bool {
        guard LocStatus.isAuthorized else {
            requestPermission()
            return false
        }
        guard !LocStatus.isPrecise else { return true }
        do {
            try await manager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: Self.fullAccuracyPurposeKey)
        } catch {
            Log.location.info("temporary full accuracy not granted: \(String(describing: error), privacy: .public)")
            return false
        }
        return LocStatus.isPrecise
    }

    func currentLocation() async -> CLLocation? {
        // UI-test hook: makes the "no location" paths — the save confirmation and
        // the read-only location row — reachable without depending on the
        // simulator's simulated position.
        if ProcessInfo.processInfo.arguments.contains("-ui-test-no-location") {
            return nil
        }
        guard LocStatus.isAuthorized else {
            Log.location.warning("currentLocation denied")
            return nil
        }
        do {
            return try await withThrowingTaskGroup(of: CLLocation?.self) { group in
                group.addTask {
                    let updates = CLLocationUpdate.liveUpdates()
                    for try await update in updates {
                        guard let location = update.location else { continue }
                        // Apple: 负的 `horizontalAccuracy` 表示这个点的经纬度无效
                        // （室内、刚开机、被吸附失败…）。这种点写进日记只会留下
                        // 一条有坐标、没意义的位置，所以继续等下一个有效定位。
                        if location.horizontalAccuracy < 0 {
                            Log.location.warning("liveUpdates: invalid fix (negative accuracy), waiting")
                            continue
                        }
                        return location
                    }
                    return nil
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    return nil
                }
                let result = try await group.next() ?? nil
                group.cancelAll()
                return result
            }
        } catch {
            Log.location.error("liveUpdates failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func reverseGeocode(_ location: CLLocation) async -> CLPlacemark? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        // Pin the geocoder to the in-app language so the produced address text
        // does not silently follow the device locale.
        request.preferredLocale = AppLanguage.locale
        do {
            let mapItems = try await request.mapItems
            return mapItems.first?.diaryPlacemark
        } catch {
            Log.location.error("reverse geocode failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

struct LocationSnapshot {
    var latitude: Double
    var longitude: Double
    var locText: String
    var locPrecision: String
    var region: LocRegion
    var placemark: CLPlacemark?
    /// 这一次定位**最多**能记到多细：Apple 的权限与这次定位的
    /// `horizontalAccuracy` 共同决定（见 `LocationResolver.maxPrecision`）。
    ///
    /// 编辑器的精度菜单只给不粗于它的级别：系统给不了更细的位置，
    /// 就不该让用户以为自己选了个更细的级别。从库里重建的快照（编辑已有片段）
    /// 用不到它 —— 那时菜单由片段自己的地区列决定，构造时照抄自己的精度即可。
    ///
    /// **没有默认值**是故意的：漏传会让菜单悄悄退化成「只有省份」，
    /// 而这正是它第一次写出来时的 bug（编译器现在会拦住）。
    var maxPrecision: String
    /// Set only when the snapshot was rebuilt from a stored block rather than
    /// from a live lookup: the precision the block was recorded at, and the text
    /// stored for it. Going back to that level restores the text verbatim — a
    /// place name or street it contains is not kept anywhere else. `nil` here
    /// means the snapshot came from a live lookup (a brand-new block).
    var recordedPrecision: String? = nil
    var recordedText: String? = nil
}

enum LocationResolver {
    // MARK: - 精度上限（与 Apple 的定位权限对齐）

    /// 这一次定位最多能记到多细。
    ///
    /// 之前只看「有没有精确位置」：给了 `fullAccuracy` 就无条件写 `exact`，
    /// 只给模糊位置时仍然把 `city` / `district` 摆进菜单 —— 菜单比权限更细，
    /// 而且一个误差 3km 的坐标也会被标成「精确地点」。现在两档一起看：
    ///
    /// | 系统给的 | 上限 | 依据 |
    /// |---|---|---|
    /// | 模糊位置（`reducedAccuracy`） | 城市 | SDK：坐标被吸附到「所在区域」的代表点，`horizontalAccuracy` 约 5km；区县不再可信 |
    /// | 精确位置 + `horizontalAccuracy` ≤ 10m | 精确地点 | 十米级才指得到某一栋楼 |
    /// | ≤ 100m | 街道 | |
    /// | ≤ 1000m | 区县 | |
    /// | ≤ 5000m | 城市 | |
    /// | 更粗、或负值（Apple：坐标无效） | 省份 | 只有省界还站得住 |
    ///
    /// 纯函数：不读系统状态，方便按「权限 × 精度」逐格测（`LocationPrecisionTests`）。
    nonisolated static func maxPrecision(accuracyAuthorization: CLAccuracyAuthorization,
                                         horizontalAccuracy: CLLocationAccuracy) -> String {
        switch accuracyAuthorization {
        case .fullAccuracy:
            if horizontalAccuracy < 0 { return LocPrecision.province }
            if horizontalAccuracy <= 10 { return LocPrecision.exact }
            if horizontalAccuracy <= 100 { return LocPrecision.street }
            if horizontalAccuracy <= 1000 { return LocPrecision.district }
            if horizontalAccuracy <= 5000 { return LocPrecision.city }
            return LocPrecision.province
        default:
            return LocPrecision.city
        }
    }

    /// 这次记录实际用的精度。
    ///
    /// `preferred` 是用户上一次在编辑器里手动选过的级别（`AppSettings.defaultLocPrecision`，
    /// `auto` = 跟随权限）。手动选的级别只会让结果**更粗**：权限算出来的上限
    /// 永远是天花板，用户的选择不能把它顶穿。
    nonisolated static func effective(precision preferred: String, cap: String) -> String {
        guard LocPrecision.all.contains(preferred) else { return cap }
        return LocPrecision.coarser(preferred, cap)
    }

    static func resolve(location: CLLocation,
                        preferred: String = LocPrecision.auto) async -> LocationSnapshot {
        let placemark = await LocationService.shared.reverseGeocode(location)
        return snapshot(location: location, placemark: placemark, preferred: preferred,
                        accuracyAuthorization: LocStatus.accuracy)
    }

    /// 把一次定位（连同它可能有的地名）变成编辑器手里的快照。
    ///
    /// 反向地理编码留在 `resolve` 里，这里只做「权限上限 → 首选精度 → 地区列」
    /// 的纯计算，于是「新片段的菜单为什么只剩省份」这类接线问题可以在单元测试里
    /// 直接断言（`LocationPrecisionTests.testLiveSnapshotCarriesThePermissionCap`）：
    /// `maxPrecision` 就是菜单的上限，漏传它曾经让菜单退化成「只有省份」。
    nonisolated static func snapshot(location: CLLocation, placemark: CLPlacemark?,
                                     preferred: String,
                                     accuracyAuthorization: CLAccuracyAuthorization) -> LocationSnapshot {
        let cap = maxPrecision(accuracyAuthorization: accuracyAuthorization,
                               horizontalAccuracy: location.horizontalAccuracy)
        let precision = effective(precision: preferred, cap: cap)
        let region = LocRegion(
            country: placemark?.country ?? "",
            countryCode: placemark?.isoCountryCode ?? "",
            region1: placemark?.administrativeArea ?? "",
            region2: placemark?.subAdministrativeArea ?? placemark?.locality ?? "",
            region3: (placemark?.subLocality ?? "").isEmpty ? "" : (placemark?.locality != nil ? placemark?.subLocality ?? "" : ""),
            // `loc_quality` 是「这行有没有可用坐标」的标记（导入路径也按经纬度写它），
            // 不是精度：精度只走 `loc_precision`。
            locQuality: accuracyAuthorization == .fullAccuracy ? LocQuality.precise : LocQuality.coarse)
        let locText = text(for: placemark, precision: precision)
        // 一行日志把「权限 → 这一次的上限 → 实际精度」串起来：菜单里级别不对时，
        // 一眼能看出是权限、还是这次定位的 horizontalAccuracy 把它压下去了。
        Log.location.info("""
            snapshot: accuracy=\(String(describing: accuracyAuthorization), privacy: .public) \
            hAcc=\(location.horizontalAccuracy, privacy: .public) \
            cap=\(cap, privacy: .public) precision=\(precision, privacy: .public) \
            preferred=\(preferred, privacy: .public)
            """)
        return LocationSnapshot(latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude,
                                locText: locText,
                                locPrecision: precision,
                                region: region,
                                placemark: placemark,
                                maxPrecision: cap)
    }

    nonisolated static func text(for placemark: CLPlacemark?, precision: String) -> String {
        guard let pm = placemark else { return "" }
        switch precision {
        case LocPrecision.exact:
            let street = pm.thoroughfare ?? ""
            let name = pm.name ?? ""
            // MapKit commonly reports the same string as both the place name and
            // the thoroughfare ("深南大道, 深南大道"); keep one of them.
            let place: String
            if name.isEmpty {
                place = street
            } else if street.isEmpty || name.contains(street) {
                place = name
            } else if street.contains(name) {
                place = street
            } else {
                place = "\(name), \(street)"
            }
            let parts = [place, pm.locality, pm.administrativeArea, pm.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.joined(separator: " · ")
        case LocPrecision.street:
            return [pm.thoroughfare ?? pm.subLocality, pm.locality, pm.administrativeArea, pm.country]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case LocPrecision.district:
            // 区县名在 `subLocality`（中国的「南山区」就在这里），`subAdministrativeArea`
            // 是县级（美国是 county）—— 两者都没有时退到城市。此前这里**只**看
            // `subAdministrativeArea`，于是「区县」级在中国常常只显示到市，
            // 与地区列重建出来的文案（region3 · region2 · …）对不上。
            return [pm.subLocality ?? pm.subAdministrativeArea, pm.locality, pm.administrativeArea, pm.country]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case LocPrecision.city:
            return [pm.locality, pm.administrativeArea, pm.country]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        default:
            return [pm.administrativeArea, pm.country]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// Address text rebuilt from the region columns a block stores.
    ///
    /// `exact` and `street` need the place name and street, which are not
    /// stored; they fall back to the finest level the columns can express, and
    /// `LocationSnapshot.recordedText` is what callers use when the block's own
    /// precision is one of them.
    nonisolated static func text(for region: LocRegion, precision: String) -> String {
        func joined(_ parts: [String]) -> String {
            parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        switch precision {
        case LocPrecision.exact, LocPrecision.street, LocPrecision.district:
            // 没有地点名与街道，能表达的**最细**一级就是区县。
            return joined([region.region3, region.region2, region.region1, region.country])
        case LocPrecision.city:
            return joined([region.region2, region.region1, region.country])
        default:
            // 省份，以及任何不在梯子上的值：一律往最粗的一侧倒。
            return joined([region.region1, region.country])
        }
    }

    /// Precisions still choosable for a block whose location is already
    /// recorded: the levels derivable from its region columns, plus the level it
    /// was recorded at (only that text can hold a place name or street).
    ///
    /// 这里**故意不看当前权限**：地点是这条日记写下时的事实，阅读页本来就会显示
    /// 记录时的原文，菜单只是决定这条已经存在的地点按哪一级显示。权限管的是
    /// **新**记录能有多细（见 `availablePrecisions(maxPrecision:)`）。
    nonisolated static func availablePrecisions(for region: LocRegion, recorded: String) -> [String] {
        var levels: [String] = []
        if recorded == LocPrecision.exact || recorded == LocPrecision.street {
            levels.append(recorded)
        }
        if !region.region3.isEmpty { levels.append(LocPrecision.district) }
        if !region.region2.isEmpty { levels.append(LocPrecision.city) }
        levels.append(LocPrecision.province)
        return levels
    }

    /// 新建片段时菜单能给的级别：不粗于这次定位算出来的上限
    /// （`LocationSnapshot.maxPrecision`）—— 系统给不了更细的位置，
    /// 菜单里就不该有更细的级别。
    nonisolated static func availablePrecisions(maxPrecision: String) -> [String] {
        LocPrecision.levels(cappedAt: maxPrecision)
    }

    /// 分享长图上的地点文案：**只用地区列重建**，`loc_text` 根本不是它的输入。
    ///
    /// 这是「分享不会泄露地点名与街道」的硬保证。此前分享直接把库里的 `loc_text`
    /// 抄进长图，而早期版本（以及地区列没回填的记录）会把地点名/街道写在
    /// `loc_text` 里、`loc_precision` 却标着 `province` —— 只要分享走原文，
    /// 就总有一条路径会漏。改成重建之后：
    ///
    /// - 上限只取到区县（`LocPrecision.shareable`），精确地点与街道不在其中；
    /// - 记录精度比上限更粗时按记录的来 —— 分享只能更粗，不会凭空更细；
    /// - 重建为空（地区列缺失、或这行本来就没有地点）时**不显示地点**，
    ///   而不是退回原文。
    nonisolated static func shareText(recorded: String, region: LocRegion, cap: String) -> String {
        // 上限先夹到「可分享」的范围里：比区县更细、或不在梯子上的值，一律按
        // 最细的可分享级别（区县）处理。设置层 `AppSettings.normalize()` 已经挡过
        // 一次，这里是最后一道 —— 只可能更粗，不可能更细。
        let capLevel = LocPrecision.shareable.contains(cap)
            ? cap
            : (cap == LocPrecision.none ? LocPrecision.none : LocPrecision.district)
        guard capLevel != LocPrecision.none, LocPrecision.all.contains(recorded) else { return "" }
        let level = LocPrecision.coarser(recorded, capLevel)
        guard LocPrecision.all.contains(level) else { return "" }
        return text(for: region, precision: level)
    }
}
