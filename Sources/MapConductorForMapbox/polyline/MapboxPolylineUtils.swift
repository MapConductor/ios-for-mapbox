import CoreLocation
import MapboxMaps
import MapConductorCore
import UIKit

func createMapboxLines(
    id: String,
    points: [GeoPointProtocol],
    geodesic: Bool,
    strokeColor: UIColor,
    strokeWidth: Double,
    zIndex: Int = 0
) -> [Feature] {
    // Mapbox GL accepts longitudes beyond +/-180, so an unwrapped (continuous-longitude)
    // path renders seamlessly across the antimeridian without splitting.
    let path = buildUnwrappedPolylinePath(points, geodesic: geodesic, maxSegmentLength: 1000.0)
    guard !path.isEmpty else { return [] }

    let coords = path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    let fid = "polyline-\(id)-0"
    var feature = Feature(geometry: .lineString(LineString(coords)))
    feature.identifier = .string(fid)
    feature.properties = [
        PolylineLayer.Prop.strokeColor: .string(strokeColor.toMapboxColorString()),
        PolylineLayer.Prop.strokeWidth: .number(strokeWidth),
        PolylineLayer.Prop.zIndex: .number(Double(zIndex)),
        PolylineLayer.Prop.polylineId: .string(id)
    ]
    return [feature]
}
