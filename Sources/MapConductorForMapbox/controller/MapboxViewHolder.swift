import CoreGraphics
import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore
import UIKit

final class MapboxViewHolder: MapViewHolderProtocol {
    typealias ActualMapView = MapView
    typealias ActualMap = MapboxMap

    let mapView: MapView
    var map: MapboxMap { mapView.mapboxMap }

    init(mapView: MapView) {
        self.mapView = mapView
    }

    func toScreenOffset(position: any GeoPointProtocol) -> CGPoint? {
        let coord = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        let point = mapView.mapboxMap.point(for: coord)
        guard point.x.isFinite && point.y.isFinite else { return nil }
        return point
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        fromScreenOffsetSync(offset: offset)
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        let coord = mapView.mapboxMap.coordinate(for: offset)
        return GeoPoint(latitude: coord.latitude, longitude: coord.longitude, altitude: 0)
    }
}
