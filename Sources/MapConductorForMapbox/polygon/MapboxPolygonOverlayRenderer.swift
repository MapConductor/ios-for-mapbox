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

    /// 複数の穴が重なっている場合は結合（union）して重複を解消する。
    /// 他プロバイダ（ArcGIS/MapLibre/HERE/Google）と同じ `unionHoles()` を用いる。
    ///
    /// Mapbox は Polygon の inner ring で複数の穴を描けるが、偶奇規則なので重なった穴は
    /// 打ち消し合い、重なり部分が塗られてしまう。コンポーネント層（`Polygon`）のユニオンは
    /// state 1 インスタンスにつき 1 回きりで、頂点ドラッグ後の `state.holes` 差し替えには
    /// 追従しないため、android-for-mapbox と同じくここでも結合する。
    private func resolveHoles(_ state: PolygonState) -> PolygonState {
        state.holes.count > 1 ? state.unionHoles() : state
    }

    override func createPolygon(state: PolygonState) async -> [Feature]? {
        let resolved = resolveHoles(state)
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
