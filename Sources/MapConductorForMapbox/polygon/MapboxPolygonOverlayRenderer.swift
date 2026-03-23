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
        guard let mapboxMap else { return }
        polygonLayer.remove(from: mapboxMap)
        mapView = nil
    }

    override func createPolygon(state: PolygonState) async -> [Feature]? {
        createMapboxPolygons(
            id: state.id,
            points: state.points,
            geodesic: state.geodesic,
            fillColor: state.fillColor,
            strokeColor: state.strokeColor,
            strokeWidth: state.strokeWidth,
            zIndex: state.zIndex,
            holes: state.holes
        )
    }

    override func updatePolygonProperties(
        polygon: [Feature],
        current: PolygonEntity<[Feature]>,
        prev: PolygonEntity<[Feature]>
    ) async -> [Feature]? {
        createMapboxPolygons(
            id: current.state.id,
            points: current.state.points,
            geodesic: current.state.geodesic,
            fillColor: current.state.fillColor,
            strokeColor: current.state.strokeColor,
            strokeWidth: current.state.strokeWidth,
            zIndex: current.state.zIndex,
            holes: current.state.holes
        )
    }

    override func removePolygon(entity: PolygonEntity<[Feature]>) async {}

    override func onPostProcess() async {
        guard let mapboxMap else { return }
        let features = polygonManager.allEntities().flatMap { $0.polygon ?? [] }
        polygonLayer.setFeatures(features, mapboxMap: mapboxMap)
    }
}
