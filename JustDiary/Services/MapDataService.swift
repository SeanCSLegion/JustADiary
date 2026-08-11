import Foundation
import CoreGraphics

struct MapPoint {
    var id: Int64
    var dayKey: String
    var startTimeUtc: Int64
    var lat: Double
    var lng: Double
    var locText: String
    var locQuality: String
    var locPrecision: String
    var country: String
    var countryCode: String
    var region1: String
    var region2: String
    var region3: String
    var summary: String
    var count: Int
}

struct MapBuildResult {
    var points: [MapPoint]
    var unlocated: Int
}

struct MapBounds {
    var minLat: Double
    var maxLat: Double
    var minLng: Double
    var maxLng: Double
}

enum MapDataService {
    static func buildMapPoints(_ rows: [MapPointRow], precision: String) -> MapBuildResult {
        var withCoord: [MapPointRow] = []
        var noCoord: [MapPointRow] = []
        for row in rows {
            if row.latitude != 0 || row.longitude != 0 {
                withCoord.append(row)
            } else {
                noCoord.append(row)
            }
        }
        var cityIndex: [String: [MapPointRow]] = [:]
        var provinceIndex: [String: [MapPointRow]] = [:]
        for row in withCoord {
            let cityKey = "\(row.country)\u{1}\(row.region1)\u{1}\(row.region2)"
            let provinceKey = "\(row.country)\u{1}\(row.region1)\u{1}"
            cityIndex[cityKey, default: []].append(row)
            provinceIndex[provinceKey, default: []].append(row)
        }
        func meanCenter(_ list: [MapPointRow]) -> (lat: Double, lng: Double) {
            guard !list.isEmpty else { return (0, 0) }
            var lat = 0.0, lng = 0.0
            for r in list {
                lat += r.latitude
                lng += r.longitude
            }
            return (lat / Double(list.count), lng / Double(list.count))
        }
        var points: [MapPoint] = []
        var unlocated = 0
        if precision == "exact" {
            for row in withCoord {
                points.append(MapPoint(id: row.id, dayKey: row.dayKey, startTimeUtc: row.startTimeUtc,
                                       lat: row.latitude, lng: row.longitude, locText: row.locText,
                                       locQuality: row.locQuality, locPrecision: row.locPrecision,
                                       country: row.country, countryCode: row.countryCode,
                                       region1: row.region1, region2: row.region2, region3: row.region3,
                                       summary: row.summary, count: 1))
            }
            for row in noCoord {
                let cityKey = "\(row.country)\u{1}\(row.region1)\u{1}\(row.region2)"
                let provinceKey = "\(row.country)\u{1}\(row.region1)\u{1}"
                var center: (lat: Double, lng: Double)?
                if let list = cityIndex[cityKey], !list.isEmpty {
                    center = meanCenter(list)
                } else if let list = provinceIndex[provinceKey], !list.isEmpty {
                    center = meanCenter(list)
                }
                if let c = center {
                    points.append(MapPoint(id: row.id, dayKey: row.dayKey, startTimeUtc: row.startTimeUtc,
                                           lat: c.lat, lng: c.lng, locText: row.locText,
                                           locQuality: row.locQuality, locPrecision: row.locPrecision,
                                           country: row.country, countryCode: row.countryCode,
                                           region1: row.region1, region2: row.region2, region3: row.region3,
                                           summary: row.summary, count: 1))
                } else {
                    unlocated += 1
                }
            }
        } else {
            var grouped: [String: [MapPointRow]] = [:]
            var firstRow: [String: MapPointRow] = [:]
            for row in withCoord {
                let key: String
                if precision == "province" {
                    key = "\(row.country)\u{1}\(row.region1)\u{1}"
                } else {
                    key = "\(row.country)\u{1}\(row.region1)\u{1}\(row.region2)"
                }
                grouped[key, default: []].append(row)
                if firstRow[key] == nil { firstRow[key] = row }
            }
            for row in noCoord {
                let key: String
                if precision == "province" {
                    key = "\(row.country)\u{1}\(row.region1)\u{1}"
                } else {
                    key = "\(row.country)\u{1}\(row.region1)\u{1}\(row.region2)"
                }
                grouped[key, default: []].append(row)
                if firstRow[key] == nil { firstRow[key] = row }
            }
            for (key, list) in grouped {
                guard let f = firstRow[key] else { continue }
                let center = meanCenter(list)
                points.append(MapPoint(id: f.id, dayKey: f.dayKey, startTimeUtc: f.startTimeUtc,
                                       lat: center.lat, lng: center.lng, locText: f.locText,
                                       locQuality: f.locQuality, locPrecision: f.locPrecision,
                                       country: f.country, countryCode: f.countryCode,
                                       region1: f.region1, region2: f.region2, region3: f.region3,
                                       summary: f.summary, count: list.count))
            }
            for row in noCoord {
                let key: String
                if precision == "province" {
                    key = "\(row.country)\u{1}\(row.region1)\u{1}"
                } else {
                    key = "\(row.country)\u{1}\(row.region1)\u{1}\(row.region2)"
                }
                if grouped[key] == nil {
                    let cityKey = "\(row.country)\u{1}\(row.region1)\u{1}\(row.region2)"
                    let provinceKey = "\(row.country)\u{1}\(row.region1)\u{1}"
                    var center: (lat: Double, lng: Double)?
                    if let list = cityIndex[cityKey], !list.isEmpty {
                        center = meanCenter(list)
                    } else if let list = provinceIndex[provinceKey], !list.isEmpty {
                        center = meanCenter(list)
                    }
                    if let c = center {
                        grouped[key] = [row]
                        firstRow[key] = row
                        points.append(MapPoint(id: row.id, dayKey: row.dayKey, startTimeUtc: row.startTimeUtc,
                                               lat: c.lat, lng: c.lng, locText: row.locText,
                                               locQuality: row.locQuality, locPrecision: row.locPrecision,
                                               country: row.country, countryCode: row.countryCode,
                                               region1: row.region1, region2: row.region2, region3: row.region3,
                                               summary: row.summary, count: 1))
                    } else {
                        unlocated += 1
                    }
                }
            }
        }
        return MapBuildResult(points: points, unlocated: unlocated)
    }

    static func fitBounds(_ points: [MapPoint]) -> MapBounds? {
        guard !points.isEmpty else { return nil }
        var minLat = points[0].lat, maxLat = points[0].lat
        var minLng = points[0].lng, maxLng = points[0].lng
        for p in points {
            minLat = min(minLat, p.lat)
            maxLat = max(maxLat, p.lat)
            minLng = min(minLng, p.lng)
            maxLng = max(maxLng, p.lng)
        }
        let padLat = max((maxLat - minLat) * 0.05, 0.02)
        let padLng = max((maxLng - minLng) * 0.05, 0.02)
        return MapBounds(minLat: minLat - padLat, maxLat: maxLat + padLat,
                         minLng: minLng - padLng, maxLng: maxLng + padLng)
    }
}
