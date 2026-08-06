import Foundation
import MapboxMaps

final class PolygonLayer {
    enum Prop {
        static let fillColor = "fillColor"
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let zIndex = "zIndex"
        static let polygonId = "polygon_id"
    }

    let sourceId: String
    let fillLayerId: String
    let lineLayerId: String

    init(sourceId: String, fillLayerId: String, lineLayerId: String) {
        self.sourceId = sourceId
        self.fillLayerId = fillLayerId
        self.lineLayerId = lineLayerId
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

        if !mapboxMap.layerExists(withId: fillLayerId) {
            var fillLayer = FillLayer(id: fillLayerId, source: sourceId)
            fillLayer.fillColor = .expression(Exp(.toColor) { Exp(.get) { Prop.fillColor } })
            try? mapboxMap.addLayer(fillLayer)
        }

        if !mapboxMap.layerExists(withId: lineLayerId) {
            var lineLayer = LineLayer(id: lineLayerId, source: sourceId)
            lineLayer.lineColor = .expression(Exp(.toColor) { Exp(.get) { Prop.strokeColor } })
            lineLayer.lineWidth = .expression(Exp(.toNumber) { Exp(.get) { Prop.strokeWidth } })
            lineLayer.lineJoin = .constant(.round)
            lineLayer.lineCap = .constant(.round)
            try? mapboxMap.addLayer(lineLayer)
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
        if mapboxMap.layerExists(withId: lineLayerId) { try? mapboxMap.removeLayer(withId: lineLayerId) }
        if mapboxMap.layerExists(withId: fillLayerId) { try? mapboxMap.removeLayer(withId: fillLayerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
    }
}
