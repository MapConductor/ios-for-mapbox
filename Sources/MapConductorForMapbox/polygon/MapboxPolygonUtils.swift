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
    // Mapbox GL accepts longitudes beyond +/-180, so the unwrapped rings render as a
    // single polygon (with all holes preserved) even across the antimeridian.
    let rings = buildUnwrappedPolygonRings(
        points: points,
        holes: holes,
        geodesic: geodesic,
        maxSegmentLength: 1000.0
    )
    guard let outerRing = rings.outerRings.first else { return [] }

    let innerRings: [Ring] = rings.holeRings.map { holeRing in
        let ring = closeRing(ensureClockwiseRing(holeRing))
        return Ring(coordinates: ring.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
    }

    let coords = closeRing(outerRing).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    let polygon = Turf.Polygon(outerRing: Ring(coordinates: coords), innerRings: innerRings)
    let fid = "polygon-\(id)-0"
    var feature = Feature(geometry: .polygon(polygon))
    feature.identifier = .string(fid)
    feature.properties = [
        PolygonLayer.Prop.fillColor: .string(fillColor.toMapboxColorString()),
        PolygonLayer.Prop.strokeColor: .string(strokeColor.toMapboxColorString()),
        PolygonLayer.Prop.strokeWidth: .number(strokeWidth),
        PolygonLayer.Prop.zIndex: .number(Double(zIndex)),
        PolygonLayer.Prop.polygonId: .string(id)
    ]
    return [feature]
}
