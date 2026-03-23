import Foundation
import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<MapboxGroundImageHandle> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }
    private let tileServer: LocalTileServer

    init(mapView: MapView?) {
        self.mapView = mapView
        self.tileServer = TileServerRegistry.get()
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {}

    func unbind() { mapView = nil }

    // MARK: - Sync helpers

    func createGroundImageSync(state: GroundImageState) -> MapboxGroundImageHandle? {
        guard let mapboxMap else { return nil }
        let routeId = buildSafeRouteId(state.id)
        let provider = GroundImageTileProvider(tileSize: state.tileSize)
        provider.update(state: state, opacity: 1.0)
        tileServer.register(routeId: routeId, provider: provider)

        let sourceId = "mapconductor-groundimage-source-\(routeId)"
        let layerId = "mapconductor-groundimage-layer-\(routeId)"

        removeSourceAndLayerIfExists(mapboxMap: mapboxMap, sourceId: sourceId, layerId: layerId)

        let tileTemplate = tileServer.urlTemplate(routeId: routeId, version: 0)
        addRasterLayer(mapboxMap: mapboxMap, sourceId: sourceId, layerId: layerId, tileTemplate: tileTemplate, tileSize: state.tileSize, opacity: state.opacity)

        return MapboxGroundImageHandle(
            routeId: routeId,
            version: 0,
            sourceId: sourceId,
            layerId: layerId,
            tileProvider: provider
        )
    }

    func updateGroundImageSync(
        groundImage: MapboxGroundImageHandle,
        current: GroundImageEntity<MapboxGroundImageHandle>,
        prev: GroundImageEntity<MapboxGroundImageHandle>
    ) -> MapboxGroundImageHandle? {
        guard let mapboxMap else { return groundImage }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // Opacity only change
        if finger.opacity != prevFinger.opacity,
           finger.bounds == prevFinger.bounds,
           finger.image == prevFinger.image,
           finger.tileSize == prevFinger.tileSize {
            try? mapboxMap.updateLayer(withId: groundImage.layerId, type: RasterLayer.self) { layer in
                layer.rasterOpacity = .constant(current.state.opacity)
            }
            return groundImage
        }

        // Content change: recreate
        let provider: GroundImageTileProvider
        if finger.tileSize != prevFinger.tileSize {
            provider = GroundImageTileProvider(tileSize: current.state.tileSize)
            tileServer.register(routeId: groundImage.routeId, provider: provider)
        } else {
            provider = groundImage.tileProvider
        }
        provider.update(state: current.state, opacity: 1.0)

        let nextVersion = groundImage.version + 1
        let tileTemplate = tileServer.urlTemplate(routeId: groundImage.routeId, version: nextVersion)

        removeSourceAndLayerIfExists(mapboxMap: mapboxMap, sourceId: groundImage.sourceId, layerId: groundImage.layerId)
        addRasterLayer(
            mapboxMap: mapboxMap,
            sourceId: groundImage.sourceId,
            layerId: groundImage.layerId,
            tileTemplate: tileTemplate,
            tileSize: current.state.tileSize,
            opacity: current.state.opacity
        )

        return MapboxGroundImageHandle(
            routeId: groundImage.routeId,
            version: nextVersion,
            sourceId: groundImage.sourceId,
            layerId: groundImage.layerId,
            tileProvider: provider
        )
    }

    func removeGroundImageSync(entity: GroundImageEntity<MapboxGroundImageHandle>) {
        guard let mapboxMap, let handle = entity.groundImage else { return }
        removeSourceAndLayerIfExists(mapboxMap: mapboxMap, sourceId: handle.sourceId, layerId: handle.layerId)
        tileServer.unregister(routeId: handle.routeId)
    }

    // MARK: - AbstractGroundImageOverlayRenderer

    override func createGroundImage(state: GroundImageState) async -> MapboxGroundImageHandle? {
        createGroundImageSync(state: state)
    }

    override func updateGroundImageProperties(
        groundImage: MapboxGroundImageHandle,
        current: GroundImageEntity<MapboxGroundImageHandle>,
        prev: GroundImageEntity<MapboxGroundImageHandle>
    ) async -> MapboxGroundImageHandle? {
        updateGroundImageSync(groundImage: groundImage, current: current, prev: prev)
    }

    override func removeGroundImage(entity: GroundImageEntity<MapboxGroundImageHandle>) async {
        removeGroundImageSync(entity: entity)
    }

    // MARK: - Private

    private func addRasterLayer(
        mapboxMap: MapboxMap,
        sourceId: String,
        layerId: String,
        tileTemplate: String,
        tileSize: Int,
        opacity: Double
    ) {
        var source = RasterSource(id: sourceId)
        source.tiles = [tileTemplate]
        source.tileSize = Double(tileSize)
        source.minzoom = 0
        source.maxzoom = 22
        try? mapboxMap.addSource(source)

        var layer = RasterLayer(id: layerId, source: sourceId)
        layer.rasterOpacity = .constant(min(max(opacity, 0.0), 1.0))
        try? mapboxMap.addLayer(layer)
    }

    private func removeSourceAndLayerIfExists(mapboxMap: MapboxMap, sourceId: String, layerId: String) {
        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
    }

    private func buildSafeRouteId(_ id: String) -> String {
        var out = "groundimage-"
        for ch in id {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { out.append(ch) }
            else { out.append("_") }
        }
        return out
    }
}
