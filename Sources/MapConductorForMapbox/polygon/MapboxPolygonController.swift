import CoreLocation
import MapboxMaps
import MapConductorCore

/// ポリゴンの状態を集めるのは `OverlayCollector`（`MapOverlayScope.polygonCollector`）で、
/// `bindOverlayCollector` がここへ `add(data:)` / `update(state:)` を流す。
/// コントローラは購読も差分も持たない。
///
/// 以前はここに `syncPolygons` という自前の差分ループがあったが、コレクタ移行で
/// 呼び出し元が無くなっていた（`updateContent` はコレクタに `sync` する）。
/// `latestStates` / `isStyleLoaded` / 個別購読もその名残だったので落とした。
///
/// クラスタのハル用にもう 1 インスタンス使われる（`hullPolygonController`）。そちらは
/// コレクタではなく `polygonSyncHandlers` 経由で `add(data:)` される。
@MainActor
final class MapboxPolygonController: PolygonController<[Feature], MapboxPolygonOverlayRenderer> {
    init(mapView: MapView?) {
        let polygonManager = PolygonManager<[Feature]>()
        let layer = PolygonLayer(
            sourceId: "mapconductor-polygons-source-\(UUID().uuidString)",
            fillLayerId: "mapconductor-polygons-fill-\(UUID().uuidString)",
            lineLayerId: "mapconductor-polygons-line-\(UUID().uuidString)"
        )
        let renderer = MapboxPolygonOverlayRenderer(
            mapView: mapView,
            polygonManager: polygonManager,
            polygonLayer: layer
        )
        super.init(polygonManager: polygonManager, renderer: renderer)
    }

    /// スタイルが載るたびに呼ばれる。捨てられたソース／レイヤを作り直してから、
    /// **マネージャ**を元に描き直す（`onPostProcess` が `allEntities()` を読む）。
    ///
    /// android-for-mapbox が `subscribeStyleLoaded` の中で
    /// `attachOverlaySourcesAndLayers` → `redraw()` をやっているのと同じ形。
    /// マップ側の `polygonCollector.flush()` も同じ集合を流し直すが、`add` は冪等なので重ならない。
    /// クラスタのハル用インスタンスはコレクタを通らないため、こちらの経路が要る。
    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        renderer.onStyleLoaded(mapboxMap)
        Task { [weak self] in
            await self?.renderer.onPostProcess()
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = find(position: position) else { return false }
        dispatchClick(event: PolygonEvent(state: hit.state, clicked: position))
        return true
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}
