import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<[Feature]> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    let polylineLayer: PolylineLayer
    private let polylineManager: PolylineManager<[Feature]>

    init(mapView: MapView?, polylineManager: PolylineManager<[Feature]>, polylineLayer: PolylineLayer) {
        self.mapView = mapView
        self.polylineManager = polylineManager
        self.polylineLayer = polylineLayer
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        polylineLayer.ensureAdded(to: mapboxMap)
    }

    func unbind() {
        guard let mapboxMap else { return }
        polylineLayer.remove(from: mapboxMap)
        mapView = nil
    }

    override func createPolyline(state: PolylineState) async -> [Feature]? {
        createMapboxLines(
            id: state.id,
            points: state.points,
            geodesic: state.geodesic,
            strokeColor: state.strokeColor,
            strokeWidth: state.strokeWidth,
            zIndex: (state.extra as? Int) ?? 0
        )
    }

    override func updatePolylineProperties(
        polyline: [Feature],
        current: PolylineEntity<[Feature]>,
        prev: PolylineEntity<[Feature]>
    ) async -> [Feature]? {
        createMapboxLines(
            id: current.state.id,
            points: current.state.points,
            geodesic: current.state.geodesic,
            strokeColor: current.state.strokeColor,
            strokeWidth: current.state.strokeWidth,
            zIndex: (current.state.extra as? Int) ?? 0
        )
    }

    override func removePolyline(entity: PolylineEntity<[Feature]>) async {}

    override func onPostProcess() async {
        guard let mapboxMap else { return }
        guard !polylineManager.isDestroyed else { return }
        let features = polylineManager.allEntities().flatMap { $0.polyline ?? [] }
        polylineLayer.setFeatures(features, mapboxMap: mapboxMap)
    }
}
