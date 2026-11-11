import Foundation
import MapboxMaps
@_spi(MapConductorDriver) import MapConductorCore

final class MarkerLayer {
    enum Prop {
        static let markerId = "marker_id"
        static let iconId = "icon_id"
        static let iconOffsetX = "icon_offset_x"
        static let iconOffsetY = "icon_offset_y"
        static let isHidden = "is_hidden"
        /// 重なり順（``MarkerDrawOrder``）。レイヤーの `symbolSortKey` が読む。大きいほど手前。
        static let sortKey = "sort_key"
        static let defaultMarkerId = "mapconductor_default_marker"
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
    /// ソースが二度と作り直されずマーカーが消えたままになっていた（実機の
    /// MapboxStyleReloadUITests が検出）。
    ///
    /// 真実はスタイル側にしかないので毎回 `sourceExists` / `layerExists` を見る。
    /// android-for-mapbox が `subscribeStyleLoaded` のたびに
    /// `attachOverlaySourcesAndLayers(style)` を無条件で呼び直しているのと同じ考え方。
    func ensureAdded(to mapboxMap: MapboxMap) {
        if !mapboxMap.sourceExists(withId: sourceId) {
            addSource(to: mapboxMap)
        }
        if !mapboxMap.layerExists(withId: layerId) {
            addLayer(to: mapboxMap)
        }
    }

    private func addSource(to mapboxMap: MapboxMap) {
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        try? mapboxMap.addSource(source)
    }

    private func addLayer(to mapboxMap: MapboxMap) {
        var layer = SymbolLayer(id: layerId, source: sourceId)
        layer.iconImage = .expression(Exp(.get) { Prop.iconId })
        layer.iconAnchor = .constant(.bottom)
        layer.iconAllowOverlap = .constant(true)
        layer.textAllowOverlap = .constant(true)
        // 重なり順は sort_key（zIndex → 南 → 西）。足した順には頼らない。
        layer.symbolSortKey = .expression(Exp(.get) { Prop.sortKey })
        layer.iconOffset = .expression(
            Exp(.array) {
                "number"
                2
                Exp(.get) { Prop.iconOffsetX }
                Exp(.get) { Prop.iconOffsetY }
            }
        )
        // Hide markers with is_hidden == 1
        layer.visibility = .constant(.visible)
        layer.iconOpacity = .expression(
            Exp(.switchCase) {
                Exp(.eq) { Exp(.get) { Prop.isHidden }; 1 }
                Double(0)
                Double(1)
            }
        )
        MapboxOverlayStacking.add(layer, OverlayStackKey(.marker), to: mapboxMap)
    }

    func setFeatures(_ features: [Feature], mapboxMap: MapboxMap) {
        guard mapboxMap.sourceExists(withId: sourceId) else { return }
        try? mapboxMap.updateGeoJSONSource(
            withId: sourceId,
            geoJSON: .featureCollection(FeatureCollection(features: features))
        )
    }

    func remove(from mapboxMap: MapboxMap) {
        if mapboxMap.layerExists(withId: layerId) {
            try? mapboxMap.removeLayer(withId: layerId)
        }
        if mapboxMap.sourceExists(withId: sourceId) {
            try? mapboxMap.removeSource(withId: sourceId)
        }
    }
}
