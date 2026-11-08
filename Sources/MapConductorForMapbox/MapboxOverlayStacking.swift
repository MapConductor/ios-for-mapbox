import Foundation
import MapboxMaps
@_spi(MapConductorDriver) import MapConductorCore

/// オーバーレイのレイヤを、重なり順の帯（``OverlayBand``）の位置へ置くための `LayerPosition`。
///
/// 下から ラスター < グラウンドイメージ < ポリゴン < サークル < ポリライン < マーカー。
/// 追加した順・送り直した順・デザイン変更の後の作り直しの順に左右されない。
/// 以前は各描画担当が `addLayer(_:)`（一番上に積む）で足していたので、後から足したもの
/// （clearOverlays の後に送り直したグラウンドイメージなど）が上に来ていた。
///
/// ラスターだけはベースマップのラベルの下に置く（ラベルを覆わないため。従来どおり）。
/// Standard スタイルのようにベースマップが import でトップレベルのレイヤを持たないときは
/// 天井が見つからず、ほかのオーバーレイより下という帯の条件だけで置く。
enum MapboxOverlayStacking {
    static func position(
        for key: OverlayStackKey,
        in mapboxMap: MapboxMap,
        excluding layerId: String? = nil,
        rasterZIndex: [String: Int] = [:]
    ) -> LayerPosition {
        let layers = mapboxMap.allLayerIdentifiers.filter { $0.id != layerId }
        let keys: [OverlayStackKey?] = layers.map { info in
            guard let band = OverlayStacking.band(ofStyleLayerId: info.id) else { return nil }
            return OverlayStackKey(band, zIndex: band == .rasterLayer ? (rasterZIndex[info.id] ?? 0) : 0)
        }
        let ceiling = key.band == .rasterLayer
            ? layers.firstIndex { $0.type == .symbol && OverlayStacking.band(ofStyleLayerId: $0.id) == nil }
            : nil
        let index = OverlayStacking.insertionIndex(for: key, among: keys, ceiling: ceiling)
        return index >= layers.count ? .default : .below(layers[index].id)
    }

    static func add(_ layer: any Layer, _ key: OverlayStackKey, to mapboxMap: MapboxMap) {
        try? mapboxMap.addLayer(layer, layerPosition: position(for: key, in: mapboxMap))
    }
}
