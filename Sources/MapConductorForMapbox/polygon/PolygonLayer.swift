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
    private var isAdded = false

    init(sourceId: String, fillLayerId: String, lineLayerId: String) {
        self.sourceId = sourceId
        self.fillLayerId = fillLayerId
        self.lineLayerId = lineLayerId
    }

    func ensureAdded(to mapboxMap: MapboxMap) {
        guard !isAdded, !mapboxMap.sourceExists(withId: sourceId) else {
            isAdded = true
            return
        }
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        try? mapboxMap.addSource(source)

        var fillLayer = FillLayer(id: fillLayerId, source: sourceId)
        fillLayer.fillColor = .expression(Exp(.toColor) { Exp(.get) { Prop.fillColor } })
        try? mapboxMap.addLayer(fillLayer)

        var lineLayer = LineLayer(id: lineLayerId, source: sourceId)
        lineLayer.lineColor = .expression(Exp(.toColor) { Exp(.get) { Prop.strokeColor } })
        lineLayer.lineWidth = .expression(Exp(.toNumber) { Exp(.get) { Prop.strokeWidth } })
        lineLayer.lineJoin = .constant(.round)
        lineLayer.lineCap = .constant(.round)
        try? mapboxMap.addLayer(lineLayer)

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
        if mapboxMap.layerExists(withId: lineLayerId) { try? mapboxMap.removeLayer(withId: lineLayerId) }
        if mapboxMap.layerExists(withId: fillLayerId) { try? mapboxMap.removeLayer(withId: fillLayerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
        isAdded = false
    }
}
