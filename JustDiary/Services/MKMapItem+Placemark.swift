import MapKit
import CoreLocation

// MKMapItem.placemark is deprecated in iOS 26 in favor of location/address
// /addressRepresentations. However the replacement API (MKAddress / MKAddressRepresentations)
// intentionally exposes only presentation-oriented values (full/short address strings,
// cityName, regionName, regionCode) and exposes NO structured country /
// administrativeArea / subAdministrativeArea / subLocality / thoroughfare fields, and no
// country field at all. The map-footprint aggregation and locText in this app rely on
// those granular region fields, so there is no functionally equivalent non-deprecated
// replacement. Keep this one documented accessor as the single intentional use.
extension MKMapItem {
    var diaryPlacemark: CLPlacemark? {
        placemark
    }
}
