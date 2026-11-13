import Foundation
import MapConductorCore
import MapboxMaps

/**
 Changes a loaded Mapbox style in place.

 The seven calls ``StyleMutationTarget`` asks for, against Mapbox's style
 API. Everything above them — what a mutation means, which can be skipped,
 keeping one bad property from costing the rest — is `applyStyleMutations`
 in core, shared with every other provider.

 ## Why the compiler's JSON goes almost straight through

 Mapbox keeps a generic door open: `setLayerProperty(for:property:value:)`
 takes the spec's own property name and any JSON-shaped value, and
 `addLayer(with:layerPosition:)` takes a whole layer as a dictionary. Paint
 keys, layout keys, `filter`, `minzoom` and `maxzoom` all go through that one
 call, so the text the compiler produced reaches the renderer as the value it
 describes and nothing here has to decide what shape it is.

 MapLibre here has no such door, which is why `MapLibreStyleMutationTarget`
 is longer for the same seven calls. The adapters differ; the decisions above
 them do not. The Android Mapbox adapter is this one's twin.
 */
struct MapboxStyleMutationTarget: StyleMutationTarget {
    /**
     The map, read through a closure rather than captured.

     Every design change replaces the loaded style, and a target holding the
     old one would patch a style the map has already dropped.
     */
    let map: () -> MapboxMap?

    var isReady: Bool { map() != nil }

    func hasLayer(_ layerId: String) -> Bool {
        map()?.layerExists(withId: layerId) ?? false
    }

    func setPaint(_ layerId: String, _ key: String, _ valueJson: String) throws {
        try set(layerId, key, valueJson)
    }

    /// Mapbox does not split paint from layout on this call: both are the
    /// spec's property name on the layer.
    func setLayout(_ layerId: String, _ key: String, _ valueJson: String) throws {
        try set(layerId, key, valueJson)
    }

    func setFilter(_ layerId: String, _ filterJson: String) throws {
        try set(layerId, "filter", filterJson)
    }

    func setZoomRange(_ layerId: String, _ minZoom: Double, _ maxZoom: Double) throws {
        guard let map = map() else { return }
        // Both ends, because the caller always sends both -- a mutation that
        // moves one has to restate the other to be undoable.
        try map.setLayerProperty(for: layerId, property: "minzoom", value: minZoom)
        try map.setLayerProperty(for: layerId, property: "maxzoom", value: maxZoom)
    }

    func addLayer(_ layerId: String, _ layerJson: String, _ beforeId: String?) throws {
        guard let map = map() else { return }
        // Already there: the style was reloaded and the whole set is going
        // back on.
        guard !map.layerExists(withId: layerId) else { return }
        guard let properties = try value(of: layerJson) as? [String: Any] else {
            throw StyleMutationFailure.notALayer(layerId)
        }
        // `beforeId` is the layer to go *under*, matching the style
        // document's own order -- earlier in the list is drawn first.
        let position: LayerPosition =
            beforeId.flatMap { map.layerExists(withId: $0) ? LayerPosition.below($0) : nil }
                ?? .default
        try map.addLayer(with: properties, layerPosition: position)
    }

    func removeLayer(_ layerId: String) throws {
        guard let map = map(), map.layerExists(withId: layerId) else { return }
        try map.removeLayer(withId: layerId)
    }

    private func set(_ layerId: String, _ key: String, _ valueJson: String) throws {
        guard let map = map() else { return }
        try map.setLayerProperty(for: layerId, property: key, value: value(of: valueJson))
    }

    /**
     A mutation's value, which travels as JSON text, as the `Any` Mapbox
     wants.

     `.fragmentsAllowed` because most values are not objects or arrays: a
     colour is a bare string and an opacity a bare number.
     */
    private func value(of json: String) throws -> Any {
        guard let data = json.data(using: .utf8) else {
            throw StyleMutationFailure.notAValue(json)
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

/// What this adapter refuses, so core can report it rather than guess.
enum StyleMutationFailure: Error {
    case notAValue(String)
    case notALayer(String)
}
