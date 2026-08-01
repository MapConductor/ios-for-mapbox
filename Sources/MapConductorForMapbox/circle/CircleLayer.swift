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
    private var isAdded = false

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
        self.strokeLayerId = "\(layerId)-stroke"
    }

    func ensureAdded(to mapboxMap: MapboxMap) {
        guard !isAdded, !mapboxMap.sourceExists(withId: sourceId) else {
            isAdded = true
            return
        }
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        try? mapboxMap.addSource(source)

        var fillLayer = FillLayer(id: layerId, source: sourceId)
        fillLayer.fillColor = .expression(Exp(.toColor) { Exp(.get) { Prop.fillColor } })
        try? mapboxMap.addLayer(fillLayer)

        var strokeLayer = LineLayer(id: strokeLayerId, source: sourceId)
        strokeLayer.lineColor = .expression(Exp(.toColor) { Exp(.get) { Prop.strokeColor } })
        strokeLayer.lineWidth = .expression(Exp(.toNumber) { Exp(.get) { Prop.strokeWidth } })
        strokeLayer.lineJoin = .constant(.round)
        strokeLayer.lineCap = .constant(.round)
        try? mapboxMap.addLayer(strokeLayer, layerPosition: .above(layerId))

        isAdded = true
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
        isAdded = false
    }
}
