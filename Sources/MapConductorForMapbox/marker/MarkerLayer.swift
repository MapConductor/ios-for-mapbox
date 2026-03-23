import Foundation
import MapboxMaps

final class MarkerLayer {
    enum Prop {
        static let markerId = "marker_id"
        static let iconId = "icon_id"
        static let iconOffsetX = "icon_offset_x"
        static let iconOffsetY = "icon_offset_y"
        static let isHidden = "is_hidden"
        static let defaultMarkerId = "mapconductor_default_marker"
    }

    let sourceId: String
    let layerId: String

    private var isAdded = false

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }

    func ensureAdded(to mapboxMap: MapboxMap) {
        guard !isAdded else { return }
        guard !mapboxMap.sourceExists(withId: sourceId) else {
            isAdded = true
            return
        }

        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        try? mapboxMap.addSource(source)

        var layer = SymbolLayer(id: layerId, source: sourceId)
        layer.iconImage = .expression(Exp(.get) { Prop.iconId })
        layer.iconAnchor = .constant(.bottom)
        layer.iconAllowOverlap = .constant(true)
        layer.textAllowOverlap = .constant(true)
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
        if mapboxMap.layerExists(withId: layerId) {
            try? mapboxMap.removeLayer(withId: layerId)
        }
        if mapboxMap.sourceExists(withId: sourceId) {
            try? mapboxMap.removeSource(withId: sourceId)
        }
        isAdded = false
    }
}
