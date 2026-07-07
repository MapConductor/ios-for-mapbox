import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<[Feature]> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    let polygonLayer: PolygonLayer
    private let polygonManager: PolygonManager<[Feature]>

    init(mapView: MapView?, polygonManager: PolygonManager<[Feature]>, polygonLayer: PolygonLayer) {
        self.mapView = mapView
        self.polygonManager = polygonManager
        self.polygonLayer = polygonLayer
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        polygonLayer.ensureAdded(to: mapboxMap)
    }

    func unbind() {
        if let mapboxMap {
            polygonLayer.remove(from: mapboxMap)
        }
        mapView = nil
    }

    override func createPolygon(state: PolygonState) async -> [Feature]? {
        let resolved = state.holes.count > 1 ? state.unionHoles() : state
        let features = createMapboxPolygons(
            id: resolved.id,
            points: resolved.points,
            geodesic: resolved.geodesic,
            fillColor: resolved.fillColor,
            strokeColor: resolved.strokeColor,
            strokeWidth: resolved.strokeWidth,
            zIndex: resolved.zIndex,
            holes: resolved.holes
        )
        return features.isEmpty ? nil : features
    }

    override func updatePolygonProperties(
        polygon: [Feature],
        current: PolygonEntity<[Feature]>,
        prev: PolygonEntity<[Feature]>
    ) async -> [Feature]? {
        return await createPolygon(state: current.state)
    }

    override func removePolygon(entity: PolygonEntity<[Feature]>) async {
    }

    override func onPostProcess() async {
        guard let mapboxMap else { return }
        let features = polygonManager.allEntities().flatMap { $0.polygon ?? [] }
        polygonLayer.setFeatures(features, mapboxMap: mapboxMap)
    }
}
