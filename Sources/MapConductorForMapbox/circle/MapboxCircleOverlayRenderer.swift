import CoreLocation
import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxCircleOverlayRenderer: AbstractCircleOverlayRenderer<Feature> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    let circleLayer: CircleLayer
    private let circleManager: CircleManager<Feature>

    init(mapView: MapView?, circleManager: CircleManager<Feature>, circleLayer: CircleLayer) {
        self.mapView = mapView
        self.circleManager = circleManager
        self.circleLayer = circleLayer
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        circleLayer.ensureAdded(to: mapboxMap)
    }

    func unbind() {
        guard let mapboxMap else { return }
        circleLayer.remove(from: mapboxMap)
        mapView = nil
    }

    override func createCircle(state: CircleState) async -> Feature? {
        makeFeature(for: state)
    }

    override func updateCircleProperties(
        circle: Feature,
        current: CircleEntity<Feature>,
        prev: CircleEntity<Feature>
    ) async -> Feature? {
        makeFeature(for: current.state)
    }

    override func removeCircle(entity: CircleEntity<Feature>) async {}

    override func onPostProcess() async {
        guard let mapboxMap else { return }
        let features = circleManager.allEntities().compactMap { entity -> Feature? in
            let updated = makeFeature(for: entity.state)
            entity.circle = updated
            return updated
        }
        circleLayer.setFeatures(features, mapboxMap: mapboxMap)
    }

    // MARK: - Helper

    /// The core `circleToRing` generates the ring. The ring is unwrapped (continuous
    /// longitudes around the center), and Mapbox GL accepts longitudes beyond +/-180, so a
    /// circle crossing the antimeridian renders as a single polygon without splitting.
    private func makeFeature(for state: CircleState) -> Feature {
        let ring = closeRing(circleToRing(
            center: state.center,
            radiusMeters: state.radiusMeters,
            geodesic: state.geodesic
        ))
        let coords = ring.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        var feature = Feature(geometry: .polygon(Turf.Polygon(outerRing: Ring(coordinates: coords), innerRings: [])))
        feature.identifier = .string("circle-\(state.id)")
        feature.properties = [
            CircleLayer.Prop.fillColor: .string(state.fillColor.toMapboxColorString()),
            CircleLayer.Prop.strokeColor: .string(state.strokeColor.toMapboxColorString()),
            CircleLayer.Prop.strokeWidth: .number(state.strokeWidth),
            CircleLayer.Prop.circleId: .string(state.id)
        ]
        return feature
    }
}
