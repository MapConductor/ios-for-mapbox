import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<MapboxRasterLayer> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    init(mapView: MapView?) {
        self.mapView = mapView
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {}

    func unbind() { mapView = nil }

    // MARK: - Sync operations (used by controller)

    func createLayerSync(state: RasterLayerState) -> MapboxRasterLayer? {
        RasterHeaderRuleSet.warnUnsupported(provider: "Mapbox", state: state)
        guard let mapboxMap else { return nil }
        let sourceId = "mapconductor-raster-source-\(state.id)"
        let layerId = "mapconductor-raster-layer-\(state.id)"

        removeIfExists(mapboxMap: mapboxMap, sourceId: sourceId, layerId: layerId)
        addRasterLayer(mapboxMap: mapboxMap, sourceId: sourceId, layerId: layerId, state: state)
        return MapboxRasterLayer(sourceId: sourceId, layerId: layerId)
    }

    func updateLayerSync(
        layer: MapboxRasterLayer,
        current: RasterLayerEntity<MapboxRasterLayer>,
        prev: RasterLayerEntity<MapboxRasterLayer>
    ) -> MapboxRasterLayer? {
        guard let mapboxMap else { return layer }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.source != prevFinger.source {
            removeIfExists(mapboxMap: mapboxMap, sourceId: layer.sourceId, layerId: layer.layerId)
            return createLayerSync(state: current.state)
        }
        if finger.debug != prevFinger.debug && current.state.debug {
            NSLog("[MapConductor] RasterLayer debug mode: id=%@", current.state.id)
        }
        if finger.zIndex != prevFinger.zIndex {
            try? mapboxMap.moveLayer(withId: layer.layerId, to: current.state.zIndex > 0 ? .at(current.state.zIndex) : .default)
        }
        if finger.opacity != prevFinger.opacity {
            try? mapboxMap.updateLayer(withId: layer.layerId, type: MapboxMaps.RasterLayer.self) { l in
                l.rasterOpacity = .constant(current.state.opacity)
            }
        }
        if finger.visible != prevFinger.visible {
            try? mapboxMap.updateLayer(withId: layer.layerId, type: MapboxMaps.RasterLayer.self) { l in
                l.visibility = .constant(current.state.visible ? .visible : .none)
            }
        }
        return layer
    }

    func removeLayerSync(entity: RasterLayerEntity<MapboxRasterLayer>) {
        guard let mapboxMap, let layer = entity.layer else { return }
        removeIfExists(mapboxMap: mapboxMap, sourceId: layer.sourceId, layerId: layer.layerId)
    }

    // MARK: - AbstractRasterLayerOverlayRenderer

    override func createLayer(state: RasterLayerState) async -> MapboxRasterLayer? {
        createLayerSync(state: state)
    }

    override func updateLayerProperties(
        layer: MapboxRasterLayer,
        current: RasterLayerEntity<MapboxRasterLayer>,
        prev: RasterLayerEntity<MapboxRasterLayer>
    ) async -> MapboxRasterLayer? {
        updateLayerSync(layer: layer, current: current, prev: prev)
    }

    override func removeLayer(entity: RasterLayerEntity<MapboxRasterLayer>) async {
        removeLayerSync(entity: entity)
    }

    // MARK: - Private

    private func addRasterLayer(
        mapboxMap: MapboxMap,
        sourceId: String,
        layerId: String,
        state: RasterLayerState
    ) {
        switch state.source {
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, _):
            var source = RasterSource(id: sourceId)
            source.tiles = [template]
            source.tileSize = Double(tileSize)
            if let minZoom { source.minzoom = Double(minZoom) }
            if let maxZoom { source.maxzoom = Double(maxZoom) }
            try? mapboxMap.addSource(source)
        default:
            return
        }

        if state.debug {
            NSLog("[MapConductor] RasterLayer debug mode: id=%@", state.id)
        }
        var layer = MapboxMaps.RasterLayer(id: layerId, source: sourceId)
        layer.rasterOpacity = .constant(state.opacity)
        layer.visibility = .constant(state.visible ? .visible : .none)
        let layerPosition: LayerPosition = state.zIndex > 0 ? .at(state.zIndex) : .default
        try? mapboxMap.addLayer(layer, layerPosition: layerPosition)
    }

    private func removeIfExists(mapboxMap: MapboxMap, sourceId: String, layerId: String) {
        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
    }
}
