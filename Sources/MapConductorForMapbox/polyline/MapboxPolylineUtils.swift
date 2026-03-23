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
    let interpolated: [GeoPointProtocol] = (geodesic
        ? createInterpolatePoints(points, maxSegmentLength: 1000.0)
        : createLinearInterpolatePoints(points))
        .map { $0.normalize() }

    return splitByMeridian(interpolated, geodesic: geodesic).enumerated().map { index, linePoints in
        let coords = linePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let fid = "polyline-\(id)-\(index)"
        var feature = Feature(geometry: .lineString(LineString(coords)))
        feature.identifier = .string(fid)
        feature.properties = [
            PolylineLayer.Prop.strokeColor: .string(strokeColor.toMapboxColorString()),
            PolylineLayer.Prop.strokeWidth: .number(strokeWidth),
            PolylineLayer.Prop.zIndex: .number(Double(zIndex)),
            PolylineLayer.Prop.polylineId: .string(id)
        ]
        return feature
    }
}
