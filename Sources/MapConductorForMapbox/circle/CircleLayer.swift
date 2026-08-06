import Foundation
import MapboxMaps

/// Draws circles as "fill (FillLayer) + stroke (LineLayer)".
///
/// Circles were previously drawn with a native CircleLayer (screen-pixel radius expression),
/// but that cannot express geodesic circles (rings equidistant along great circles, which are
/// not perfect circles in Mercator). Instead the ring polygon produced by the core
/// `circleToRing` is rendered, matching the polygon layer plumbing.
final class CircleLayer {
    enum Prop {
        static let fillColor = "fillColor"
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let circleId = "circle_id"
    }

    let sourceId: String
    /// Fill layer keeps the historical `layerId` so existing ordering anchors stay valid.
    let layerId: String
    let strokeLayerId: String

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
        self.strokeLayerId = "\(layerId)-stroke"
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
            var fillLayer = FillLayer(id: layerId, source: sourceId)
            fillLayer.fillColor = .expression(Exp(.toColor) { Exp(.get) { Prop.fillColor } })
            try? mapboxMap.addLayer(fillLayer)
        }

        if !mapboxMap.layerExists(withId: strokeLayerId) {
            var strokeLayer = LineLayer(id: strokeLayerId, source: sourceId)
            strokeLayer.lineColor = .expression(Exp(.toColor) { Exp(.get) { Prop.strokeColor } })
            strokeLayer.lineWidth = .expression(Exp(.toNumber) { Exp(.get) { Prop.strokeWidth } })
            strokeLayer.lineJoin = .constant(.round)
            strokeLayer.lineCap = .constant(.round)
            try? mapboxMap.addLayer(strokeLayer, layerPosition: .above(layerId))
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
        if mapboxMap.layerExists(withId: strokeLayerId) { try? mapboxMap.removeLayer(withId: strokeLayerId) }
        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
    }
}
