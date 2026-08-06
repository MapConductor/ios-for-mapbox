import Foundation
import MapboxMaps

final class PolylineLayer {
    enum Prop {
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let zIndex = "zIndex"
        static let polylineId = "polyline_id"
    }

    let sourceId: String
    let layerId: String

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }

    /// スタイルにソースとレイヤが載っていることを保証する。
    ///
    /// **「一度足した」を自前のフラグで覚えてはいけない。** `loadStyle`（地図デザインの
    /// 変更）はランタイムに足したソース／レイヤをすべて捨てるので、フラグは即座に嘘になる。
    /// 以前は `isAdded` を持っていて、デザインを切り替えるとここが早期 return し、
    /// オーバーレイが二度と描かれなくなっていた（実機の MapboxStyleReloadUITests が検出）。
    ///
    /// 真実はスタイル側にしかないので毎回 `sourceExists` / `layerExists` を見る。
    /// android-for-mapbox が `subscribeStyleLoaded` のたびに
    /// `attachOverlaySourcesAndLayers(style)` を無条件で呼び直しているのと同じ考え方。
    func ensureAdded(to mapboxMap: MapboxMap) {
        if !mapboxMap.sourceExists(withId: sourceId) {
            var source = GeoJSONSource(id: sourceId)
            source.data = .featureCollection(FeatureCollection(features: []))
            try? mapboxMap.addSource(source)
        }

        if !mapboxMap.layerExists(withId: layerId) {
            var layer = LineLayer(id: layerId, source: sourceId)
            layer.lineColor = .expression(Exp(.toColor) { Exp(.get) { Prop.strokeColor } })
            layer.lineWidth = .expression(Exp(.toNumber) { Exp(.get) { Prop.strokeWidth } })
            layer.lineJoin = .constant(.round)
            layer.lineCap = .constant(.round)
            try? mapboxMap.addLayer(layer)
        }
    }

    func setFeatures(_ features: [Feature], mapboxMap: MapboxMap) {
        guard mapboxMap.sourceExists(withId: sourceId) else { return }
        try? mapboxMap.updateGeoJSONSource(
            withId: sourceId,
            geoJSON: .featureCollection(FeatureCollection(features: features))
        )
    }

    func remove(from mapboxMap: MapboxMap) {
        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
    }
}
