import MapKit

extension MKMapItem {
    var diaryPlacemark: CLPlacemark? {
        value(forKey: "placemark") as? CLPlacemark
    }
}
