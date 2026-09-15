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
            let parts = [name.isEmpty ? street : (street.isEmpty ? name : "\(name), \(street)"),
                         pm.locality, pm.administrativeArea, pm.country]
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

    static func availablePrecisions() -> [String] {
        if LocStatus.isAuthorized, LocStatus.isPrecise {
            return LocPrecision.all
        }
        return [LocPrecision.province, LocPrecision.city, LocPrecision.district]
    }
}
