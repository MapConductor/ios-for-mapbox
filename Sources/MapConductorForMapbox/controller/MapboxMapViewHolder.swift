import CoreGraphics
import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore
import UIKit

public final class MapboxMapViewHolder: MapViewHolderProtocol {
    public typealias ActualMapView = MapView
    public typealias ActualMap = MapboxMap

    public let mapView: MapView
    public var map: MapboxMap { mapView.mapboxMap }

    init(mapView: MapView) {
        self.mapView = mapView
    }

    public func toScreenOffset(position: any GeoPointProtocol) -> CGPoint? {
        let coord = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        let point = mapView.mapboxMap.point(for: coord)
        guard point.x.isFinite && point.y.isFinite else { return nil }
        return point
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        let coord = mapView.mapboxMap.coordinate(for: offset)
        return GeoPoint(latitude: coord.latitude, longitude: coord.longitude, altitude: 0)
    }
}
