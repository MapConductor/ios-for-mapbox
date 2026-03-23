import Combine
import CoreGraphics
import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxMarkerController: AbstractMarkerController<Feature, MapboxMarkerRenderer> {
    private weak var mapView: MapView?

    private var markerSubscriptions: [String: AnyCancellable] = [:]
    private var markerStatesById: [String: MarkerState] = [:]
    private var latestStates: [MarkerState] = []
    private var isStyleLoaded = false

    let onUpdateInfoBubble: (String) -> Void

    // MARK: - Marker tiling

    var tilingOptions: MarkerTilingOptions = .Default
    private var tileRenderer: MarkerTileRenderer<Feature>?
    private var tileRouteId: String?
    private var tileVersion: Int64 = 0
    private var tiledMarkerIds: Set<String> = []
    private var tileSourceId: String?
    private var tileLayerId: String?
    private let defaultMarkerIconForTiling: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    init(mapView: MapView?, onUpdateInfoBubble: @escaping (String) -> Void) {
        self.mapView = mapView
        self.onUpdateInfoBubble = onUpdateInfoBubble

        let markerManager = MarkerManager<Feature>.defaultManager()
        let layer = MarkerLayer(
            sourceId: "mapconductor-markers-source-\(UUID().uuidString)",
            layerId: "mapconductor-markers-layer-\(UUID().uuidString)"
        )
        let renderer = MapboxMarkerRenderer(mapView: mapView, markerManager: markerManager, markerLayer: layer)
        super.init(markerManager: markerManager, renderer: renderer)
        setupTileRenderer()
    }

    private func setupTileRenderer() {
        let routeId = "mapconductor-markers-\(UUID().uuidString)"
        let renderer = MarkerTileRenderer<Feature>(
            markerManager: markerManager,
            tileSize: 256,
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            iconScaleCallback: tilingOptions.iconScaleCallback
        )
        TileServerRegistry.get().register(routeId: routeId, provider: renderer)
        tileRenderer = renderer
        tileRouteId = routeId
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        isStyleLoaded = true
        renderer.onStyleLoaded(mapboxMap)
        // Re-attach tile raster layer if there are already tiled markers
        if !tiledMarkerIds.isEmpty {
            updateTileLayer(mapboxMap: mapboxMap, hasTiledMarkers: true)
        }
        if !latestStates.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }
    }

    func syncMarkers(_ markers: [Marker]) {
        let newIds = Set(markers.map { $0.id })
        let oldIds = Set(markerStatesById.keys)

        var newStatesById: [String: MarkerState] = [:]
        var shouldSyncList = false

        for marker in markers {
            let state = marker.state
            if let existing = markerStatesById[state.id], existing !== state {
                markerSubscriptions[state.id]?.cancel()
                markerSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !markerManager.hasEntity(state.id) { shouldSyncList = true }
        }

        markerStatesById = newStatesById
        latestStates = markers.map { $0.state }
        if oldIds != newIds { shouldSyncList = true }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for marker in markers {
            subscribeToMarker(marker.state)
            onUpdateInfoBubble(marker.id)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }
    }

    override func find(position: any GeoPointProtocol) -> MarkerEntity<Feature>? {
        markerManager.findNearest(position: position)
    }

    func handleTap(at point: CGPoint) -> Bool {
        guard let mapView else { return false }
        var tapped = false
        let options = RenderedQueryOptions(layerIds: [renderer.markerLayer.layerId], filter: nil)
        let sema = DispatchSemaphore(value: 0)
        mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
            defer { sema.signal() }
            guard let self else { return }
            if case .success(let features) = result,
               let first = features.first,
               let markerId = first.queriedFeature.feature.properties?[MarkerLayer.Prop.markerId]??.rawValue as? String,
               let entity = self.markerManager.getEntity(markerId),
               entity.state.clickable {
                self.dispatchClick(state: entity.state)
                tapped = true
            }
        }
        sema.wait()
        return tapped
    }

    func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        // Drag support: not implemented yet - future work
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    func getIcon(for state: MarkerState) -> BitmapIcon {
        (state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
    }

    override func add(data: [MarkerState]) async {
        guard tilingOptions.enabled else {
            await super.add(data: data)
            return
        }

        let shouldTileAll = data.count >= tilingOptions.minMarkerCount
        var localTiledMarkerIds = tiledMarkerIds
        let result = await MarkerIngestionEngine.ingest(
            data: data,
            markerManager: markerManager,
            renderer: renderer,
            defaultMarkerIcon: defaultMarkerIconForTiling,
            tilingEnabled: tilingOptions.enabled,
            tiledMarkerIds: &localTiledMarkerIds,
            shouldTile: { [shouldTileAll] _ in shouldTileAll }
        )
        tiledMarkerIds = localTiledMarkerIds

        if result.tiledDataChanged, let tileRenderer {
            tileRenderer.invalidate()
            tileVersion += 1
            if let mapboxMap = mapView?.mapboxMap {
                updateTileLayer(mapboxMap: mapboxMap, hasTiledMarkers: result.hasTiledMarkers)
            }
        }
    }

    private func updateTileLayer(mapboxMap: MapboxMap, hasTiledMarkers: Bool) {
        guard let routeId = tileRouteId else { return }
        let server = TileServerRegistry.get()
        let urlTemplate = server.urlTemplate(routeId: routeId, version: tileVersion)
        let sourceId = tileSourceId ?? "mapconductor-tile-markers-source-\(routeId)"
        let layerId = tileLayerId ?? "mapconductor-tile-markers-layer-\(routeId)"
        tileSourceId = sourceId
        tileLayerId = layerId

        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }

        guard hasTiledMarkers else { return }

        var source = RasterSource(id: sourceId)
        source.tiles = [urlTemplate]
        source.tileSize = 256
        try? mapboxMap.addSource(source)

        let layer = RasterLayer(id: layerId, source: sourceId)
        try? mapboxMap.addLayer(layer)
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        markerSubscriptions[state.id] = state.asFlow()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.markerStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                    self.onUpdateInfoBubble(state.id)
                }
            }
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        if let routeId = tileRouteId {
            TileServerRegistry.get().unregister(routeId: routeId)
        }
        tileRenderer = nil
        tileRouteId = nil
        tiledMarkerIds.removeAll()
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
