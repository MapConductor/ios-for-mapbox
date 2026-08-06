import CoreLocation
import MapboxMaps
import MapConductorCore

/// ポリラインの状態を集めるのは `OverlayCollector`（`MapOverlayScope.polylineCollector`）で、
/// `bindOverlayCollector` がここへ `add(data:)` / `update(state:)` を流す。
/// コントローラは購読も差分も持たない。
///
/// 以前はここに `syncPolylines` という自前の差分ループがあったが、コレクタ移行で
/// 呼び出し元が無くなっていた（`updateContent` はコレクタに `sync` する）。
/// `latestStates` / `isStyleLoaded` / 個別購読もその名残だったので落とした。
@MainActor
final class MapboxPolylineController: PolylineController<[Feature], MapboxPolylineOverlayRenderer> {
    init(mapView: MapView?) {
        let polylineManager = PolylineManager<[Feature]>()
        let layer = PolylineLayer(
            sourceId: "mapconductor-polylines-source-\(UUID().uuidString)",
            layerId: "mapconductor-polylines-layer-\(UUID().uuidString)"
        )
        let renderer = MapboxPolylineOverlayRenderer(
            mapView: mapView,
            polylineManager: polylineManager,
            polylineLayer: layer
        )
        super.init(polylineManager: polylineManager, renderer: renderer)
    }

    /// スタイルが載るたびに呼ばれる。捨てられたソース／レイヤを作り直してから、
    /// **マネージャ**を元に描き直す（`onPostProcess` が `allEntities()` を読む）。
    ///
    /// android-for-mapbox が `subscribeStyleLoaded` の中で
    /// `attachOverlaySourcesAndLayers` → `redraw()` をやっているのと同じ形。
    /// マップ側の `polylineCollector.flush()` も同じ集合を流し直すが、`add` は冪等なので重ならない。
    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        renderer.onStyleLoaded(mapboxMap)
        Task { [weak self] in
            await self?.renderer.onPostProcess()
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = findWithClosestPoint(position: position) else { return false }
        dispatchClick(event: PolylineEvent(state: hit.entity.state, clicked: hit.closestPoint))
        return true
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}
