import Combine
import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxRasterLayerController: RasterLayerController<MapboxRasterLayer, MapboxRasterLayerOverlayRenderer> {
    private var rasterSubscriptions: [String: AnyCancellable] = [:]
    private var rasterStatesById: [String: RasterLayerState] = [:]
    private var latestStates: [RasterLayerState] = []
    private var isStyleLoaded = false

    init(mapView: MapView?) {
        let rasterManager = RasterLayerManager<MapboxRasterLayer>()
        let renderer = MapboxRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        isStyleLoaded = true
        renderer.onStyleLoaded(mapboxMap)
        if !latestStates.isEmpty { syncDirectly(latestStates) }
    }

    func syncRasterLayers(_ layers: [MapConductorCore.RasterLayer]) {
        let newIds = Set(layers.map { $0.id })
        let oldIds = Set(rasterStatesById.keys)
        var newStatesById: [String: RasterLayerState] = [:]
        var shouldSync = false

        for layer in layers {
            let state = layer.state
            if let existing = rasterStatesById[state.id], existing !== state {
                rasterSubscriptions[state.id]?.cancel()
                rasterSubscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !rasterLayerManager.hasEntity(state.id) { shouldSync = true }
        }

        if !shouldSync {
            for (id, newState) in newStatesById {
                if let entity = rasterLayerManager.getEntity(id),
                   entity.fingerPrint != newState.fingerPrint() {
                    shouldSync = true
                    break
                }
            }
        }

        rasterStatesById = newStatesById
        latestStates = layers.map { $0.state }
        if oldIds != newIds { shouldSync = true }

        for layer in layers { subscribeToRasterLayer(layer.state) }

        for id in oldIds.subtracting(newIds) {
            rasterSubscriptions[id]?.cancel()
            rasterSubscriptions.removeValue(forKey: id)
        }

        guard isStyleLoaded, shouldSync else { return }
        syncDirectly(layers.map { $0.state })
    }

    private func syncDirectly(_ states: [RasterLayerState]) {
        let previous = Set(rasterLayerManager.allEntities().map { $0.state.id })
        let newIds = Set(states.map { $0.id })

        for id in previous.subtracting(newIds) {
            if let entity = rasterLayerManager.getEntity(id) {
                renderer.removeLayerSync(entity: entity)
                _ = rasterLayerManager.removeEntity(id)
            }
        }

        for state in states {
            if let prevEntity = rasterLayerManager.getEntity(state.id) {
                if prevEntity.fingerPrint != state.fingerPrint() {
                    if let updated = renderer.updateLayerSync(
                        layer: prevEntity.layer!,
                        current: RasterLayerEntity(layer: prevEntity.layer, state: state),
                        prev: prevEntity
                    ) {
                        rasterLayerManager.registerEntity(RasterLayerEntity(layer: updated, state: state))
                    }
                }
            } else {
                if let newLayer = renderer.createLayerSync(state: state) {
                    rasterLayerManager.registerEntity(RasterLayerEntity(layer: newLayer, state: state))
                }
            }
        }
    }

    override func onCameraChanged(mapCameraPosition: MapCameraPosition) async {}

    private func subscribeToRasterLayer(_ state: RasterLayerState) {
        guard rasterSubscriptions[state.id] == nil else { return }
        rasterSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.rasterStatesById[state.id] != nil, self.isStyleLoaded else { return }
                self.syncDirectly(self.latestStates)
            }
    }

    func unbind() {
        rasterSubscriptions.values.forEach { $0.cancel() }
        rasterSubscriptions.removeAll()
        rasterStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        destroy()
    }
}
