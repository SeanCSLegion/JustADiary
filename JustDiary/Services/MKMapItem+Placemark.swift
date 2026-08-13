import MapKit
import CoreLocation

// MKMapItem.placemark is deprecated in iOS 26 in favor of location/address/addressRepresentations.
// However MKAddress/MKAddressRepresentations only expose city/region level data; the granular
// fields (administrativeArea/subAdministrativeArea/subLocality/locality/thoroughfare/country)
// required for the map footprint aggregation have no replacement. Keep one documented accessor.
extension MKMapItem {
    var diaryPlacemark: CLPlacemark? {
        placemark
    }
}
