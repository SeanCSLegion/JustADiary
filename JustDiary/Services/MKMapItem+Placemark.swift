import MapKit
import CoreLocation

// MKMapItem.placemark is deprecated in iOS 26 in favor of location/address/
// addressRepresentations. However the replacement API (MKAddress /
// MKAddressRepresentations) intentionally exposes only presentation-oriented
// values (full/short address strings, cityName, regionName, regionCode) and
// exposes NO structured country / administrativeArea / subAdministrativeArea /
// subLocality / thoroughfare fields, and no country code field at all. Verified
// against the iOS 27 SDK headers and by reverse/forward geocoding Chinese
// addresses on macOS 27.
//
// The footprint aggregation (country / province / city) and locText in this app
// rely on those granular region fields, so there is no functionally equivalent
// non-deprecated replacement. Apple's own DTS guidance discourages hand-parsing
// the formatted address strings, which would silently produce wrong province
// aggregation if Apple ever changes the format.
//
// Keep this one documented accessor as the single intentional use, and silence
// exactly this diagnostic with @diagnose (SE-0522) rather than suppressing
// deprecation warnings project-wide.
extension MKMapItem {
    @diagnose(DeprecatedDeclaration, as: ignored,
              reason: "MKAddressRepresentations exposes no administrativeArea/subLocality; province and district aggregation require CLPlacemark")
    var diaryPlacemark: CLPlacemark? {
        placemark
    }
}
