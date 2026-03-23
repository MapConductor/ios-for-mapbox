import CoreLocation
import MapboxMaps
import MapConductorCore
import UIKit

func createMapboxPolygons(
    id: String,
    points: [GeoPointProtocol],
    geodesic: Bool,
    fillColor: UIColor,
    strokeColor: UIColor,
    strokeWidth: Double,
    zIndex: Int = 0,
    holes: [[GeoPointProtocol]] = []
) -> [Feature] {
    let interpolated: [GeoPointProtocol] = (geodesic
        ? createInterpolatePoints(points, maxSegmentLength: 1000.0)
        : createLinearInterpolatePoints(points))
        .map { $0.normalize() }

    let innerRings: [Ring] = holes.compactMap { holePoints in
        guard !holePoints.isEmpty else { return nil }
        var ring = holePoints.map { $0.normalize() }
        if let first = ring.first, let last = ring.last,
           !(GeoPoint.from(position: first) == GeoPoint.from(position: last)) {
            ring.append(first)
        }
        return Ring(coordinates: ring.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
    }

    return splitByMeridian(interpolated, geodesic: geodesic).enumerated().map { index, ringPoints in
        // Close the ring if needed
        var ring = ringPoints
        if let first = ring.first, let last = ring.last,
           !(GeoPoint.from(position: first) == GeoPoint.from(position: last)) {
            ring.append(first)
        }
        let coords = ring.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polygon = Turf.Polygon(outerRing: Ring(coordinates: coords), innerRings: innerRings)
        let fid = "polygon-\(id)-\(index)"
        var feature = Feature(geometry: .polygon(polygon))
        feature.identifier = .string(fid)
        feature.properties = [
            PolygonLayer.Prop.fillColor: .string(fillColor.toMapboxColorString()),
            PolygonLayer.Prop.strokeColor: .string(strokeColor.toMapboxColorString()),
            PolygonLayer.Prop.strokeWidth: .number(strokeWidth),
            PolygonLayer.Prop.zIndex: .number(Double(zIndex)),
            PolygonLayer.Prop.polygonId: .string(id)
        ]
        return feature
    }
}
