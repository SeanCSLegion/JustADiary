import CoreLocation
import Foundation
import MapKit

enum LocStatus {
    static func current() -> CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    static var isAuthorized: Bool {
        let status = current()
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static var isPrecise: Bool {
        isAuthorized && (CLLocationManager().accuracyAuthorization == .fullAccuracy)
    }

    static func requestPermission() {
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()
    }
}

final class LocationService: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    @Published private(set) var state: String = "idle"

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func currentLocation() async -> CLLocation? {
        guard LocStatus.isAuthorized else { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.continuation?.resume(returning: nil)
                self?.continuation = nil
            }
        }
    }

    func reverseGeocode(_ location: CLLocation) async -> (placemark: CLPlacemark?, error: Error?) {
        guard let request = MKReverseGeocodingRequest(location: location) else { return (nil, nil) }
        do {
            let mapItems = try await request.mapItems
            return (mapItems.first?.diaryPlacemark, nil)
        } catch {
            return (nil, error)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        state = "authorized"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
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
        let placemark = (await LocationService.shared.reverseGeocode(location)).placemark
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
