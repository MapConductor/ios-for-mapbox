import Foundation
import MapboxMaps

final class CircleLayer {
    enum Prop {
        static let radiusPixels = "radiusPixels"
        static let fillColor = "fillColor"
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let circleId = "circle_id"
    }

    let sourceId: String
    let layerId: String
    private var isAdded = false

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }

    func ensureAdded(to mapboxMap: MapboxMap) {
        guard !isAdded, !mapboxMap.sourceExists(withId: sourceId) else {
            isAdded = true
            return
        }
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        try? mapboxMap.addSource(source)

        var layer = MapboxMaps.CircleLayer(id: layerId, source: sourceId)
        layer.circleRadius = .expression(Exp(.toNumber) { Exp(.get) { Prop.radiusPixels } })
        layer.circleColor = .expression(Exp(.toColor) { Exp(.get) { Prop.fillColor } })
        layer.circleStrokeColor = .expression(Exp(.toColor) { Exp(.get) { Prop.strokeColor } })
        layer.circleStrokeWidth = .expression(Exp(.toNumber) { Exp(.get) { Prop.strokeWidth } })
        try? mapboxMap.addLayer(layer)
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
        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
        isAdded = false
    }
}
