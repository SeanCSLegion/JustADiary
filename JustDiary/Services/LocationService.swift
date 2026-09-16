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

    static var isAuthorized: Bool {
        let status = current()
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static var isPrecise: Bool {
        isAuthorized && (statusManager.accuracyAuthorization == .fullAccuracy)
    }
}

final class LocationService {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
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
                        if let location = update.location {
                            return location
                        }
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
    /// Set only when the snapshot was rebuilt from a stored block rather than
    /// from a live lookup: the precision the block was recorded at, and the text
    /// stored for it. Going back to that level restores the text verbatim — a
    /// place name or street it contains is not kept anywhere else. `nil` here
    /// means the snapshot came from a live lookup (a brand-new block).
    var recordedPrecision: String? = nil
    var recordedText: String? = nil
}

enum LocationResolver {
    static func resolve(location: CLLocation) async -> LocationSnapshot {
        let placemark = await LocationService.shared.reverseGeocode(location)
        let precise = LocStatus.isPrecise
        let precision = precise ? LocPrecision.exact : LocPrecision.province
        let region = LocRegion(
            country: placemark?.country ?? "",
            countryCode: placemark?.isoCountryCode ?? "",
            region1: placemark?.administrativeArea ?? "",
            region2: placemark?.subAdministrativeArea ?? placemark?.locality ?? "",
            region3: (placemark?.subLocality ?? "").isEmpty ? "" : (placemark?.locality != nil ? placemark?.subLocality ?? "" : ""),
            locQuality: precise ? LocQuality.precise : LocQuality.coarse)
        let locText = Self.text(for: placemark, precision: precision)
        return LocationSnapshot(latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude,
                                locText: locText,
                                locPrecision: precision,
                                region: region,
                                placemark: placemark)
    }

    static func text(for placemark: CLPlacemark?, precision: String) -> String {
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
            return [pm.subAdministrativeArea, pm.locality, pm.administrativeArea, pm.country]
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
    static func text(for region: LocRegion, precision: String) -> String {
        func joined(_ parts: [String]) -> String {
            parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        switch precision {
        case LocPrecision.city:
            return joined([region.region2, region.region1, region.country])
        case LocPrecision.province:
            return joined([region.region1, region.country])
        default:
            return joined([region.region3, region.region2, region.region1, region.country])
        }
    }

    /// Precisions still choosable for a block whose location is already
    /// recorded: the levels derivable from its region columns, plus the level it
    /// was recorded at (only that text can hold a place name or street).
    static func availablePrecisions(for region: LocRegion, recorded: String) -> [String] {
        var levels: [String] = []
        if recorded == LocPrecision.exact || recorded == LocPrecision.street {
            levels.append(recorded)
        }
        if !region.region3.isEmpty { levels.append(LocPrecision.district) }
        if !region.region2.isEmpty { levels.append(LocPrecision.city) }
        levels.append(LocPrecision.province)
        return levels
    }

    static func availablePrecisions() -> [String] {
        if LocStatus.isAuthorized, LocStatus.isPrecise {
            return LocPrecision.all
        }
        return [LocPrecision.province, LocPrecision.city, LocPrecision.district]
    }
}
