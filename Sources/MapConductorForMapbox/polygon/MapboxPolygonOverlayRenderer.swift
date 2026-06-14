import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<[Feature]> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    let polygonLayer: PolygonLayer
    private let polygonManager: PolygonManager<[Feature]>
    private var masks: [String: MapboxMaskHandle] = [:]

    init(mapView: MapView?, polygonManager: PolygonManager<[Feature]>, polygonLayer: PolygonLayer) {
        self.mapView = mapView
        self.polygonManager = polygonManager
        self.polygonLayer = polygonLayer
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        polygonLayer.ensureAdded(to: mapboxMap)
        // Re-register raster sources/layers for any existing masks after style reload
        for (_, handle) in masks {
            addMaskLayer(to: mapboxMap, handle: handle)
        }
    }

    func unbind() {
        masks.values.forEach { TileServerRegistry.get().unregister(routeId: $0.routeId) }
        masks.removeAll()
        if let mapboxMap {
            polygonLayer.remove(from: mapboxMap)
        }
        mapView = nil
    }

    override func createPolygon(state: PolygonState) async -> [Feature]? {
        if state.holes.isEmpty {
            removeMask(id: state.id)
            return createMapboxPolygons(
                id: state.id,
                points: state.points,
                geodesic: state.geodesic,
                fillColor: state.fillColor,
                strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth,
                zIndex: state.zIndex,
                holes: []
            )
        } else {
            ensureMask(state: state)
            return createMapboxPolygons(
                id: state.id,
                points: state.points,
                geodesic: state.geodesic,
                fillColor: .clear,
                strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth,
                zIndex: state.zIndex,
                holes: []
            )
        }
    }

    override func updatePolygonProperties(
        polygon: [Feature],
        current: PolygonEntity<[Feature]>,
        prev: PolygonEntity<[Feature]>
    ) async -> [Feature]? {
        return await createPolygon(state: current.state)
    }

    override func removePolygon(entity: PolygonEntity<[Feature]>) async {
        removeMask(id: entity.state.id)
    }

    override func onPostProcess() async {
        guard let mapboxMap else { return }
        let features = polygonManager.allEntities().flatMap { $0.polygon ?? [] }
        polygonLayer.setFeatures(features, mapboxMap: mapboxMap)
    }

    // MARK: - Mask (raster tile overlay for hole polygons)

    private func ensureMask(state: PolygonState) {
        let id = state.id
        if let existing = masks[id] {
            existing.tileRenderer.update(
                points: state.points,
                holes: state.holes,
                fillColor: state.fillColor,
                geodesic: state.geodesic
            )
            return
        }

        let tileRenderer = PolygonRasterTileRenderer(tileSize: 256)
        tileRenderer.update(
            points: state.points,
            holes: state.holes,
            fillColor: state.fillColor,
            geodesic: state.geodesic
        )

        let routeId = "polygon-raster-\(safeId(id))"
        let cacheKey = String(abs(routeId.hashValue))
        let tileServer = TileServerRegistry.get(forceNoStoreCache: true)
        tileServer.register(routeId: routeId, provider: tileRenderer)
        let urlTemplate = tileServer.urlTemplate(routeId: routeId, tileSize: 256, cacheKey: cacheKey)
        let sourceId = "mapconductor-polygon-mask-source-\(safeId(id))"
        let layerId = "mapconductor-polygon-mask-layer-\(safeId(id))"

        let handle = MapboxMaskHandle(
            routeId: routeId,
            tileRenderer: tileRenderer,
            sourceId: sourceId,
            layerId: layerId,
            urlTemplate: urlTemplate
        )
        masks[id] = handle

        if let mapboxMap {
            addMaskLayer(to: mapboxMap, handle: handle)
        }
    }

    private func addMaskLayer(to mapboxMap: MapboxMap, handle: MapboxMaskHandle) {
        if mapboxMap.layerExists(withId: handle.layerId) {
            try? mapboxMap.removeLayer(withId: handle.layerId)
        }
        if mapboxMap.sourceExists(withId: handle.sourceId) {
            try? mapboxMap.removeSource(withId: handle.sourceId)
        }

        var source = RasterSource(id: handle.sourceId)
        source.tiles = [handle.urlTemplate]
        source.tileSize = 256
        source.minzoom = 0
        source.maxzoom = 22
        try? mapboxMap.addSource(source)

        let rasterLayer = RasterLayer(id: handle.layerId, source: handle.sourceId)
        // Insert above polygon fill layer but below line (stroke) layer
        try? mapboxMap.addLayer(rasterLayer, layerPosition: .above(polygonLayer.fillLayerId))
    }

    private func removeMask(id: String) {
        guard let handle = masks.removeValue(forKey: id) else { return }
        TileServerRegistry.get().unregister(routeId: handle.routeId)
        if let mapboxMap {
            if mapboxMap.layerExists(withId: handle.layerId) {
                try? mapboxMap.removeLayer(withId: handle.layerId)
            }
            if mapboxMap.sourceExists(withId: handle.sourceId) {
                try? mapboxMap.removeSource(withId: handle.sourceId)
            }
        }
    }

    private func safeId(_ id: String) -> String {
        id.map { ch in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" ? String(ch) : "_"
        }.joined()
    }
}

private struct MapboxMaskHandle {
    let routeId: String
    let tileRenderer: PolygonRasterTileRenderer
    let sourceId: String
    let layerId: String
    let urlTemplate: String
}
